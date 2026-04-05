// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'author.dart';

// **************************************************************************
// ModelGenerator
// **************************************************************************

// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

// **************************************************************************
// dartdata ModelGenerator
// **************************************************************************

/// Type-safe query field descriptors for [Author].
abstract class $Author {
  static final QueryField<String> idField = QueryField<String>('id');
  static final QueryField<String> nameField = QueryField<String>('name');
  static final QueryField<String> emailField = QueryField<String>('email');
}

/// [ModelDescriptor] for [Author]. Registered via [Schema].
class _AuthorDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'author';

  @override
  String get modelClassName => 'Author';

  @override
  Type get modelType => Author;

  @override
  List<ColumnDefinition> get columns => [
        ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isUnique: false,
            isIndexed: false,
            isNullable: false),
        ColumnDefinition(
            columnName: 'name',
            type: ColumnType.text,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: false),
        ColumnDefinition(
            columnName: 'email',
            type: ColumnType.text,
            isPrimaryKey: false,
            isUnique: true,
            isIndexed: true,
            isNullable: false),
        ColumnDefinition(
            columnName: 'photo',
            type: ColumnType.text,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [];

  @override
  List<String> get externalFileFields => [
        'photo',
      ];

  @override
  Author fromMap(Map<String, Object?> row) {
    return Author(
      id: row['id'] as String,
      name: row['name'] as String,
      email: row['email'] as String,
      photo: row['photo'] != null
          ? ExternalFile.fromManagedPath(row['photo'] as String)
          : null,
    );
  }

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as Author;
    return {
      'id': m.id,
      'name': m.name,
      'email': m.email,
      'photo': null,
    };
  }

  @override
  ExternalFile? getExternalFile(Object model, String fieldName) {
    final m = model as Author;
    switch (fieldName) {
      case 'photo':
        return m.photo;
      default:
        return null;
    }
  }
}

extension AuthorPersistence on Author {
  static final ModelDescriptor descriptor = _AuthorDescriptor();
}
