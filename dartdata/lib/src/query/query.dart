import 'predicate.dart';
import 'sort_descriptor.dart';

export 'predicate.dart';
export 'sort_descriptor.dart';

/// Describes a fetch operation for model type [T].
///
/// Build a query using the generated `$ClassName` descriptor fields:
/// ```dart
/// final query = Query<Trip>(
///   where: $Trip.destination.equals('Paris') & $Trip.startDate > DateTime.now(),
///   orderBy: [$Trip.startDate.ascending()],
///   limit: 20,
/// );
/// final trips = await context.fetch(query);
/// ```
class Query<T> {
  /// Filter predicate. `null` means fetch all rows.
  final Predicate<T>? where;

  /// Ordering. Applied in list order (first element = primary sort).
  final List<SortDescriptor<T>> orderBy;

  /// Maximum number of results. `null` means no limit.
  final int? limit;

  /// Number of leading results to skip. Useful for pagination.
  final int offset;

  /// If true, [ExternalFile] fields are read from disk eagerly for every
  /// result. Defaults to false (lazy — bytes loaded on first [ExternalFile.file] access).
  final bool eagerLoadExternalStorage;

  const Query({
    this.where,
    this.orderBy = const [],
    this.limit,
    this.offset = 0,
    this.eagerLoadExternalStorage = false,
  });
}
