// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'post.dart';

// **************************************************************************
// ModelGenerator
// **************************************************************************

// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

// **************************************************************************
// dartdata ModelGenerator
// **************************************************************************

/// Type-safe query field descriptors for [Post].
abstract class $Post {
  static final QueryField<String> idField = QueryField<String>('id');
  static final QueryField<String> titleField = QueryField<String>('title');
  static final QueryField<String> bodyField = QueryField<String>('body_text');
  static final QueryField<DateTime> publishedAtField =
      QueryField<DateTime>('published_at');
  static final QueryField<bool> isDraftField = QueryField<bool>('is_draft');
}

/// [ModelDescriptor] for [Post]. Registered via [Schema].
class _PostDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'post';

  @override
  String get modelClassName => 'Post';

  @override
  Type get modelType => Post;

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
            columnName: 'title',
            type: ColumnType.text,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: true,
            isNullable: false),
        ColumnDefinition(
            columnName: 'body_text',
            type: ColumnType.text,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: false),
        ColumnDefinition(
            columnName: 'published_at',
            type: ColumnType.integer,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: false),
        ColumnDefinition(
            columnName: 'is_draft',
            type: ColumnType.integer,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: false),
        ColumnDefinition(
            columnName: 'author_id',
            type: ColumnType.integer,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [
        RelationshipDefinition(
          fieldName: 'author',
          relatedTable: 'author',
          cardinality: RelationshipCardinality.toOne,
          deleteRule: DeleteRule.nullify,
          fkColumnName: 'author_id',
          isForeignKeySide: true,
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  Post fromMap(Map<String, Object?> row) {
    return Post(
      id: row['id'] as String,
      title: row['title'] as String,
      body: row['body_text'] as String,
      publishedAt: DateTime.fromMillisecondsSinceEpoch(
          row['published_at'] as int,
          isUtc: true),
      isDraft: (row['is_draft'] as int) != 0,
    );
  }

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as Post;
    return {
      'id': m.id,
      'title': m.title,
      'body_text': m.body,
      'published_at': m.publishedAt.toUtc().millisecondsSinceEpoch,
      'is_draft': m.isDraft ? 1 : 0,
    };
  }
}

extension PostPersistence on Post {
  static final ModelDescriptor descriptor = _PostDescriptor();
}
