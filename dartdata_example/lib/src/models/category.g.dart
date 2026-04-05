// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'category.dart';

// **************************************************************************
// ModelGenerator
// **************************************************************************

// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

// **************************************************************************
// dartdata ModelGenerator
// **************************************************************************

/// Type-safe query field descriptors for [Category].
abstract class $Category {
  static final QueryField<String> idField = QueryField<String>('id');
  static final QueryField<String> nameField = QueryField<String>('name');
}

/// [ModelDescriptor] for [Category]. Registered via [Schema].
class _CategoryDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'category';

  @override
  String get modelClassName => 'Category';

  @override
  Type get modelType => Category;

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
            columnName: 'post_id',
            type: ColumnType.integer,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [
        RelationshipDefinition(
          fieldName: 'post',
          relatedTable: 'post',
          cardinality: RelationshipCardinality.toOne,
          deleteRule: DeleteRule.nullify,
          fkColumnName: 'post_id',
          isForeignKeySide: true,
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  Category fromMap(Map<String, Object?> row) {
    return Category(
      id: row['id'] as String,
      name: row['name'] as String,
    );
  }

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as Category;
    return {
      'id': m.id,
      'name': m.name,
      'post_id': null, // FK resolved by ModelContext via getRelationshipIds
    };
  }

  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as Category;
    return {
      'post_id': m.post?.id,
    };
  }
}

extension CategoryPersistence on Category {
  static final ModelDescriptor descriptor = _CategoryDescriptor();
}
