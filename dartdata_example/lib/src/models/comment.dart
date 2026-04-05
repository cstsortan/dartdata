import 'package:dartdata/dartdata.dart';
import 'package:uuid/uuid.dart';

import 'post.dart';

part 'comment.g.dart';

/// A comment on a post. Uses DeleteRule.cascade — deleting the parent Post
/// deletes all its Comments.
@model
class Comment {
  @attribute(primaryKey: true)
  final String id;

  String text;
  DateTime createdAt;

  @relationship(deleteRule: DeleteRule.cascade)
  Post? post;

  Comment({
    String? id,
    required this.text,
    required this.createdAt,
    this.post,
  }) : id = id ?? const Uuid().v4();
}
