// Hand-written test models that simulate what dartdata_generator would produce.
// These allow us to write tests before the generator is built.

import 'package:dartdata/dartdata.dart';

// ---------------------------------------------------------------------------
// Trip model
// ---------------------------------------------------------------------------

class Trip {
  final String id;
  String name;
  String destination;
  DateTime startDate;
  DateTime endDate;

  Trip({
    required this.id,
    required this.name,
    required this.destination,
    required this.startDate,
    required this.endDate,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'destination': destination,
        'start_date': startDate.toUtc().millisecondsSinceEpoch,
        'end_date': endDate.toUtc().millisecondsSinceEpoch,
      };
}

/// Simulates what the generator emits as `$Trip`.
abstract class $Trip {
  static final destination = QueryField<String>('destination');
  static final name = QueryField<String>('name');
  static final startDate = QueryField<DateTime>('start_date');
  static final endDate = QueryField<DateTime>('end_date');
}

/// The [ModelDescriptor] for [Trip].
class TripDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'trip';

  @override
  String get modelClassName => 'Trip';

  @override
  Type get modelType => Trip;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'name', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'destination', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'start_date', type: ColumnType.integer),
        const ColumnDefinition(
            columnName: 'end_date', type: ColumnType.integer),
      ];

  @override
  List<RelationshipDefinition> get relationships => [
        const RelationshipDefinition(
          fieldName: 'bucketList',
          relatedTable: 'bucket_list_item',
          cardinality: RelationshipCardinality.toMany,
          inverseFieldName: 'trip',
          deleteRule: DeleteRule.cascade,
          fkColumnName: 'trip_id',
        ),
        const RelationshipDefinition(
          fieldName: 'accommodation',
          relatedTable: 'living_accommodation',
          cardinality: RelationshipCardinality.toOne,
          inverseFieldName: 'trip',
          deleteRule: DeleteRule.nullify,
          fkColumnName: 'trip_id',
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  Trip fromMap(Map<String, Object?> row) => Trip(
        id: row['id'] as String,
        name: row['name'] as String,
        destination: row['destination'] as String,
        startDate: DateTime.fromMillisecondsSinceEpoch(
            row['start_date'] as int,
            isUtc: true),
        endDate: DateTime.fromMillisecondsSinceEpoch(row['end_date'] as int,
            isUtc: true),
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as Trip;
    return m.toMap();
  }
}

// ---------------------------------------------------------------------------
// TripV2 — Trip with an extra 'notes' column, for migration testing
// ---------------------------------------------------------------------------

class TripV2Descriptor extends ModelDescriptor {
  @override
  String get tableName => 'trip';

  @override
  String get modelClassName => 'Trip';

  @override
  Type get modelType => Trip;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'name', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'destination', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'start_date', type: ColumnType.integer),
        const ColumnDefinition(
            columnName: 'end_date', type: ColumnType.integer),
        const ColumnDefinition(
            columnName: 'notes', type: ColumnType.text, isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [];

  @override
  List<String> get externalFileFields => [];

  @override
  Trip fromMap(Map<String, Object?> row) => Trip(
        id: row['id'] as String,
        name: row['name'] as String,
        destination: row['destination'] as String,
        startDate: DateTime.fromMillisecondsSinceEpoch(
            row['start_date'] as int,
            isUtc: true),
        endDate: DateTime.fromMillisecondsSinceEpoch(row['end_date'] as int,
            isUtc: true),
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as Trip;
    return m.toMap();
  }
}

// ---------------------------------------------------------------------------
// TripV3 — Trip with a non-nullable unique 'tag' column, for constraint testing
// ---------------------------------------------------------------------------

class TripV3Descriptor extends ModelDescriptor {
  @override
  String get tableName => 'trip';

  @override
  String get modelClassName => 'Trip';

  @override
  Type get modelType => Trip;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'name', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'destination', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'start_date', type: ColumnType.integer),
        const ColumnDefinition(
            columnName: 'end_date', type: ColumnType.integer),
        const ColumnDefinition(
            columnName: 'tag',
            type: ColumnType.text,
            isNullable: false,
            isUnique: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [];

  @override
  List<String> get externalFileFields => [];

  @override
  Trip fromMap(Map<String, Object?> row) => Trip(
        id: row['id'] as String,
        name: row['name'] as String,
        destination: row['destination'] as String,
        startDate: DateTime.fromMillisecondsSinceEpoch(
            row['start_date'] as int,
            isUtc: true),
        endDate: DateTime.fromMillisecondsSinceEpoch(row['end_date'] as int,
            isUtc: true),
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as Trip;
    return m.toMap();
  }
}

// ---------------------------------------------------------------------------
// Photo model (with ExternalFile)
// ---------------------------------------------------------------------------

class Photo {
  final String id;
  String title;
  ExternalFile? imageData;

  Photo({required this.id, required this.title, this.imageData});

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        // ExternalFile UUID injected by ModelContext during save
        'image_data': null,
      };

  ExternalFile? getExternalFile(String fieldName) {
    if (fieldName == 'image_data') return imageData;
    return null;
  }
}

class PhotoDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'photo';

  @override
  String get modelClassName => 'Photo';

  @override
  Type get modelType => Photo;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'title', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'image_data', type: ColumnType.text, isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [];

  @override
  List<String> get externalFileFields => ['image_data'];

  @override
  Photo fromMap(Map<String, Object?> row) => Photo(
        id: row['id'] as String,
        title: row['title'] as String,
        imageData: row['image_data'] != null
            ? ExternalFile.fromManagedPath(row['image_data'] as String)
            : null,
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as Photo;
    return m.toMap();
  }

  @override
  ExternalFile? getExternalFile(Object model, String fieldName) {
    final m = model as Photo;
    switch (fieldName) {
      case 'image_data': return m.imageData;
      default: return null;
    }
  }
}

// ---------------------------------------------------------------------------
// BucketListItem model (child of Trip, one-to-many)
// ---------------------------------------------------------------------------

class BucketListItem {
  final String id;
  String title;
  bool isInBucket;
  Trip? trip; // object reference — FK resolved by ModelContext at save time

  BucketListItem({
    required this.id,
    required this.title,
    this.isInBucket = false,
    this.trip,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'is_in_bucket': isInBucket ? 1 : 0,
        'trip_id': null, // FK resolved by ModelContext via getRelationshipIds
      };
}

abstract class $BucketListItem {
  static final title = QueryField<String>('title');
  static final tripId = QueryField<int>('trip_id');
}

class BucketListItemDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'bucket_list_item';

  @override
  String get modelClassName => 'BucketListItem';

  @override
  Type get modelType => BucketListItem;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'title', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'is_in_bucket', type: ColumnType.integer),
        const ColumnDefinition(
            columnName: 'trip_id',
            type: ColumnType.integer,
            isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [
        const RelationshipDefinition(
          fieldName: 'trip',
          relatedTable: 'trip',
          cardinality: RelationshipCardinality.toOne,
          inverseFieldName: 'bucketList',
          deleteRule: DeleteRule.cascade,
          fkColumnName: 'trip_id',
          isForeignKeySide: true,
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  BucketListItem fromMap(Map<String, Object?> row) => BucketListItem(
        id: row['id'] as String,
        title: row['title'] as String,
        isInBucket: (row['is_in_bucket'] as int) == 1,
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as BucketListItem;
    return m.toMap();
  }

  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as BucketListItem;
    return {'trip_id': m.trip?.id};
  }
}

// ---------------------------------------------------------------------------
// SubItem model (child of BucketListItem, for nested cascade testing)
// ---------------------------------------------------------------------------

class SubItem {
  final String id;
  String note;
  BucketListItem? bucketListItem;

  SubItem({
    required this.id,
    required this.note,
    this.bucketListItem,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'note': note,
        'bucket_list_item_id':
            null, // FK resolved by ModelContext via getRelationshipIds
      };
}

class SubItemDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'sub_item';

  @override
  String get modelClassName => 'SubItem';

  @override
  Type get modelType => SubItem;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'note', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'bucket_list_item_id',
            type: ColumnType.integer,
            isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [
        const RelationshipDefinition(
          fieldName: 'bucket_list_item',
          relatedTable: 'bucket_list_item',
          cardinality: RelationshipCardinality.toOne,
          inverseFieldName: 'subItems',
          deleteRule: DeleteRule.cascade,
          fkColumnName: 'bucket_list_item_id',
          isForeignKeySide: true,
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  SubItem fromMap(Map<String, Object?> row) => SubItem(
        id: row['id'] as String,
        note: row['note'] as String,
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as SubItem;
    return m.toMap();
  }

  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as SubItem;
    return {'bucket_list_item_id': m.bucketListItem?.id};
  }
}

/// Variant of [BucketListItemDescriptor] with [DeleteRule.deny] for testing.
class DenyBucketListItemDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'bucket_list_item';

  @override
  String get modelClassName => 'BucketListItem';

  @override
  Type get modelType => BucketListItem;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'title', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'is_in_bucket', type: ColumnType.integer),
        const ColumnDefinition(
            columnName: 'trip_id',
            type: ColumnType.integer,
            isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [
        const RelationshipDefinition(
          fieldName: 'trip',
          relatedTable: 'trip',
          cardinality: RelationshipCardinality.toOne,
          inverseFieldName: 'bucketList',
          deleteRule: DeleteRule.deny,
          fkColumnName: 'trip_id',
          isForeignKeySide: true,
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  BucketListItem fromMap(Map<String, Object?> row) => BucketListItem(
        id: row['id'] as String,
        title: row['title'] as String,
        isInBucket: (row['is_in_bucket'] as int) == 1,
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as BucketListItem;
    return m.toMap();
  }

  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as BucketListItem;
    return {'trip_id': m.trip?.id};
  }
}

/// Variant of [BucketListItemDescriptor] with [DeleteRule.noAction] for testing.
class NoActionBucketListItemDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'bucket_list_item';

  @override
  String get modelClassName => 'BucketListItem';

  @override
  Type get modelType => BucketListItem;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'title', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'is_in_bucket', type: ColumnType.integer),
        const ColumnDefinition(
            columnName: 'trip_id',
            type: ColumnType.integer,
            isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [
        const RelationshipDefinition(
          fieldName: 'trip',
          relatedTable: 'trip',
          cardinality: RelationshipCardinality.toOne,
          inverseFieldName: 'bucketList',
          deleteRule: DeleteRule.noAction,
          fkColumnName: 'trip_id',
          isForeignKeySide: true,
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  BucketListItem fromMap(Map<String, Object?> row) => BucketListItem(
        id: row['id'] as String,
        title: row['title'] as String,
        isInBucket: (row['is_in_bucket'] as int) == 1,
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as BucketListItem;
    return m.toMap();
  }

  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as BucketListItem;
    return {'trip_id': m.trip?.id};
  }
}

// ---------------------------------------------------------------------------
// LivingAccommodation model (one-to-one optional on Trip)
// ---------------------------------------------------------------------------

class LivingAccommodation {
  final String id;
  String address;
  Trip? trip; // object reference — FK resolved by ModelContext at save time

  LivingAccommodation({
    required this.id,
    required this.address,
    this.trip,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'address': address,
        'trip_id': null, // FK resolved by ModelContext via getRelationshipIds
      };
}

abstract class $LivingAccommodation {
  static final address = QueryField<String>('address');
  static final tripId = QueryField<int>('trip_id');
}

// ---------------------------------------------------------------------------
// Tag model (many-to-many with Trip via junction table)
// ---------------------------------------------------------------------------

class Tag {
  final String id;
  String name;

  Tag({required this.id, required this.name});

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
      };
}

abstract class $Tag {
  static final name = QueryField<String>('name');
}

class TagDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'tag';

  @override
  String get modelClassName => 'Tag';

  @override
  Type get modelType => Tag;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'name', type: ColumnType.text),
      ];

  @override
  List<RelationshipDefinition> get relationships => [
        const RelationshipDefinition(
          fieldName: 'trips',
          relatedTable: 'trip',
          cardinality: RelationshipCardinality.toMany,
          inverseFieldName: 'tags',
          deleteRule: DeleteRule.nullify,
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  List<JunctionTableDefinition> get junctionTables => [
        const JunctionTableDefinition(
          tableName: '_tag_trip',
          firstFkColumn: 'tag_id',
          firstTable: 'tag',
          secondFkColumn: 'trip_id',
          secondTable: 'trip',
        ),
      ];

  @override
  Tag fromMap(Map<String, Object?> row) => Tag(
        id: row['id'] as String,
        name: row['name'] as String,
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as Tag;
    return m.toMap();
  }
}

class LivingAccommodationDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'living_accommodation';

  @override
  String get modelClassName => 'LivingAccommodation';

  @override
  Type get modelType => LivingAccommodation;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'address', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'trip_id',
            type: ColumnType.integer,
            isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [
        const RelationshipDefinition(
          fieldName: 'trip',
          relatedTable: 'trip',
          cardinality: RelationshipCardinality.toOne,
          deleteRule: DeleteRule.nullify,
          fkColumnName: 'trip_id',
          isForeignKeySide: true,
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  LivingAccommodation fromMap(Map<String, Object?> row) =>
      LivingAccommodation(
        id: row['id'] as String,
        address: row['address'] as String,
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as LivingAccommodation;
    return m.toMap();
  }

  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as LivingAccommodation;
    return {'trip_id': m.trip?.id};
  }
}
