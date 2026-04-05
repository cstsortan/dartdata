// Hand-written test models that simulate what dartdata_generator would produce.
// These allow us to write tests before the generator is built.

import 'dart:io';

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
  List<RelationshipDefinition> get relationships => [];

  @override
  List<String> get externalFileFields => [];

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

  Photo fromMap(Map<String, Object?> row) => Photo(
        id: row['id'] as String,
        title: row['title'] as String,
        imageData: row['image_data'] != null
            ? ExternalFile.fromManagedPath(row['image_data'] as String)
            : null,
      );
}
