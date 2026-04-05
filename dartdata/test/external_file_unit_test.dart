import 'dart:io';
import 'dart:typed_data';

import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Task 2.1: ExternalFile.fromBytes → _StagedBytesState
  // ---------------------------------------------------------------------------
  group('ExternalFile.fromBytes (staged bytes)', () {
    test('creates a staged ExternalFile', () {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([1, 2, 3]));
      expect(ef.isStaged, isTrue);
      expect(ef.isManaged, isFalse);
      expect(ef.isPendingDeletion, isFalse);
    });

    test('accessing .file throws StateError', () {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([1, 2, 3]));
      expect(() => ef.file, throwsStateError);
    });

    test('accessing .uri throws StateError (delegates to .file)', () {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([1, 2, 3]));
      expect(() => ef.uri, throwsStateError);
    });
  });

  // ---------------------------------------------------------------------------
  // Task 2.2: ExternalFile.fromPath → _StagedPathState
  // ---------------------------------------------------------------------------
  group('ExternalFile.fromPath (staged path)', () {
    test('creates a staged ExternalFile', () {
      final ef = ExternalFile.fromPath('/tmp/some-image.jpg');
      expect(ef.isStaged, isTrue);
      expect(ef.isManaged, isFalse);
      expect(ef.isPendingDeletion, isFalse);
    });

    test('accessing .file throws StateError', () {
      final ef = ExternalFile.fromPath('/tmp/some-image.jpg');
      expect(() => ef.file, throwsStateError);
    });
  });

  // ---------------------------------------------------------------------------
  // Task 2.3: ExternalFile.fromManagedPath → _ManagedState
  // ---------------------------------------------------------------------------
  group('ExternalFile.fromManagedPath (managed)', () {
    test('creates a managed ExternalFile', () {
      final ef = ExternalFile.fromManagedPath('/managed/_EXTERNAL_DATA/uuid-abc');
      expect(ef.isManaged, isTrue);
      expect(ef.isStaged, isFalse);
      expect(ef.isPendingDeletion, isFalse);
    });

    test('.file returns a dart:io File pointing to the managed path', () {
      final ef = ExternalFile.fromManagedPath('/managed/_EXTERNAL_DATA/uuid-abc');
      expect(ef.file, isA<File>());
      expect(ef.file.path, equals('/managed/_EXTERNAL_DATA/uuid-abc'));
    });

    test('.uri returns the file URI', () {
      final ef = ExternalFile.fromManagedPath('/managed/_EXTERNAL_DATA/uuid-abc');
      expect(ef.uri, equals(ef.file.uri));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 2.4: _PendingDeletionState
  // ---------------------------------------------------------------------------
  group('PendingDeletion state', () {
    test('delete() on staged bytes transitions to pending deletion', () {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([1, 2, 3]));
      ef.delete();
      expect(ef.isPendingDeletion, isTrue);
      expect(ef.isStaged, isFalse);
      expect(ef.isManaged, isFalse);
    });

    test('delete() on staged path transitions to pending deletion', () {
      final ef = ExternalFile.fromPath('/tmp/image.jpg');
      ef.delete();
      expect(ef.isPendingDeletion, isTrue);
    });

    test('delete() on managed file transitions to pending deletion', () {
      final ef = ExternalFile.fromManagedPath('/managed/uuid-abc');
      ef.delete();
      expect(ef.isPendingDeletion, isTrue);
      expect(ef.isManaged, isFalse);
    });

    test('.file throws StateError in pending deletion state', () {
      final ef = ExternalFile.fromManagedPath('/managed/uuid-abc');
      ef.delete();
      expect(() => ef.file, throwsStateError);
    });

    test('delete() is idempotent — calling twice does not throw', () {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([1]));
      ef.delete();
      ef.delete(); // should not throw
      expect(ef.isPendingDeletion, isTrue);
    });
  });

  // ---------------------------------------------------------------------------
  // Task 2.5: State transitions
  // ---------------------------------------------------------------------------
  group('State transitions', () {
    test('staged bytes → managed via persistTo()', () async {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([10, 20, 30]));
      final dest = File('${Directory.systemTemp.path}/dartdata_unit_test_blob_1');
      addTearDown(() async {
        if (await dest.exists()) await dest.delete();
      });

      expect(ef.isStaged, isTrue);
      await ef.persistTo(dest);
      expect(ef.isManaged, isTrue);
      expect(ef.isStaged, isFalse);
      expect(ef.file.path, equals(dest.path));
      expect(await dest.readAsBytes(), equals([10, 20, 30]));
    });

    test('staged path → managed via persistTo()', () async {
      // Create a source file to copy from.
      final source = File('${Directory.systemTemp.path}/dartdata_unit_test_source');
      await source.writeAsBytes([40, 50, 60]);
      addTearDown(() async {
        if (await source.exists()) await source.delete();
      });

      final ef = ExternalFile.fromPath(source.path);
      final dest = File('${Directory.systemTemp.path}/dartdata_unit_test_blob_2');
      addTearDown(() async {
        if (await dest.exists()) await dest.delete();
      });

      expect(ef.isStaged, isTrue);
      await ef.persistTo(dest);
      expect(ef.isManaged, isTrue);
      expect(await dest.readAsBytes(), equals([40, 50, 60]));
      // Source file should be untouched (copied, not moved).
      expect(await source.exists(), isTrue);
    });

    test('managed → pending deletion via delete()', () {
      final ef = ExternalFile.fromManagedPath('/managed/uuid-abc');
      expect(ef.isManaged, isTrue);
      ef.delete();
      expect(ef.isPendingDeletion, isTrue);
      expect(ef.isManaged, isFalse);
    });

    test('persistTo on already-managed file is a no-op', () async {
      final dest = File('${Directory.systemTemp.path}/dartdata_unit_test_managed');
      await dest.writeAsBytes([1, 2, 3]);
      addTearDown(() async {
        if (await dest.exists()) await dest.delete();
      });

      final ef = ExternalFile.fromManagedPath(dest.path);
      // persistTo should return without error or changing state.
      final newDest = File('${Directory.systemTemp.path}/dartdata_unit_test_managed_2');
      await ef.persistTo(newDest);
      expect(ef.isManaged, isTrue);
      // File at newDest should NOT be created since managed state is a no-op.
      expect(await newDest.exists(), isFalse);
    });

    test('persistTo on pending-deletion throws StateError', () async {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([1]));
      ef.delete();
      final dest = File('${Directory.systemTemp.path}/should_not_exist');
      await expectLater(ef.persistTo(dest), throwsStateError);
    });

    test('removeFromDisk deletes the managed file from disk', () async {
      final dest = File('${Directory.systemTemp.path}/dartdata_unit_test_remove');
      await dest.writeAsBytes([9, 8, 7]);

      final ef = ExternalFile.fromManagedPath(dest.path);
      ef.delete();
      await ef.removeFromDisk();

      expect(await dest.exists(), isFalse);
    });

    test('removeFromDisk is safe when managed file does not exist', () async {
      final ef = ExternalFile.fromManagedPath('/nonexistent/path/uuid');
      ef.delete();
      // Should not throw even though the file never existed.
      await ef.removeFromDisk();
    });

    test('removeFromDisk on staged-then-deleted does nothing (no file to remove)', () async {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([1]));
      ef.delete();
      // No managed file exists, so removeFromDisk should be a no-op.
      await ef.removeFromDisk();
    });
  });
}
