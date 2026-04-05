import 'dart:io';
import 'dart:typed_data';

import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_models.dart';

/// Integration tests for ExternalFile persistence through ModelContext.
///
/// These tests verify that ExternalFile fields are persisted to and deleted
/// from the _EXTERNAL_DATA directory when ModelContext.save() is called.
void main() {
  late ModelContainer container;
  late ModelContext context;

  setUp(() async {
    container = await ModelContainer.create(
      schema: Schema([PhotoDescriptor()]),
      configuration: const ModelConfiguration.inMemory(),
    );
    context = ModelContext(container);
  });

  tearDown(() {
    container.close();
  });

  // ---------------------------------------------------------------------------
  // Task 6.1: Insert Photo with staged bytes, verify UUID stored in column
  // ---------------------------------------------------------------------------
  group('ExternalFile persistence — staged bytes', () {
    test('insert Photo with staged bytes stores UUID in image_data column',
        () async {
      final photo = Photo(
        id: 'photo-1',
        title: 'Sunset',
        imageData: ExternalFile.fromBytes(Uint8List.fromList([1, 2, 3, 4, 5])),
      );
      context.insert(photo);
      await context.save();

      // Verify the image_data column holds a non-null string (the UUID reference).
      final rows = container.db.select(
        "SELECT image_data FROM photo WHERE id = 'photo-1'",
      );
      expect(rows.length, equals(1));
      expect(rows.first['image_data'], isNotNull);
      expect(rows.first['image_data'], isA<String>());
    });
  });

  // ---------------------------------------------------------------------------
  // Task 6.2: Verify blob file exists with correct bytes
  // ---------------------------------------------------------------------------
  group('ExternalFile persistence — blob on disk', () {
    test('blob file exists at _EXTERNAL_DATA/<uuid> with correct bytes',
        () async {
      final bytes = Uint8List.fromList([10, 20, 30, 40, 50]);
      final photo = Photo(
        id: 'photo-2',
        title: 'Mountain',
        imageData: ExternalFile.fromBytes(bytes),
      );
      context.insert(photo);
      await context.save();

      // Get the UUID from the column.
      final rows = container.db.select(
        "SELECT image_data FROM photo WHERE id = 'photo-2'",
      );
      final uuid = rows.first['image_data'] as String;

      // The blob should exist in the container's blob directory.
      final blobFile = File('${container.blobDirectory.path}/$uuid');
      expect(await blobFile.exists(), isTrue);
      expect(await blobFile.readAsBytes(), equals(bytes));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 6.3: Insert Photo with staged path, verify file copied
  // ---------------------------------------------------------------------------
  group('ExternalFile persistence — staged path', () {
    test('staged path file is copied into _EXTERNAL_DATA', () async {
      // Create a temp source file.
      final sourceDir = await Directory.systemTemp.createTemp('dartdata_test_');
      final sourceFile = File('${sourceDir.path}/source_image.bin');
      final sourceBytes = Uint8List.fromList([60, 70, 80, 90]);
      await sourceFile.writeAsBytes(sourceBytes);
      addTearDown(() async {
        if (await sourceDir.exists()) {
          await sourceDir.delete(recursive: true);
        }
      });

      final photo = Photo(
        id: 'photo-3',
        title: 'From Path',
        imageData: ExternalFile.fromPath(sourceFile.path),
      );
      context.insert(photo);
      await context.save();

      // Get the UUID from the column.
      final rows = container.db.select(
        "SELECT image_data FROM photo WHERE id = 'photo-3'",
      );
      final uuid = rows.first['image_data'] as String;

      // Blob should exist with source bytes.
      final blobFile = File('${container.blobDirectory.path}/$uuid');
      expect(await blobFile.exists(), isTrue);
      expect(await blobFile.readAsBytes(), equals(sourceBytes));

      // Source should be untouched.
      expect(await sourceFile.exists(), isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Task 6.4: Delete Photo with managed ExternalFile, verify blob removed
  // ---------------------------------------------------------------------------
  group('ExternalFile persistence — delete', () {
    test('deleting a Photo removes the blob from _EXTERNAL_DATA', () async {
      final photo = Photo(
        id: 'photo-del',
        title: 'To Delete',
        imageData: ExternalFile.fromBytes(Uint8List.fromList([1, 2, 3])),
      );
      context.insert(photo);
      await context.save();

      // Get the blob path before deletion.
      final rows = container.db.select(
        "SELECT image_data FROM photo WHERE id = 'photo-del'",
      );
      final uuid = rows.first['image_data'] as String;
      final blobFile = File('${container.blobDirectory.path}/$uuid');
      expect(await blobFile.exists(), isTrue);

      // Delete and save.
      context.delete(photo);
      await context.save();

      // Row should be gone.
      final afterRows = container.db.select(
        "SELECT * FROM photo WHERE id = 'photo-del'",
      );
      expect(afterRows, isEmpty);

      // Blob file should be removed.
      expect(await blobFile.exists(), isFalse);
    });
  });

  // ---------------------------------------------------------------------------
  // Task 6.5: Insert Photo with imageData = null, verify column is NULL
  // ---------------------------------------------------------------------------
  group('ExternalFile persistence — null field', () {
    test('Photo with null imageData stores NULL in column', () async {
      final photo = Photo(
        id: 'photo-null',
        title: 'No Image',
        imageData: null,
      );
      context.insert(photo);
      await context.save();

      final rows = container.db.select(
        "SELECT image_data FROM photo WHERE id = 'photo-null'",
      );
      expect(rows.length, equals(1));
      expect(rows.first['image_data'], isNull);
    });
  });
}
