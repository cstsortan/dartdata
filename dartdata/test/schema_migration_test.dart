import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_models.dart';

void main() {
  // ===========================================================================
  // Phase 1: Schema Fingerprinting
  // ===========================================================================

  group('Schema.fingerprint', () {
    // Task 1.1: Consistent hash for the same schema
    test('returns a consistent hash for the same schema definition', () {
      final schema1 = Schema([TripDescriptor()]);
      final schema2 = Schema([TripDescriptor()]);

      expect(schema1.fingerprint, isA<String>());
      expect(schema1.fingerprint, isNotEmpty);
      expect(schema1.fingerprint, equals(schema2.fingerprint));
    });

    // Task 1.2: Hash changes when a column is added
    test('changes when a column is added to a descriptor', () {
      final schemaV1 = Schema([TripDescriptor()]);
      final schemaV2 = Schema([TripV2Descriptor()]);

      expect(schemaV1.fingerprint, isNot(equals(schemaV2.fingerprint)));
    });
  });

  group('ModelContainer — fingerprint storage', () {
    // Task 1.4: Fingerprint stored in _schema_version on first open
    test('stores fingerprint in _schema_version on first open', () async {
      final schema = Schema([TripDescriptor()]);
      final container = await ModelContainer.create(
        schema: schema,
        configuration: const ModelConfiguration.inMemory(),
      );
      addTearDown(container.close);

      final rows = container.db.select(
        "SELECT z_fingerprint FROM _schema_version WHERE z_name = 'schema'",
      );
      expect(rows.length, equals(1));
      expect(rows.first['z_fingerprint'], equals(schema.fingerprint));
    });
  });

  // ===========================================================================
  // Phase 2: MigrationPolicy.automatic
  // ===========================================================================

  group('MigrationPolicy.automatic', () {
    // Task 2.1: Extra column — old data preserved
    test('adds new column and preserves existing data', () async {
      // Open with V1 schema
      final containerV1 = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );

      containerV1.db.execute(
        "INSERT INTO trip (id, name, destination, start_date, end_date) "
        "VALUES ('t1', 'Tour', 'Paris', 0, 0)",
      );

      // Simulate reopen with V2 schema (extra column) on same DB
      final schemaV2 = Schema([TripV2Descriptor()]);
      await ModelContainer.createFromDatabase(
        schema: schemaV2,
        db: containerV1.db,
        configuration: const ModelConfiguration.inMemory(),
      );

      // Old row still present, new column is NULL
      final rows =
          containerV1.db.select("SELECT * FROM trip WHERE id = 't1'");
      expect(rows.length, equals(1));
      expect(rows.first['name'], equals('Tour'));
      expect(rows.first['notes'], isNull);

      containerV1.close();
    });

    // Task 2.2: Extra table is created
    test('creates new tables from V2 schema', () async {
      // Open with Trip only
      final containerV1 = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );

      // Reopen with Trip + Photo
      final schemaV2 = Schema([TripDescriptor(), PhotoDescriptor()]);
      await ModelContainer.createFromDatabase(
        schema: schemaV2,
        db: containerV1.db,
        configuration: const ModelConfiguration.inMemory(),
      );

      final tables = containerV1.db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toList();
      expect(tables, contains('photo'));

      containerV1.close();
    });

    // Task 2.4: Removed column is NOT dropped (additive only)
    test('does not drop columns removed from schema', () async {
      // Open with V2 (has notes column)
      final containerV2 = await ModelContainer.create(
        schema: Schema([TripV2Descriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );

      containerV2.db.execute(
        "INSERT INTO trip (id, name, destination, start_date, end_date, notes) "
        "VALUES ('t1', 'Tour', 'Paris', 0, 0, 'fun')",
      );

      // Reopen with V1 (no notes column) — notes should still exist in DB
      final schemaV1 = Schema([TripDescriptor()]);
      await ModelContainer.createFromDatabase(
        schema: schemaV1,
        db: containerV2.db,
        configuration: const ModelConfiguration.inMemory(),
      );

      final cols = containerV2.db.select("PRAGMA table_info(trip)");
      final colNames = cols.map((c) => c['name'] as String).toList();
      expect(colNames, contains('notes'));

      // Data preserved
      final rows =
          containerV2.db.select("SELECT notes FROM trip WHERE id = 't1'");
      expect(rows.first['notes'], equals('fun'));

      containerV2.close();
    });

    // Task 2.6: Fingerprint updated after automatic migration
    test('updates fingerprint after automatic migration', () async {
      final containerV1 = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );

      final schemaV2 = Schema([TripV2Descriptor()]);
      await ModelContainer.createFromDatabase(
        schema: schemaV2,
        db: containerV1.db,
        configuration: const ModelConfiguration.inMemory(),
      );

      final rows = containerV1.db.select(
        "SELECT z_fingerprint FROM _schema_version WHERE z_name = 'schema'",
      );
      expect(rows.first['z_fingerprint'], equals(schemaV2.fingerprint));

      containerV1.close();
    });
  });

  // ===========================================================================
  // Phase 3: MigrationPolicy.none and resetOnConflict
  // ===========================================================================

  group('MigrationPolicy.none', () {
    // Task 3.1: Throws SchemaMismatchError on changed schema
    test('throws SchemaMismatchError when schema has changed', () async {
      final containerV1 = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );

      final schemaV2 = Schema([TripV2Descriptor()]);
      expect(
        () => ModelContainer.createFromDatabase(
          schema: schemaV2,
          db: containerV1.db,
          configuration: const ModelConfiguration(
            migrationPolicy: MigrationPolicy.none,
          ),
        ),
        throwsA(isA<SchemaMismatchError>()),
      );

      containerV1.close();
    });

    // Task 3.3: Unchanged schema succeeds silently
    test('succeeds silently when schema is unchanged', () async {
      final containerV1 = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );

      // Reopen with same schema and none policy
      await ModelContainer.createFromDatabase(
        schema: Schema([TripDescriptor()]),
        db: containerV1.db,
        configuration: const ModelConfiguration(
          migrationPolicy: MigrationPolicy.none,
        ),
      );

      // Should not throw — if we get here, the test passes
      containerV1.close();
    });
  });

  group('MigrationPolicy.resetOnConflict', () {
    // Task 3.5: Drops and recreates on changed schema
    test('drops all model tables and recreates on schema change', () async {
      final containerV1 = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );

      containerV1.db.execute(
        "INSERT INTO trip (id, name, destination, start_date, end_date) "
        "VALUES ('t1', 'Tour', 'Paris', 0, 0)",
      );

      // Verify data exists
      var rows = containerV1.db.select("SELECT COUNT(*) as c FROM trip");
      expect(rows.first['c'], equals(1));

      // Reopen with V2 schema and resetOnConflict
      final schemaV2 = Schema([TripV2Descriptor()]);
      await ModelContainer.createFromDatabase(
        schema: schemaV2,
        db: containerV1.db,
        configuration: const ModelConfiguration(
          migrationPolicy: MigrationPolicy.resetOnConflict,
        ),
      );

      // Old data is gone
      rows = containerV1.db.select("SELECT COUNT(*) as c FROM trip");
      expect(rows.first['c'], equals(0));

      // New column exists
      final cols = containerV1.db.select("PRAGMA table_info(trip)");
      final colNames = cols.map((c) => c['name'] as String).toList();
      expect(colNames, contains('notes'));

      containerV1.close();
    });

    // Task 3.7: Unchanged schema does not drop tables
    test('does not drop tables when schema is unchanged', () async {
      final containerV1 = await ModelContainer.create(
        schema: Schema([TripDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );

      containerV1.db.execute(
        "INSERT INTO trip (id, name, destination, start_date, end_date) "
        "VALUES ('t1', 'Tour', 'Paris', 0, 0)",
      );

      // Reopen with same schema and resetOnConflict
      await ModelContainer.createFromDatabase(
        schema: Schema([TripDescriptor()]),
        db: containerV1.db,
        configuration: const ModelConfiguration(
          migrationPolicy: MigrationPolicy.resetOnConflict,
        ),
      );

      // Data still there
      final rows = containerV1.db.select("SELECT COUNT(*) as c FROM trip");
      expect(rows.first['c'], equals(1));

      containerV1.close();
    });
  });
}
