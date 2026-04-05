// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comment.dart';

// **************************************************************************
// ModelGenerator
// **************************************************************************

// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

// **************************************************************************
// dartdata ModelGenerator
// **************************************************************************

/// Type-safe query field descriptors for [Comment].
abstract class $Comment {
  static final QueryField<String> idField = QueryField<String>('id');
  static final QueryField<String> textField = QueryField<String>('text');
  static final QueryField<DateTime> createdAtField =
      QueryField<DateTime>('created_at');
}

/// [ModelDescriptor] for [Comment]. Registered via [Schema].
class _CommentDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'comment';

  @override
  String get modelClassName => 'Comment';

  @override
  Type get modelType => Comment;

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
            columnName: 'text',
            type: ColumnType.text,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: false),
        ColumnDefinition(
            columnName: 'created_at',
            type: ColumnType.integer,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: false),
        ColumnDefinition(
            columnName: 'post_id',
            type: ColumnType.text,
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
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  Comment fromMap(Map<String, Object?> row) {
    return Comment(
      id: row['id'] as String,
      text: row['text'] as String,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int,
          isUtc: true),
    );
  }

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as Comment;
    return {
      'id': m.id,
      'text': m.text,
      'created_at': m.createdAt.toUtc().millisecondsSinceEpoch,
      'post_id': m.post?.id,
    };
  }
}

extension CommentPersistence on Comment {
  static final ModelDescriptor descriptor = _CommentDescriptor();
}
