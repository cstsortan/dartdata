// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post_tag.dart';

// **************************************************************************
// ModelGenerator
// **************************************************************************

// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

// **************************************************************************
// dartdata ModelGenerator
// **************************************************************************

/// Type-safe query field descriptors for [PostTag].
abstract class $PostTag {
  static final QueryField<String> idField = QueryField<String>('id');
  static final QueryField<DateTime> pinnedAtField =
      QueryField<DateTime>('pinned_at');
}

/// [ModelDescriptor] for [PostTag]. Registered via [Schema].
class _PostTagDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'post_tag';

  @override
  String get modelClassName => 'PostTag';

  @override
  Type get modelType => PostTag;

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
            columnName: 'pinned_at',
            type: ColumnType.integer,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: true),
        ColumnDefinition(
            columnName: 'post_id',
            type: ColumnType.integer,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: true),
        ColumnDefinition(
            columnName: 'tag_id',
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
          deleteRule: DeleteRule.cascade,
          fkColumnName: 'post_id',
          isForeignKeySide: true,
        ),
        RelationshipDefinition(
          fieldName: 'tag',
          relatedTable: 'tag',
          cardinality: RelationshipCardinality.toOne,
          deleteRule: DeleteRule.cascade,
          fkColumnName: 'tag_id',
          isForeignKeySide: true,
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  PostTag fromMap(Map<String, Object?> row) {
    return PostTag(
      id: row['id'] as String,
      pinnedAt: row['pinned_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(row['pinned_at'] as int,
              isUtc: true)
          : null,
    );
  }

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as PostTag;
    return {
      'id': m.id,
      'pinned_at': m.pinnedAt?.toUtc().millisecondsSinceEpoch,
      'post_id': null, // FK resolved by ModelContext via getRelationshipIds
      'tag_id': null, // FK resolved by ModelContext via getRelationshipIds
    };
  }

  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as PostTag;
    return {
      'post_id': m.post?.id,
      'tag_id': m.tag?.id,
    };
  }
}

extension PostTagPersistence on PostTag {
  static final ModelDescriptor descriptor = _PostTagDescriptor();
}
