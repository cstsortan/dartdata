import 'package:dartdata/dartdata.dart';
import 'package:uuid/uuid.dart';

part 'tag.g.dart';

/// A tag linked to Posts via the explicit [PostTag] junction model.
/// The many-to-many relationship goes through PostTag (which carries extra
/// fields like pinnedAt), so no auto junction table is generated here.
@model
class Tag {
  @attribute(primaryKey: true)
  final String id;

  @attribute(unique: true)
  String name;

  Tag({
    String? id,
    required this.name,
  }) : id = id ?? const Uuid().v4();
}
