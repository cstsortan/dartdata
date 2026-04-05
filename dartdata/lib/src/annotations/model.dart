/// Marks a class as a persistent data model.
///
/// The dartdata_generator will read this annotation and produce a `.g.dart`
/// file containing:
///   - A `$ClassName` query descriptor with typed [QueryField]s.
///   - `toMap()` / `fromMap()` serialisation helpers.
///   - A `_tableName` and `_externalFileFields` registry used by [ModelContext].
///
/// Example:
/// ```dart
/// @model
/// class Trip {
///   @attribute(primaryKey: true)
///   final String id;
///   String name;
///   DateTime startDate;
/// }
/// ```
const model = _Model();

class _Model {
  const _Model();
}

/// Fine-tunes how a single field is persisted.
///
/// Apply to any field inside a `@model` class.
class attribute {
  /// Whether this field is the primary key. At most one field per model.
  final bool primaryKey;

  /// Adds a UNIQUE constraint to the column.
  final bool unique;

  /// Adds a database index for faster queries.
  final bool indexed;

  /// Overrides the SQLite column name. Defaults to the field name in
  /// snake_case.
  final String? columnName;

  /// If true, the field is never written to or read from SQLite.
  /// Useful for computed or cached values.
  final bool transient;

  const attribute({
    this.primaryKey = false,
    this.unique = false,
    this.indexed = false,
    this.columnName,
    this.transient = false,
  });
}
