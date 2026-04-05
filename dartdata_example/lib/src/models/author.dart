import 'package:dartdata/dartdata.dart';
import 'package:uuid/uuid.dart';

part 'author.g.dart';

/// A blog author with a unique, indexed email and an optional photo blob.
@model
class Author {
  @attribute(primaryKey: true)
  final String id;

  String name;

  @attribute(unique: true, indexed: true)
  String email;

  @attribute()
  ExternalFile? photo;

  Author({
    String? id,
    required this.name,
    required this.email,
    this.photo,
  }) : id = id ?? const Uuid().v4();
}
