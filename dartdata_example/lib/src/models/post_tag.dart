import 'package:dartdata/dartdata.dart';
import 'package:uuid/uuid.dart';

import 'post.dart';
import 'tag.dart';

part 'post_tag.g.dart';

/// Explicit junction model for many-to-many between Post and Tag,
/// carrying an extra field (pinnedAt). No auto junction table is generated
/// when using an explicit junction model.
@model
class PostTag {
  @attribute(primaryKey: true)
  final String id;

  DateTime? pinnedAt;

  @relationship(deleteRule: DeleteRule.cascade)
  Post? post;

  @relationship(deleteRule: DeleteRule.cascade)
  Tag? tag;

  PostTag({
    String? id,
    this.pinnedAt,
    this.post,
    this.tag,
  }) : id = id ?? const Uuid().v4();
}
