import 'package:dartdata/dartdata.dart';
import 'package:uuid/uuid.dart';

import 'post.dart';

part 'tag.g.dart';

/// A tag with many-to-many relationship to Post via auto junction table.
/// Uses DeleteRule.deny — cannot delete a Tag while Posts reference it.
@model
class Tag {
  @attribute(primaryKey: true)
  final String id;

  @attribute(unique: true)
  String name;

  @relationship(deleteRule: DeleteRule.deny, inverse: 'tags')
  List<Post> posts;

  Tag({
    String? id,
    required this.name,
    this.posts = const [],
  }) : id = id ?? const Uuid().v4();
}
