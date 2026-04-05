import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_models.dart';

void main() {
  late ModelContainer container;
  late ModelContext context;

  setUp(() async {
    container = await ModelContainer.create(
      schema: Schema([TripDescriptor()]),
      configuration: const ModelConfiguration.inMemory(),
    );
    context = ModelContext(container);
  });

  tearDown(() => container.close());

  // ---------------------------------------------------------------------------
  // Phase 1: Version Tracking on Fetch
  // ---------------------------------------------------------------------------
  group('Optimistic locking — version tracking', () {
    test('Task 1.1: versionOf returns null for unknown id', () {
      expect(context.versionOf<Trip>('nonexistent'), isNull);
    });

    test('Task 1.1: insert + save + fetch returns z_opt == 0', () async {
      final trip = Trip(
        id: 'v-1',
        name: 'Version Test',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      );

      context.insert(trip);
      await context.save();

      // After insert, z_opt should be 0.
      final version = context.versionOf<Trip>('v-1');
      expect(version, equals(0));
    });

    test('Task 1.3: update + save + fetch returns z_opt == 1', () async {
      // Insert original.
      context.insert(Trip(
        id: 'v-2',
        name: 'Original',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await context.save();
      expect(context.versionOf<Trip>('v-2'), equals(0));

      // Update via INSERT OR REPLACE (upsert).
      context.insert(Trip(
        id: 'v-2',
        name: 'Updated',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await context.save();

      // z_opt should have incremented to 1.
      expect(context.versionOf<Trip>('v-2'), equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Phase 2: Conflict Detection
  // ---------------------------------------------------------------------------
  group('Optimistic locking — conflict detection', () {
    test('Task 2.1: OptimisticLockError has correct fields', () {
      final error = OptimisticLockError(
        modelType: 'Trip',
        id: 'abc',
        expectedVersion: 0,
        actualVersion: 1,
      );

      expect(error, isA<OptimisticLockError>());
      expect(error.modelType, equals('Trip'));
      expect(error.id, equals('abc'));
      expect(error.expectedVersion, equals(0));
      expect(error.actualVersion, equals(1));
      expect(error.toString(), contains('Trip'));
      expect(error.toString(), contains('abc'));
    });

    test('Task 2.3: concurrent update throws OptimisticLockError', () async {
      // Insert a row.
      context.insert(Trip(
        id: 'conflict-1',
        name: 'Original',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await context.save();

      // Two contexts fetch the same row.
      final ctx1 = ModelContext(container);
      final ctx2 = ModelContext(container);

      await ctx1.fetchOne<Trip>(id: 'conflict-1');
      await ctx2.fetchOne<Trip>(id: 'conflict-1');

      // Context 1 updates and saves — should succeed.
      ctx1.insert(Trip(
        id: 'conflict-1',
        name: 'Updated by ctx1',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await ctx1.save();

      // Context 2 updates and saves — should throw OptimisticLockError.
      ctx2.insert(Trip(
        id: 'conflict-1',
        name: 'Updated by ctx2',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));

      expect(
        () => ctx2.save(),
        throwsA(isA<OptimisticLockError>()
            .having((e) => e.expectedVersion, 'expectedVersion', 0)
            .having((e) => e.actualVersion, 'actualVersion', 1)),
      );
    });

    test('Task 2.5: sequential updates increment z_opt to 2', () async {
      context.insert(Trip(
        id: 'seq-1',
        name: 'V0',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await context.save();
      expect(context.versionOf<Trip>('seq-1'), equals(0));

      // First update.
      await context.fetchOne<Trip>(id: 'seq-1');
      context.insert(Trip(
        id: 'seq-1',
        name: 'V1',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await context.save();
      expect(context.versionOf<Trip>('seq-1'), equals(1));

      // Second update.
      await context.fetchOne<Trip>(id: 'seq-1');
      context.insert(Trip(
        id: 'seq-1',
        name: 'V2',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await context.save();
      expect(context.versionOf<Trip>('seq-1'), equals(2));
    });
  });
}
