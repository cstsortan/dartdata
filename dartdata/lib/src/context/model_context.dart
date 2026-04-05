import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../annotations/relationship.dart';
import '../query/query.dart';
import '../schema/schema.dart';
import '../storage/external_file.dart';
import 'model_container.dart';

/// A unit of work that tracks inserts, updates, and deletes in memory and
/// flushes them to SQLite on [save].
///
/// Obtain a context from a [ModelContainer]:
/// ```dart
/// final context = ModelContext(container);
/// ```
///
/// Or inside a Flutter widget tree via the inherited widget:
/// ```dart
/// final context = ModelContext.of(buildContext);
/// ```
class ModelContext {
  final ModelContainer container;

  final List<_PendingOperation> _pending = [];
  final _controller = StreamController<ContextChangeSet>.broadcast(sync: true);

  /// Descriptor lookup by runtime Type — O(1) instead of linear scan.
  late final Map<Type, ModelDescriptor> _descriptorsByType = {
    for (final d in container.schema.descriptors) d.modelType: d,
  };

  /// Version cache: `tableName:id` → z_opt value at fetch time.
  final Map<String, int> _versions = {};

  /// Reverse relationship index: parent tableName → list of (child descriptor, relationship).
  /// Pre-computed to avoid O(D*R) scan per delete.
  late final Map<String, List<_ChildRelationship>> _reverseRelationships = _buildReverseIndex();

  /// Cached SQL templates per descriptor tableName.
  late final Map<String, _SqlTemplates> _sqlTemplates = {
    for (final d in container.schema.descriptors) d.tableName: _SqlTemplates.from(d),
  };

  ModelContext(this.container);

  // -------------------------------------------------------------------------
  // Write operations
  // -------------------------------------------------------------------------

  /// Stage [model] for insertion on the next [save].
  void insert(covariant Object model) {
    _pending.add(_PendingOperation(_OperationType.insert, model));
  }

  /// Stage [model] for deletion on the next [save].
  void delete(covariant Object model) {
    _pending.add(_PendingOperation(_OperationType.delete, model));
  }

  /// Discard all pending inserts, updates, and deletes.
  void rollback() => _pending.clear();

  /// Flush all pending operations to SQLite.
  ///
  /// Runs inside a single transaction. On failure, all changes are rolled
  /// back and [save] can be retried safely.
  Future<void> save() async {
    if (_pending.isEmpty) return;

    final db = container.db;
    final versionSnapshot = Map<String, int>.of(_versions);
    db.execute('BEGIN');

    try {
      // Enforce delete rules inside the transaction so that:
      // 1. Deny throws are caught, triggering ROLLBACK and leaving _pending
      //    intact for retry or manual rollback().
      // 2. Cascade SELECTs and deny COUNTs read a consistent snapshot.
      final preDeleteSql = _enforceDeleteRules();

      // Execute any nullify UPDATEs queued by delete rule enforcement.
      for (final sql in preDeleteSql) {
        db.execute(sql.statement, sql.arguments);
      }

      for (final op in _pending) {
        await _execute(op, db);
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      _versions
        ..clear()
        ..addAll(versionSnapshot);
      rethrow;
    }

    final affected = List<_PendingOperation>.from(_pending);
    _pending.clear();

    // Notify observers of the change set.
    _notifyChanges(affected);
  }

  /// Execute a single pending operation against the database.
  Future<void> _execute(_PendingOperation op, Database db) async {
    final descriptor = _descriptorFor(op.model);
    final map = descriptor.toMap(op.model);
    final templates = _sqlTemplates[descriptor.tableName]!;

    // Validate that toMap() keys match the descriptor's declared columns.
    final declaredColumns = {for (final c in descriptor.columns) c.columnName};
    final unknownKeys = map.keys.where((k) => !declaredColumns.contains(k));
    if (unknownKeys.isNotEmpty) {
      throw StateError(
        'toMap() returned unknown columns $unknownKeys for ${descriptor.modelClassName}. '
        'Allowed: $declaredColumns',
      );
    }

    // Resolve FK UUIDs → z_pk integers for relationship columns.
    _resolveRelationshipFks(op.model, descriptor, map);

    switch (op.type) {
      case _OperationType.insert:
        // Persist any staged ExternalFile fields first.
        await _persistExternalFiles(op.model, descriptor, map);

        final id = map['id'] as String;
        final vKey = '${descriptor.tableName}:$id';

        // Check for optimistic lock conflict if we have a cached version.
        final cachedVersion = _versions[vKey];
        if (cachedVersion != null) {
          // Verify the row hasn't been modified since we last fetched it.
          final currentRow = db.select(
            'SELECT z_opt FROM ${descriptor.tableName} WHERE id = ?',
            [id],
          );
          if (currentRow.isNotEmpty) {
            final currentVersion = currentRow.first['z_opt'] as int;
            if (currentVersion != cachedVersion) {
              throw OptimisticLockError(
                modelType: descriptor.modelClassName,
                id: id,
                expectedVersion: cachedVersion,
                actualVersion: currentVersion,
              );
            }
          }
        }

        // Build values in descriptor column order for the cached template.
        final values = descriptor.columns
            .map((col) => map[col.columnName])
            .toList();
        db.execute(templates.insert, values);

        // After ON CONFLICT upsert, z_opt may have been incremented.
        // Read current z_opt from the database.
        final vRow = db.select(
          'SELECT z_opt FROM ${descriptor.tableName} WHERE id = ?',
          [id],
        );
        if (vRow.isNotEmpty) {
          _versions[vKey] = vRow.first['z_opt'] as int;
        }

      case _OperationType.update:
        await _persistExternalFiles(op.model, descriptor, map);

        final id = map['id'];
        final values = [
          ...descriptor.columns
              .where((c) => c.columnName != 'id')
              .map((c) => map[c.columnName]),
          id,
        ];
        db.execute(templates.update, values);

      case _OperationType.delete:
        final id = map['id'];
        // Handle ExternalFile deletions.
        await _deleteExternalFiles(op.model, descriptor);
        db.execute(templates.delete, [id]);
    }
  }

  // -------------------------------------------------------------------------
  // Read operations
  // -------------------------------------------------------------------------

  /// Fetch all objects matching [query].
  Future<List<T>> fetch<T>(Query<T> query) async {
    final descriptor = _descriptorForType<T>();
    final sql = _buildSelectSql(descriptor, query);

    final rows = container.db.select(
      sql,
      query.where?.arguments ?? [],
    );

    return rows.map((row) {
      final resolved = _resolveExternalFilePaths(row, descriptor);
      final obj = descriptor.fromMap(resolved) as T;
      final id = row['id'] as String;
      final zOpt = row['z_opt'] as int;
      _versions['${descriptor.tableName}:$id'] = zOpt;
      return obj;
    }).toList();
  }

  /// Fetch the first object matching [query], or `null` if none exists.
  Future<T?> fetchFirst<T>(Query<T> query) async {
    final results = await fetch(Query<T>(
      where: query.where,
      orderBy: query.orderBy,
      limit: 1,
      offset: query.offset,
    ));
    return results.isEmpty ? null : results.first;
  }

  /// Fetch a single object by its primary key.
  Future<T?> fetchOne<T>({required String id}) async {
    final descriptor = _descriptorForType<T>();
    final rows = container.db.select(
      'SELECT * FROM ${descriptor.tableName} WHERE id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final zOpt = row['z_opt'] as int;
    _versions['${descriptor.tableName}:$id'] = zOpt;
    final resolved = _resolveExternalFilePaths(row, descriptor);
    return descriptor.fromMap(resolved) as T;
  }

  /// Fetch related objects through a declared relationship.
  ///
  /// [model] is the parent object, [relationshipField] is the field name
  /// declared on the parent's descriptor (e.g., 'bucketList' on Trip).
  ///
  /// Returns the child objects whose FK references [model].
  Future<List<T>> fetchRelated<T>(Object model, String relationshipField) async {
    final parentDescriptor = _descriptorFor(model);
    final parentMap = parentDescriptor.toMap(model);
    final parentId = parentMap['id'] as String;

    // Find the relationship on the parent descriptor.
    final parentRel = parentDescriptor.relationships.firstWhere(
      (r) => r.fieldName == relationshipField,
      orElse: () => throw StateError(
        'No relationship "$relationshipField" on ${parentDescriptor.modelClassName}',
      ),
    );

    // Find the child descriptor for the related table.
    final childDescriptor = container.schema.descriptors.firstWhere(
      (d) => d.tableName == parentRel.relatedTable,
      orElse: () => throw StateError(
        'No descriptor for table "${parentRel.relatedTable}"',
      ),
    );

    // Use explicit fkColumnName, or fall back to convention.
    final fkColumn = parentRel.fkColumnName ??
        '${parentRel.inverseFieldName ?? parentDescriptor.tableName}_id';

    final rows = container.db.select(
      'SELECT * FROM ${childDescriptor.tableName} WHERE $fkColumn = ?',
      [parentId],
    );

    return rows.map((row) {
      final resolved = _resolveExternalFilePaths(row, childDescriptor);
      return childDescriptor.fromMap(resolved) as T;
    }).toList();
  }

  /// Count objects matching [query] without fetching them.
  Future<int> fetchCount<T>(Query<T> query) async {
    final descriptor = _descriptorForType<T>();
    final where = query.where != null ? 'WHERE ${query.where!.sql}' : '';
    final row = container.db.select(
      'SELECT COUNT(*) as c FROM ${descriptor.tableName} $where',
      query.where?.arguments ?? [],
    );
    return row.first['c'] as int;
  }

  // -------------------------------------------------------------------------
  // Transactions
  // -------------------------------------------------------------------------

  /// Execute [action] inside a single database transaction.
  ///
  /// Only operations staged during [action] are committed. If [action]
  /// throws, all changes (including any cascade operations appended by
  /// delete-rule enforcement) are rolled back at both the SQLite and
  /// in-memory levels.
  ///
  /// Throws [StateError] if there are already pending operations — call
  /// [save] or [rollback] first. This prevents ambiguity about whether
  /// pre-existing ops should be included in the transaction.
  Future<T> transaction<T>(Future<T> Function() action) async {
    if (_pending.isNotEmpty) {
      throw StateError(
        'Cannot start a transaction with ${_pending.length} pending '
        'operation(s). Call save() or rollback() first.',
      );
    }
    try {
      final result = await action();
      await save();
      return result;
    } catch (e) {
      _pending.clear();
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Change observation
  // -------------------------------------------------------------------------

  /// Returns the z_opt version for the object of type [T] with the given [id].
  ///
  /// Returns `null` if the version is not tracked (object was never fetched or
  /// saved through this context).
  int? versionOf<T>(String id) {
    final descriptor = _descriptorForType<T>();
    return _versions['${descriptor.tableName}:$id'];
  }

  /// Listen to changes made by [save] on this context.
  ///
  /// The stream emits after every successful save that affects at least one
  /// row. Used by [QueryObserver] to know when to re-run queries.
  Stream<ContextChangeSet> get changes => _controller.stream;

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Resolve FK UUID strings to z_pk integers for all relationship columns.
  ///
  /// Calls `getRelationshipIds()` on the descriptor to get FK column → UUID
  /// pairs, then looks up each UUID's z_pk via SQL and injects the integer
  /// into [map]. Throws [StateError] if a related object hasn't been saved.
  void _resolveRelationshipFks(
    Object model,
    ModelDescriptor descriptor,
    Map<String, Object?> map,
  ) {
    final relIds = descriptor.getRelationshipIds(model);
    if (relIds.isEmpty) return;

    for (final entry in relIds.entries) {
      final fkColumn = entry.key;
      final relatedUuid = entry.value;

      if (relatedUuid == null) {
        map[fkColumn] = null;
        continue;
      }

      // Find the related table from the relationship definitions.
      final rel = descriptor.relationships.firstWhere(
        (r) => r.fkColumnName == fkColumn,
        orElse: () => throw StateError(
          'No relationship with fkColumnName "$fkColumn" '
          'on ${descriptor.modelClassName}',
        ),
      );

      final zpk = _resolveZpk(rel.relatedTable, relatedUuid);
      map[fkColumn] = zpk;
    }
  }

  /// Look up the z_pk integer for a row by its UUID id.
  ///
  /// Throws [StateError] if the row doesn't exist (unsaved parent).
  int _resolveZpk(String tableName, String uuid) {
    final rows = container.db.select(
      'SELECT z_pk FROM $tableName WHERE id = ?',
      [uuid],
    );
    if (rows.isEmpty) {
      throw StateError(
        'Cannot resolve FK: no row in "$tableName" with id "$uuid". '
        'Save the parent object before its children.',
      );
    }
    return rows.first['z_pk'] as int;
  }

  String _buildSelectSql<T>(ModelDescriptor descriptor, Query<T> query) {
    final parts = ['SELECT * FROM ${descriptor.tableName}'];
    if (query.where != null) parts.add('WHERE ${query.where!.sql}');
    if (query.orderBy.isNotEmpty) {
      parts.add('ORDER BY ${query.orderBy.map((s) => s.toSql()).join(', ')}');
    }
    if (query.limit != null) parts.add('LIMIT ${query.limit}');
    if (query.offset > 0) parts.add('OFFSET ${query.offset}');
    return parts.join(' ');
  }

  Future<void> _persistExternalFiles(
    Object model,
    ModelDescriptor descriptor,
    Map<String, Object?> map,
  ) async {
    final id = map['id'] as String;
    for (final fieldName in descriptor.externalFileFields) {
      final file = descriptor.getExternalFile(model, fieldName);
      if (file == null || !file.isStaged) continue;
      final destination = _blobFile(id, fieldName);
      await file.persistTo(destination);
      // Update the map with the blob UUID reference.
      map[fieldName] = destination.uri.pathSegments.last;
    }
  }

  Future<void> _deleteExternalFiles(
      Object model, ModelDescriptor descriptor) async {
    for (final fieldName in descriptor.externalFileFields) {
      final file = descriptor.getExternalFile(model, fieldName);
      if (file == null) continue;
      file.delete();
      await file.removeFromDisk();
    }
  }

  /// Resolve ExternalFile UUID columns in [row] to full blob directory paths
  /// before passing to `fromMap`. The database stores just the UUID filename;
  /// `fromManagedPath` needs the full filesystem path.
  Map<String, Object?> _resolveExternalFilePaths(
    Map<String, Object?> row,
    ModelDescriptor descriptor,
  ) {
    if (descriptor.externalFileFields.isEmpty) return row;
    final resolved = Map<String, Object?>.of(row);
    for (final fieldName in descriptor.externalFileFields) {
      final uuid = resolved[fieldName];
      if (uuid is String) {
        resolved[fieldName] =
            '${container.blobDirectory.path}/$uuid';
      }
    }
    return resolved;
  }

  static final _safePathSegment = RegExp(r'^[a-zA-Z0-9_\-]+$');

  File _blobFile(String modelId, String fieldName) {
    // Validate to prevent path traversal via malicious model IDs.
    if (!_safePathSegment.hasMatch(modelId)) {
      throw ArgumentError(
        'Invalid model id "$modelId". Must be alphanumeric/hyphens/underscores.',
      );
    }
    if (!_safePathSegment.hasMatch(fieldName)) {
      throw ArgumentError(
        'Invalid field name "$fieldName". Must be alphanumeric/hyphens/underscores.',
      );
    }
    final uuid = '$modelId-$fieldName';
    return File(
        '${container.blobDirectory.path}/$uuid');
  }

  /// Enforce delete rules for all pending delete operations.
  ///
  /// Uses the pre-computed [_reverseRelationships] index for O(1) lookup
  /// per parent table instead of scanning all descriptors.
  List<_DeferredSql> _enforceDeleteRules() {
    final deferredSql = <_DeferredSql>[];

    // Snapshot current deletes — cascade may append new ones, which we
    // then process in subsequent iterations until no new deletes appear.
    var i = 0;
    while (i < _pending.length) {
      final op = _pending[i];
      i++;
      if (op.type != _OperationType.delete) continue;

      final parentDescriptor = _descriptorFor(op.model);
      final parentMap = parentDescriptor.toMap(op.model);
      final parentId = parentMap['id'] as String;

      final children = _reverseRelationships[parentDescriptor.tableName];
      if (children == null) continue;

      for (final child in children) {
        final fkColumn = child.fkColumnName;

        switch (child.deleteRule) {
          case DeleteRule.cascade:
            _cascadeDelete(child.descriptor, fkColumn, parentId);
          case DeleteRule.nullify:
            deferredSql.add(_DeferredSql(
              'UPDATE ${child.descriptor.tableName} SET $fkColumn = NULL WHERE $fkColumn = ?',
              [parentId],
            ));
          case DeleteRule.deny:
            _denyDelete(child.descriptor, fkColumn, parentId);
          case DeleteRule.noAction:
            break;
        }
      }
    }

    return deferredSql;
  }

  /// CASCADE: query child IDs by FK, reconstruct models, add them as
  /// pending deletes (which will recursively trigger their own rules).
  void _cascadeDelete(
    ModelDescriptor childDescriptor,
    String fkColumn,
    String parentId,
  ) {
    final rows = container.db.select(
      'SELECT * FROM ${childDescriptor.tableName} WHERE $fkColumn = ?',
      [parentId],
    );

    for (final row in rows) {
      final resolved = _resolveExternalFilePaths(row, childDescriptor);
      final childModel = childDescriptor.fromMap(resolved);
      _pending.add(_PendingOperation(_OperationType.delete, childModel));
    }
  }

  /// DENY: throw [StateError] if any child rows reference the parent.
  void _denyDelete(
    ModelDescriptor childDescriptor,
    String fkColumn,
    String parentId,
  ) {
    final row = container.db.select(
      'SELECT COUNT(*) as c FROM ${childDescriptor.tableName} WHERE $fkColumn = ?',
      [parentId],
    );
    final count = row.first['c'] as int;
    if (count > 0) {
      throw StateError(
        'Cannot delete: $count related row(s) exist in '
        '${childDescriptor.tableName} (delete rule: deny)',
      );
    }
  }

  /// Build reverse relationship index from schema.
  Map<String, List<_ChildRelationship>> _buildReverseIndex() {
    final index = <String, List<_ChildRelationship>>{};
    for (final childDescriptor in container.schema.descriptors) {
      for (final rel in childDescriptor.relationships) {
        // Only index child-side relationships — those that own the FK column.
        if (!rel.isForeignKeySide) continue;

        final fkColumn = rel.fkColumnName ?? '${rel.fieldName}_id';

        index.putIfAbsent(rel.relatedTable, () => []).add(
          _ChildRelationship(childDescriptor, rel.deleteRule, fkColumn),
        );
      }
    }
    return index;
  }

  ModelDescriptor _descriptorFor(Object model) {
    final descriptor = _descriptorsByType[model.runtimeType];
    if (descriptor != null) return descriptor;
    throw StateError(
      'No descriptor registered for ${model.runtimeType}. '
      'Did you add it to your Schema?',
    );
  }

  ModelDescriptor _descriptorForType<T>() {
    final descriptor = _descriptorsByType[T];
    if (descriptor != null) return descriptor;
    throw StateError(
      'No descriptor registered for $T. '
      'Did you add it to your Schema?',
    );
  }

  void _notifyChanges(List<_PendingOperation> ops) {
    if (ops.isEmpty) return;
    // TODO: build a real ContextChangeSet from ops
    _controller.add(const ContextChangeSet());
  }
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

enum _OperationType { insert, update, delete }

class _DeferredSql {
  final String statement;
  final List<Object?> arguments;
  _DeferredSql(this.statement, this.arguments);
}

class _PendingOperation {
  final _OperationType type;
  final Object model;
  _PendingOperation(this.type, this.model);
}

/// Pre-computed child relationship entry for the reverse index.
class _ChildRelationship {
  final ModelDescriptor descriptor;
  final DeleteRule deleteRule;
  final String fkColumnName;
  _ChildRelationship(this.descriptor, this.deleteRule, this.fkColumnName);
}

/// Cached SQL templates for a single table, built once from the descriptor.
class _SqlTemplates {
  final String insert;
  final String update;
  final String delete;

  _SqlTemplates._({required this.insert, required this.update, required this.delete});

  factory _SqlTemplates.from(ModelDescriptor d) {
    final cols = d.columns.map((c) => c.columnName).join(', ');
    final placeholders = List.filled(d.columns.length, '?').join(', ');
    final setClauses = d.columns
        .where((c) => c.columnName != 'id')
        .map((c) => '${c.columnName} = ?')
        .join(', ');

    // Upsert on id conflict: preserves z_pk and increments z_opt.
    final upsertSet = d.columns
        .where((c) => c.columnName != 'id')
        .map((c) => '${c.columnName} = excluded.${c.columnName}')
        .join(', ');

    return _SqlTemplates._(
      insert: 'INSERT INTO ${d.tableName} ($cols) VALUES ($placeholders) '
              'ON CONFLICT(id) DO UPDATE SET $upsertSet, z_opt = z_opt + 1',
      update: 'UPDATE ${d.tableName} SET $setClauses, z_opt = z_opt + 1 WHERE id = ?',
      delete: 'DELETE FROM ${d.tableName} WHERE id = ?',
    );
  }
}

/// Thrown when a save fails because the row was modified by another context
/// since it was fetched.
class OptimisticLockError extends Error {
  final String modelType;
  final String id;
  final int expectedVersion;
  final int actualVersion;

  OptimisticLockError({
    required this.modelType,
    required this.id,
    required this.expectedVersion,
    required this.actualVersion,
  });

  @override
  String toString() =>
      'OptimisticLockError: $modelType(id=$id) expected z_opt=$expectedVersion '
      'but found $actualVersion — the row was modified by another context.';
}

/// The set of changes reported after a successful [ModelContext.save].
class ContextChangeSet {
  final List<String> insertedTables;
  final List<String> updatedTables;
  final List<String> deletedTables;

  const ContextChangeSet({
    this.insertedTables = const [],
    this.updatedTables = const [],
    this.deletedTables = const [],
  });

  bool get isEmpty =>
      insertedTables.isEmpty &&
      updatedTables.isEmpty &&
      deletedTables.isEmpty;

  /// Returns true if any of [tableNames] appear in this change set.
  bool affects(List<String> tableNames) {
    final all = {...insertedTables, ...updatedTables, ...deletedTables};
    return tableNames.any(all.contains);
  }
}
