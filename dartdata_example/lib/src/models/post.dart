import 'package:dartdata/dartdata.dart';
import 'package:uuid/uuid.dart';

import 'author.dart';

part 'post.g.dart';

/// A blog post demonstrating primaryKey, indexed, transient, columnName,
/// DateTime, bool, and a one-to-many owner relationship to Author.
@model
class Post {
  @attribute(primaryKey: true)
  final String id;

  @attribute(indexed: true)
  String title;

  @attribute(columnName: 'body_text')
  String body;

  DateTime publishedAt;

  bool isDraft;

  @attribute(transient: true)
  int wordCount;

  @relationship(deleteRule: DeleteRule.nullify)
  Author? author;

  Post({
    String? id,
    required this.title,
    required this.body,
    required this.publishedAt,
    this.isDraft = true,
    this.wordCount = 0,
    this.author,
  }) : id = id ?? const Uuid().v4();
}
