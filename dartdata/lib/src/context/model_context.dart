import 'dart:async';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

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
  final _ChangeNotifier _notifier = _ChangeNotifier();

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
      rethrow;
    }

    final affected = List<_PendingOperation>.from(_pending);
    _pending.clear();

    // Notify observers of the change set.
    _notifier.notify(affected);
  }

  /// Execute a single pending operation against the database.
  Future<void> _execute(_PendingOperation op, Database db) async {
    final descriptor = _descriptorFor(op.model);
    final map = (op.model as dynamic).toMap() as Map<String, Object?>;

    switch (op.type) {
      case _OperationType.insert:
        // Persist any staged ExternalFile fields first.
        await _persistExternalFiles(op.model, descriptor, map);

        final cols = map.keys.join(', ');
        final placeholders = map.keys.map((_) => '?').join(', ');
        db.execute(
          'INSERT OR REPLACE INTO ${descriptor.tableName} ($cols) VALUES ($placeholders)',
          map.values.toList(),
        );

      case _OperationType.update:
        await _persistExternalFiles(op.model, descriptor, map);

        final id = map['id'];
        final setClauses =
            map.keys.where((k) => k != 'id').map((k) => '$k = ?').join(', ');
        final values = [
          ...map.entries.where((e) => e.key != 'id').map((e) => e.value),
          id,
        ];
        db.execute(
          'UPDATE ${descriptor.tableName} SET $setClauses, z_opt = z_opt + 1 WHERE id = ?',
          values,
        );

      case _OperationType.delete:
        final id = map['id'];
        // Handle ExternalFile deletions.
        await _deleteExternalFiles(op.model, descriptor);
        db.execute(
          'DELETE FROM ${descriptor.tableName} WHERE id = ?',
          [id],
        );
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

    return rows
        .map((row) => (descriptor as dynamic).fromMap(row) as T)
        .toList();
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
    return (descriptor as dynamic).fromMap(rows.first) as T;
  }

  /// Fetch related objects through a declared relationship.
  ///
  /// [model] is the parent object, [relationshipField] is the field name
  /// declared on the parent's descriptor (e.g., 'bucketList' on Trip).
  ///
  /// Returns the child objects whose FK references [model].
  Future<List<T>> fetchRelated<T>(Object model, String relationshipField) async {
    final parentDescriptor = _descriptorFor(model);
    final parentMap = (model as dynamic).toMap() as Map<String, Object?>;
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

    // The FK column on the child table is named after the inverse field + '_id'.
    final inverseField = parentRel.inverseFieldName ?? parentDescriptor.tableName;
    final fkColumn = '${inverseField}_id';

    final rows = container.db.select(
      'SELECT * FROM ${childDescriptor.tableName} WHERE $fkColumn = ?',
      [parentId],
    );

    return rows
        .map((row) => (childDescriptor as dynamic).fromMap(row) as T)
        .toList();
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
  /// If [action] throws, all staged changes are rolled back.
  Future<T> transaction<T>(Future<T> Function() action) async {
    final snapshot = List<_PendingOperation>.from(_pending);
    _pending.clear();
    try {
      final result = await action();
      await save();
      return result;
    } catch (e) {
      _pending
        ..clear()
        ..addAll(snapshot);
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // Change observation
  // -------------------------------------------------------------------------

  /// Listen to changes made by [save] on this context.
  ///
  /// The stream emits after every successful save that affects at least one
  /// row. Used by [QueryObserver] to know when to re-run queries.
  Stream<ContextChangeSet> get changes => _notifier.stream;

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

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
      final file = (model as dynamic).getExternalFile(fieldName) as ExternalFile?;
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
      final file =
          (model as dynamic).getExternalFile(fieldName) as ExternalFile?;
      if (file == null) continue;
      file.delete();
      await file.removeFromDisk();
    }
  }

  File _blobFile(String modelId, String fieldName) {
    // Flat UUID-keyed directory, mirroring SwiftData's _EXTERNAL_DATA layout.
    // We use modelId + fieldName as a deterministic UUID-like key.
    final uuid = '$modelId-$fieldName';
    return File(
        '${container.blobDirectory.path}/$uuid');
  }

  /// Enforce delete rules for all pending delete operations.
  ///
  /// Iterates pending deletes, looks up child descriptors that reference
  /// the parent's table via [RelationshipDefinition], and dispatches to
  /// rule-specific handlers. Returns SQL statements (e.g., nullify UPDATEs)
  /// to be executed inside the transaction.
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
      final parentMap = (op.model as dynamic).toMap() as Map<String, Object?>;
      final parentId = parentMap['id'] as String;

      for (final childDescriptor in container.schema.descriptors) {
        for (final rel in childDescriptor.relationships) {
          if (rel.relatedTable != parentDescriptor.tableName) continue;

          final fkColumn = '${rel.fieldName}_id';

          // Only process child-side relationships (where the FK column
          // exists on this descriptor's table). Skip parent-side entries.
          if (!childDescriptor.columns.any((c) => c.columnName == fkColumn)) {
            continue;
          }

          switch (rel.deleteRule) {
            case 'cascade':
              _cascadeDelete(childDescriptor, fkColumn, parentId);
            case 'nullify':
              deferredSql.add(_DeferredSql(
                'UPDATE ${childDescriptor.tableName} SET $fkColumn = NULL WHERE $fkColumn = ?',
                [parentId],
              ));
            case 'deny':
              _denyDelete(childDescriptor, fkColumn, parentId);
            case 'noAction':
              break;
          }
        }
      }
    }

    return deferredSql;
  }

  /// CASCADE: query child rows by FK, reconstruct models, add them as
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
      final childModel = (childDescriptor as dynamic).fromMap(row);
      _pending.add(_PendingOperation(_OperationType.delete, childModel as Object));
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

  ModelDescriptor _descriptorFor(Object model) {
    final typeName = model.runtimeType.toString();
    return container.schema.descriptors.firstWhere(
      (d) => d.modelClassName == typeName,
      orElse: () => throw StateError(
        'No descriptor registered for $typeName. '
        'Did you add it to your Schema?',
      ),
    );
  }

  ModelDescriptor _descriptorForType<T>() {
    return container.schema.descriptors.firstWhere(
      (d) => d.modelClassName == T.toString(),
      orElse: () => throw StateError(
        'No descriptor registered for $T. '
        'Did you add it to your Schema?',
      ),
    );
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

class _ChangeNotifier {
  final _controller = _StreamController<ContextChangeSet>();

  Stream<ContextChangeSet> get stream => _controller.stream;

  void notify(List<_PendingOperation> ops) {
    if (ops.isEmpty) return;
    // TODO: build a real ContextChangeSet from ops
    _controller.add(const ContextChangeSet());
  }
}

// Minimal stream controller without dart:async import conflict.
class _StreamController<T> {
  final List<void Function(T)> _listeners = [];

  Stream<T> get stream => _Stream<T>(this);

  void add(T value) {
    for (final listener in _listeners) {
      listener(value);
    }
  }
}

class _Stream<T> extends Stream<T> {
  final _StreamController<T> _controller;
  _Stream(this._controller);

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    _controller._listeners.add(onData ?? (_) {});
    return _StreamSubscription<T>(
        _controller, onData ?? (_) {});
  }
}

class _StreamSubscription<T> implements StreamSubscription<T> {
  final _StreamController<T> _controller;
  final void Function(T) _listener;
  _StreamSubscription(this._controller, this._listener);

  @override
  Future<void> cancel() async {
    _controller._listeners.remove(_listener);
  }

  @override
  void onData(void Function(T data)? handleData) {}
  @override
  void onError(Function? handleError) {}
  @override
  void onDone(void Function()? handleDone) {}
  @override
  void pause([Future<void>? resumeSignal]) {}
  @override
  void resume() {}
  @override
  bool get isPaused => false;
  @override
  Future<E> asFuture<E>([E? futureValue]) => Future.value(futureValue as E);
}
