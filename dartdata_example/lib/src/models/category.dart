import 'package:dartdata/dartdata.dart';
import 'package:uuid/uuid.dart';

import 'post.dart';

part 'category.g.dart';

/// A category with a one-to-one optional relationship to Post.
/// Uses DeleteRule.nullify — deleting the category nullifies the FK on Post.
@model
class Category {
  @attribute(primaryKey: true)
  final String id;

  String name;

  @relationship(deleteRule: DeleteRule.nullify)
  Post? post;

  Category({
    String? id,
    required this.name,
    this.post,
  }) : id = id ?? const Uuid().v4();
}
