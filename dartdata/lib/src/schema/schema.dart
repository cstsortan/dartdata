import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../annotations/relationship.dart';
import '../storage/external_file.dart';

/// Holds the set of model types that a [ModelContainer] should persist.
///
/// Pass the generated `$ClassName.descriptor` for each model:
/// ```dart
/// Schema([Trip.descriptor, BucketListItem.descriptor])
/// ```
class Schema {
  final List<ModelDescriptor> descriptors;

  static final _validIdentifier = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

  String? _cachedFingerprint;

  Schema(this.descriptors) {
    _validateIdentifiers();
  }

  /// Returns a deterministic SHA-256 hash of the schema definition.
  ///
  /// The fingerprint is computed by sorting all column tuples
  /// `(tableName, columnName, type, isPK, isUnique, isNullable)` and hashing
  /// the resulting canonical string. Two schemas with the same tables and
  /// columns will always produce the same fingerprint.
  String get fingerprint {
    if (_cachedFingerprint != null) return _cachedFingerprint!;

    final tuples = <String>[];
    for (final d in descriptors) {
      for (final col in d.columns) {
        tuples.add(
          '${d.tableName}|${col.columnName}|${col.type.name}'
          '|${col.isPrimaryKey}|${col.isUnique}|${col.isNullable}',
        );
      }
    }
    tuples.sort();

    final canonical = tuples.join('\n');
    _cachedFingerprint =
        sha256.convert(utf8.encode(canonical)).toString();
    return _cachedFingerprint!;
  }

  void _validateIdentifiers() {
    for (final d in descriptors) {
      _checkId(d.tableName, 'tableName on ${d.modelClassName}');
      for (final col in d.columns) {
        _checkId(col.columnName, 'columnName "${col.columnName}" on ${d.tableName}');
      }
      for (final rel in d.relationships) {
        _checkId(rel.fieldName, 'relationship fieldName "${rel.fieldName}" on ${d.tableName}');
        _checkId(rel.relatedTable, 'relatedTable "${rel.relatedTable}" on ${d.tableName}');
        if (rel.fkColumnName != null) {
          _checkId(rel.fkColumnName!, 'fkColumnName "${rel.fkColumnName}" on ${d.tableName}');
        }
      }
    }
  }

  static void _checkId(String value, String context) {
    if (!_validIdentifier.hasMatch(value)) {
      throw ArgumentError(
        'Invalid SQL identifier "$value" in $context. '
        'Must match [a-zA-Z_][a-zA-Z0-9_]*.',
      );
    }
  }
}

/// Runtime descriptor for a single `@model` class.
///
/// Produced by the code generator in the `.g.dart` file. Contains the
/// table name, column definitions, and relationship metadata needed by
/// [ModelContext] to create the schema and perform CRUD operations.
abstract class ModelDescriptor {
  String get tableName;
  List<ColumnDefinition> get columns;
  List<RelationshipDefinition> get relationships;
  List<String> get externalFileFields;
  String get modelClassName;

  /// The Dart [Type] of the model class this descriptor represents.
  /// Used for O(1) descriptor lookup instead of string-based matching.
  Type get modelType;

  /// Junction tables for simple many-to-many relationships.
  /// Only the side that declares `inverse` emits the junction table.
  List<JunctionTableDefinition> get junctionTables => const [];

  /// Reconstruct a model instance from a SQLite row map.
  Object fromMap(Map<String, Object?> row);

  /// Convert a model instance to a SQLite column map.
  Map<String, Object?> toMap(Object model);

  /// Access an [ExternalFile] field on [model] by [fieldName].
  ///
  /// Returns `null` if the field is null or the model has no ExternalFile
  /// fields. Override in descriptors that declare [externalFileFields].
  ExternalFile? getExternalFile(Object model, String fieldName) => null;
}

/// Describes a single SQLite column derived from a `@model` field.
class ColumnDefinition {
  final String columnName;
  final ColumnType type;
  final bool isPrimaryKey;
  final bool isUnique;
  final bool isIndexed;
  final bool isNullable;

  const ColumnDefinition({
    required this.columnName,
    required this.type,
    this.isPrimaryKey = false,
    this.isUnique = false,
    this.isIndexed = false,
    this.isNullable = true,
  });
}

enum ColumnType { text, integer, real, blob }

/// Describes a relationship declared with `@relationship`.
class RelationshipDefinition {
  final String fieldName;
  final String relatedTable;
  final RelationshipCardinality cardinality;
  final String? inverseFieldName;
  final DeleteRule deleteRule;

  /// The FK column name on the child table (e.g., 'trip_id').
  /// Explicit rather than derived via convention.
  final String? fkColumnName;

  /// Whether this side of the relationship owns the foreign key column.
  /// `true` for the child side (e.g., BucketListItem → Trip), `false` for the
  /// parent/inverse side. Used by [ModelContext] to determine relationship
  /// direction without probing column existence by name convention.
  final bool isForeignKeySide;

  const RelationshipDefinition({
    required this.fieldName,
    required this.relatedTable,
    required this.cardinality,
    this.inverseFieldName,
    required this.deleteRule,
    this.fkColumnName,
    this.isForeignKeySide = false,
  });
}

enum RelationshipCardinality { toOne, toMany }

/// Describes a hidden junction table for a simple many-to-many relationship.
class JunctionTableDefinition {
  /// The junction table name, e.g. `_actor_movie` (alphabetical, underscore prefix).
  final String tableName;

  /// FK column referencing the first table (alphabetical).
  final String firstFkColumn;

  /// The table the first FK references.
  final String firstTable;

  /// FK column referencing the second table (alphabetical).
  final String secondFkColumn;

  /// The table the second FK references.
  final String secondTable;

  const JunctionTableDefinition({
    required this.tableName,
    required this.firstFkColumn,
    required this.firstTable,
    required this.secondFkColumn,
    required this.secondTable,
  });
}

/// Controls how the [ModelContainer] handles schema differences between
/// the current model definitions and what is on disk.
enum MigrationPolicy {
  /// Add new tables and columns automatically. Never drops existing columns.
  /// Safe to use in production.
  automatic,

  /// Throw [SchemaMismatchError] if the on-disk schema differs from the
  /// current model. Use during development to catch accidental drift.
  none,

  /// Drop and recreate all tables. All existing data is lost.
  /// Useful during early development.
  resetOnConflict,
}

/// Thrown when [MigrationPolicy.none] is active and the schema has changed.
class SchemaMismatchError extends Error {
  final String message;
  SchemaMismatchError(this.message);

  @override
  String toString() => 'SchemaMismatchError: $message';
}
