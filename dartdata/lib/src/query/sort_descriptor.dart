/// Describes how to sort results for a [Query].
///
/// Created via [QueryField.ascending] / [QueryField.descending] on the
/// generated `$ClassName` descriptor fields.
class SortDescriptor<T> {
  final String columnName;
  final bool ascending;

  const SortDescriptor(this.columnName, {required this.ascending});

  String toSql() => '$columnName ${ascending ? 'ASC' : 'DESC'}';
}
