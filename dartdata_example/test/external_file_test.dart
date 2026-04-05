import 'dart:io';
import 'dart:typed_data';

import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dartdata_example/dartdata_example.dart';

void main() {
  late ModelContainer container;
  late ModelContext context;

  setUp(() async {
    container = await ModelContainer.create(
      schema: cmsSchema,
      configuration: const ModelConfiguration.inMemory(),
    );
    context = ModelContext(container);
  });

  tearDown(() => container.close());

  // ---------------------------------------------------------------------------
  // ExternalFile.fromBytes round-trip
  // ---------------------------------------------------------------------------

  group('ExternalFile.fromBytes round-trip', () {
    test('Author photo: stage bytes, save, fetch, read bytes back', () async {
      final photoBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

      context.insert(Author(
        id: 'a1',
        name: 'Alice',
        email: 'alice@test.com',
        photo: ExternalFile.fromBytes(photoBytes),
      ));
      await context.save();

      // Fetch the author back
      final author = (await context.fetchOne<Author>(id: 'a1'))!;
      expect(author.photo, isNotNull);
      expect(author.photo!.isManaged, isTrue);

      // Read the bytes back from the managed file
      final readBytes = await author.photo!.file.readAsBytes();
      expect(readBytes, equals(photoBytes));
    });

    test('Attachment data: stage bytes, save, fetch, verify', () async {
      final fileBytes = Uint8List.fromList([0x50, 0x4B, 0x03, 0x04]);

      context.insert(Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      await context.save();

      context.insert(Attachment(
        id: 'att1',
        filename: 'doc.zip',
        data: ExternalFile.fromBytes(fileBytes),
      ));
      await context.save();

      // Link to post using z_pk integer FK
      final postZpk = container.db.select(
        "SELECT z_pk FROM post WHERE id = 'p1'",
      ).first['z_pk'] as int;
      container.db.execute(
        'UPDATE attachment SET post_id = ? WHERE id = ?',
        [postZpk, 'att1'],
      );

      final att = (await context.fetchOne<Attachment>(id: 'att1'))!;
      expect(att.data, isNotNull);
      expect(att.data!.isManaged, isTrue);
      expect(await att.data!.file.readAsBytes(), equals(fileBytes));
    });
  });

  // ---------------------------------------------------------------------------
  // ExternalFile.fromPath round-trip
  // ---------------------------------------------------------------------------

  group('ExternalFile.fromPath round-trip', () {
    test('Attachment from temp file: copy into managed storage', () async {
      // Create a temp file to simulate an image picker result
      final tempFile = File(
        '${Directory.systemTemp.path}/dartdata_example_test_source.bin',
      );
      final sourceBytes = Uint8List.fromList([10, 20, 30, 40, 50]);
      await tempFile.writeAsBytes(sourceBytes);
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });

      context.insert(Attachment(
        id: 'att1',
        filename: 'image.png',
        data: ExternalFile.fromPath(tempFile.path),
      ));
      await context.save();

      // Source file should still exist (it's copied, not moved)
      expect(await tempFile.exists(), isTrue);

      // Fetch and verify the managed copy
      final att = (await context.fetchOne<Attachment>(id: 'att1'))!;
      expect(att.data!.isManaged, isTrue);
      expect(await att.data!.file.readAsBytes(), equals(sourceBytes));

      // Managed file path should be in the blob directory, not the source path
      expect(att.data!.file.path, isNot(equals(tempFile.path)));
    });
  });

  // ---------------------------------------------------------------------------
  // ExternalFile.file access (stream, stat, readAsBytes)
  // ---------------------------------------------------------------------------

  group('ExternalFile.file access', () {
    test('readAsBytes on managed file returns correct data', () async {
      final bytes = Uint8List.fromList(List.generate(256, (i) => i));

      context.insert(Author(
        id: 'a1',
        name: 'Bob',
        email: 'bob@test.com',
        photo: ExternalFile.fromBytes(bytes),
      ));
      await context.save();

      final author = (await context.fetchOne<Author>(id: 'a1'))!;
      final readBack = await author.photo!.file.readAsBytes();
      expect(readBack, hasLength(256));
      expect(readBack, equals(bytes));
    });

    test('file.stat returns valid file info', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

      context.insert(Author(
        id: 'a1',
        name: 'Carol',
        email: 'carol@test.com',
        photo: ExternalFile.fromBytes(bytes),
      ));
      await context.save();

      final author = (await context.fetchOne<Author>(id: 'a1'))!;
      final stat = await author.photo!.file.stat();
      expect(stat.type, FileSystemEntityType.file);
      expect(stat.size, 5);
    });

    test('file.openRead streams bytes correctly', () async {
      final bytes = Uint8List.fromList([100, 200, 150]);

      context.insert(Author(
        id: 'a1',
        name: 'Dave',
        email: 'dave@test.com',
        photo: ExternalFile.fromBytes(bytes),
      ));
      await context.save();

      final author = (await context.fetchOne<Author>(id: 'a1'))!;
      final chunks = await author.photo!.file.openRead().toList();
      final allBytes = chunks.expand((c) => c).toList();
      expect(allBytes, equals([100, 200, 150]));
    });
  });

  // ---------------------------------------------------------------------------
  // ExternalFile deletion
  // ---------------------------------------------------------------------------

  group('ExternalFile deletion', () {
    test('deleting model removes blob file from disk', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);

      context.insert(Author(
        id: 'a1',
        name: 'Eve',
        email: 'eve@test.com',
        photo: ExternalFile.fromBytes(bytes),
      ));
      await context.save();

      // Get the managed file path before deletion
      final author = (await context.fetchOne<Author>(id: 'a1'))!;
      final blobPath = author.photo!.file.path;
      expect(await File(blobPath).exists(), isTrue);

      // Delete the author
      context.delete(author);
      await context.save();

      // Blob file should be removed from disk
      expect(await File(blobPath).exists(), isFalse);

      // Author should be gone
      expect(await context.fetchCount(Query<Author>()), 0);
    });

    test('null ExternalFile field does not create a blob', () async {
      context.insert(Author(
        id: 'a1',
        name: 'Frank',
        email: 'frank@test.com',
        // photo is null — no ExternalFile
      ));
      await context.save();

      final author = (await context.fetchOne<Author>(id: 'a1'))!;
      expect(author.photo, isNull);

      // Verify no blob entry in the database column
      final row = container.db.select(
        "SELECT photo FROM author WHERE id = 'a1'",
      );
      expect(row.first['photo'], isNull);
    });
  });
}
