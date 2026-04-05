import '../annotations/relationship.dart';

/// Holds the set of model types that a [ModelContainer] should persist.
///
/// Pass the generated `$ClassName.descriptor` for each model:
/// ```dart
/// Schema([Trip.descriptor, BucketListItem.descriptor])
/// ```
class Schema {
  final List<ModelDescriptor> descriptors;

  static final _validIdentifier = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

  Schema(this.descriptors) {
    _validateIdentifiers();
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

  /// Reconstruct a model instance from a SQLite row map.
  Object fromMap(Map<String, Object?> row);
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

  const RelationshipDefinition({
    required this.fieldName,
    required this.relatedTable,
    required this.cardinality,
    this.inverseFieldName,
    required this.deleteRule,
    this.fkColumnName,
  });
}

enum RelationshipCardinality { toOne, toMany }

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
