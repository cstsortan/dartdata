import 'dart:typed_data';

import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ExternalFile state machine', () {
    test('fromBytes is staged and not yet accessible via file', () {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([1, 2, 3]));
      expect(ef.isStaged, isTrue);
      expect(ef.isManaged, isFalse);
      expect(() => ef.file, throwsStateError);
    });

    test('fromPath is staged and not yet accessible via file', () {
      final ef = ExternalFile.fromPath('/tmp/some-image.jpg');
      expect(ef.isStaged, isTrue);
      expect(() => ef.file, throwsStateError);
    });

    test('delete marks file as pending deletion', () {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([1, 2, 3]));
      ef.delete();
      expect(ef.isPendingDeletion, isTrue);
      expect(() => ef.file, throwsStateError);
    });

    test('persistTo writes bytes to destination and becomes managed', () async {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([10, 20, 30]));
      final dest = File('${Directory.systemTemp.path}/dartdata_test_blob');
      addTearDown(() => dest.existsSync() ? dest.deleteSync() : null);

      await ef.persistTo(dest);

      expect(ef.isManaged, isTrue);
      expect(ef.isStaged, isFalse);
      expect(await dest.readAsBytes(), equals([10, 20, 30]));
    });

    test('file getter works after persistTo', () async {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([1]));
      final dest = File('${Directory.systemTemp.path}/dartdata_test_blob2');
      addTearDown(() => dest.existsSync() ? dest.deleteSync() : null);

      await ef.persistTo(dest);

      expect(ef.file.path, equals(dest.path));
    });

    test('fromManagedPath creates a managed ExternalFile', () {
      final ef = ExternalFile.fromManagedPath('/managed/path/uuid-123');
      expect(ef.isManaged, isTrue);
      expect(ef.file.path, equals('/managed/path/uuid-123'));
    });

    test('persistTo on a pending-deletion file throws StateError', () async {
      final ef = ExternalFile.fromBytes(Uint8List.fromList([1]));
      ef.delete();
      final dest = File('${Directory.systemTemp.path}/should_not_exist');
      await expectLater(ef.persistTo(dest), throwsStateError);
    });

    test('removeFromDisk deletes the managed file', () async {
      final dest = File('${Directory.systemTemp.path}/dartdata_delete_test');
      await dest.writeAsBytes([9, 8, 7]);

      final ef = ExternalFile.fromManagedPath(dest.path);
      ef.delete();
      await ef.removeFromDisk();

      expect(await dest.exists(), isFalse);
    });
  });
}
