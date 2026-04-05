import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_models.dart';

void main() {
  group('ModelContainer', () {
    test('creates an in-memory container without throwing', () async {
      final container = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );
      addTearDown(container.close);

      expect(container, isNotNull);
    });

    test('enables WAL journal mode', () async {
      final container = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );
      addTearDown(container.close);

      final rows = container.db.select("PRAGMA journal_mode");
      expect(rows.first['journal_mode'], equals('wal'));
    });

    test('enables foreign key enforcement', () async {
      final container = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );
      addTearDown(container.close);

      final rows = container.db.select("PRAGMA foreign_keys");
      expect(rows.first['foreign_keys'], equals(1));
    });

    test('creates the model table on first open', () async {
      final container = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );
      addTearDown(container.close);

      final tables = container.db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toList();

      expect(tables, contains('trip'));
    });

    test('creates system tables on first open', () async {
      final container = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );
      addTearDown(container.close);

      final tables = container.db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toList();

      expect(tables, containsAll(['_schema_version', '_change_log']));
    });

    test('adds z_pk and z_opt system columns to model tables', () async {
      final container = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );
      addTearDown(container.close);

      final cols = container.db
          .select("PRAGMA table_info(trip)")
          .map((r) => r['name'] as String)
          .toList();

      expect(cols, containsAll(['z_pk', 'z_opt']));
    });
  });
}
