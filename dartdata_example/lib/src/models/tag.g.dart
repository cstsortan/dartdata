// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tag.dart';

// **************************************************************************
// ModelGenerator
// **************************************************************************

// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

// **************************************************************************
// dartdata ModelGenerator
// **************************************************************************

/// Type-safe query field descriptors for [Tag].
abstract class $Tag {
  static final QueryField<String> idField = QueryField<String>('id');
  static final QueryField<String> nameField = QueryField<String>('name');
}

/// [ModelDescriptor] for [Tag]. Registered via [Schema].
class _TagDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'tag';

  @override
  String get modelClassName => 'Tag';

  @override
  Type get modelType => Tag;

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
            isUnique: true,
            isIndexed: false,
            isNullable: false),
      ];

  @override
  List<RelationshipDefinition> get relationships => [];

  @override
  List<String> get externalFileFields => [];

  @override
  Tag fromMap(Map<String, Object?> row) {
    return Tag(
      id: row['id'] as String,
      name: row['name'] as String,
    );
  }

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as Tag;
    return {
      'id': m.id,
      'name': m.name,
    };
  }
}

extension TagPersistence on Tag {
  static final ModelDescriptor descriptor = _TagDescriptor();
}
