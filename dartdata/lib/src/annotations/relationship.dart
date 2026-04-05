/// What happens to related objects when the owning object is deleted.
enum DeleteRule {
  /// Set the foreign key to NULL on related objects.
  nullify,

  /// Delete all related objects along with the owner.
  cascade,

  /// Prevent deletion if related objects exist. Throws [StateError].
  deny,

  /// Do nothing — related objects become orphans.
  noAction,
}

/// Declares a relationship between two `@model` types.
///
/// The generator infers cardinality from the Dart field type:
///   - `RelatedModel?`      → optional one-to-one
///   - `RelatedModel`       → required one-to-one
///   - `List<RelatedModel>` → one-to-many
///
/// For many-to-many, declare `List<B>` on both sides and set [inverse] on
/// one side. The generator creates a hidden junction table automatically.
///
/// Example:
/// ```dart
/// @model
/// class Trip {
///   @relationship(deleteRule: DeleteRule.cascade)
///   List<BucketListItem> bucketList;
///
///   @relationship()
///   LivingAccommodation? accommodation;
/// }
/// ```
class relationship {
  /// What to do with related objects when this object is deleted.
  final DeleteRule deleteRule;

  /// The field name on the related model that forms the inverse of this
  /// relationship. Required for many-to-many; optional for one-to-many.
  final String? inverse;

  /// Minimum number of related objects (validation only, not a DB constraint).
  final int minimumModelCount;

  /// Maximum number of related objects. `null` means unlimited.
  final int? maximumModelCount;

  const relationship({
    this.deleteRule = DeleteRule.nullify,
    this.inverse,
    this.minimumModelCount = 0,
    this.maximumModelCount,
  });
}
