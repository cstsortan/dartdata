// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attachment.dart';

// **************************************************************************
// ModelGenerator
// **************************************************************************

// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

// **************************************************************************
// dartdata ModelGenerator
// **************************************************************************

/// Type-safe query field descriptors for [Attachment].
abstract class $Attachment {
  static final QueryField<String> idField = QueryField<String>('id');
  static final QueryField<String> filenameField =
      QueryField<String>('filename');
}

/// [ModelDescriptor] for [Attachment]. Registered via [Schema].
class _AttachmentDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'attachment';

  @override
  String get modelClassName => 'Attachment';

  @override
  Type get modelType => Attachment;

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
            columnName: 'filename',
            type: ColumnType.text,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: false),
        ColumnDefinition(
            columnName: 'data',
            type: ColumnType.text,
            isPrimaryKey: false,
            isUnique: false,
            isIndexed: false,
            isNullable: true),
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
  List<String> get externalFileFields => [
        'data',
      ];

  @override
  Attachment fromMap(Map<String, Object?> row) {
    return Attachment(
      id: row['id'] as String,
      filename: row['filename'] as String,
      data: row['data'] != null
          ? ExternalFile.fromManagedPath(row['data'] as String)
          : null,
    );
  }

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as Attachment;
    return {
      'id': m.id,
      'filename': m.filename,
      'data': null,
      'post_id': m.post?.id,
    };
  }

  @override
  ExternalFile? getExternalFile(Object model, String fieldName) {
    final m = model as Attachment;
    switch (fieldName) {
      case 'data':
        return m.data;
      default:
        return null;
    }
  }
}

extension AttachmentPersistence on Attachment {
  static final ModelDescriptor descriptor = _AttachmentDescriptor();
}
