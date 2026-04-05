/// dartdata — A Flutter persistence library inspired by SwiftData.
///
/// Quick start:
/// ```dart
/// import 'package:dartdata/dartdata.dart';
///
/// @model
/// class Trip {
///   @attribute(primaryKey: true)
///   final String id;
///   String name;
///   DateTime startDate;
/// }
/// ```
library dartdata;

// Annotations
export 'src/annotations/model.dart';
export 'src/annotations/relationship.dart';

// Context
export 'src/context/model_container.dart';
export 'src/context/model_context.dart';

// Query
export 'src/query/query.dart';

// Storage
export 'src/storage/external_file.dart';

// Schema
export 'src/schema/schema.dart';
