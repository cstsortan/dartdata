/// Holds the set of model types that a [ModelContainer] should persist.
///
/// Pass the generated `$ClassName.descriptor` for each model:
/// ```dart
/// Schema([Trip.descriptor, BucketListItem.descriptor])
/// ```
class Schema {
  final List<ModelDescriptor> descriptors;

  const Schema(this.descriptors);
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
  final String deleteRule;

  const RelationshipDefinition({
    required this.fieldName,
    required this.relatedTable,
    required this.cardinality,
    this.inverseFieldName,
    required this.deleteRule,
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
