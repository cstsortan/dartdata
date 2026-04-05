import 'package:dartdata/dartdata.dart';

import 'models/author.dart';
import 'models/post.dart';
import 'models/category.dart';
import 'models/comment.dart';
import 'models/tag.dart';
import 'models/post_tag.dart';
import 'models/attachment.dart';

/// The shared schema used by all integration tests.
///
/// Contains descriptors for all seven CMS domain models.
Schema get cmsSchema => Schema([
      AuthorPersistence.descriptor,
      PostPersistence.descriptor,
      CategoryPersistence.descriptor,
      CommentPersistence.descriptor,
      TagPersistence.descriptor,
      PostTagPersistence.descriptor,
      AttachmentPersistence.descriptor,
    ]);
