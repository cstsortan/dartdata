import 'package:dartdata/dartdata.dart';
import 'package:uuid/uuid.dart';

import 'post.dart';

part 'attachment.g.dart';

/// A file attachment on a post with ExternalFile and DeleteRule.cascade.
/// Deleting the parent Post deletes all its Attachments (and their blobs).
@model
class Attachment {
  @attribute(primaryKey: true)
  final String id;

  String filename;

  @attribute()
  ExternalFile? data;

  @relationship(deleteRule: DeleteRule.cascade)
  Post? post;

  Attachment({
    String? id,
    required this.filename,
    this.data,
    this.post,
  }) : id = id ?? const Uuid().v4();
}
