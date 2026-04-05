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

  // ---------------------------------------------------------------------------
  // Phase 3: Edge Cases
  // ---------------------------------------------------------------------------
  group('Optimistic locking — edge cases', () {
    test('Task 3.1: new insert (no prior fetch) always succeeds with z_opt 0',
        () async {
      // Insert a brand new object — no version cached.
      context.insert(Trip(
        id: 'new-1',
        name: 'Brand New',
        destination: 'Tokyo',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await context.save();

      expect(context.versionOf<Trip>('new-1'), equals(0));
    });

    test('Task 3.3: OptimisticLockError inside transaction rolls back',
        () async {
      // Insert a row.
      context.insert(Trip(
        id: 'tx-lock-1',
        name: 'Original',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await context.save();

      // ctx1 fetches and updates.
      final ctx1 = ModelContext(container);
      await ctx1.fetchOne<Trip>(id: 'tx-lock-1');
      ctx1.insert(Trip(
        id: 'tx-lock-1',
        name: 'ctx1 update',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await ctx1.save();

      // ctx2 fetched before ctx1 saved — stale version.
      final ctx2 = ModelContext(container);
      await ctx2.fetchOne<Trip>(id: 'tx-lock-1');
      // Manually set ctx2's version to 0 to simulate stale fetch.
      // Actually, ctx2 fetched after ctx1 saved, so it has version 1.
      // We need a context that fetched before ctx1's save.
      // Let's use a fresh approach: ctx2 has the old version cached.

      // Create ctx3 that sees the pre-update version.
      final ctx3 = ModelContext(container);
      // Simulate stale version by fetching first, then having someone else update.
      await ctx3.fetchOne<Trip>(id: 'tx-lock-1');
      expect(ctx3.versionOf<Trip>('tx-lock-1'), equals(1));

      // Now ctx1 updates again, bumping version to 2.
      await ctx1.fetchOne<Trip>(id: 'tx-lock-1');
      ctx1.insert(Trip(
        id: 'tx-lock-1',
        name: 'ctx1 update 2',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await ctx1.save();

      // ctx3 tries to update inside a transaction — should throw and roll back.
      // Also insert another row in the same transaction to verify it's rolled back.
      expect(
        () => ctx3.transaction(() async {
          ctx3.insert(Trip(
            id: 'tx-extra',
            name: 'Extra',
            destination: 'Berlin',
            startDate: DateTime.utc(2026, 1, 1),
            endDate: DateTime.utc(2026, 1, 10),
          ));
          ctx3.insert(Trip(
            id: 'tx-lock-1',
            name: 'ctx3 stale update',
            destination: 'Paris',
            startDate: DateTime.utc(2026, 1, 1),
            endDate: DateTime.utc(2026, 1, 10),
          ));
        }),
        throwsA(isA<OptimisticLockError>()),
      );

      // The extra row should NOT have been committed.
      final extra = await context.fetchOne<Trip>(id: 'tx-extra');
      expect(extra, isNull);

      // Verify _versions cache was restored after rollback.
      // ctx3 fetched 'tx-lock-1' at z_opt 1, so after rollback it should
      // still report 1 (not a post-upsert value from the rolled-back tx).
      expect(ctx3.versionOf<Trip>('tx-lock-1'), equals(1));
      // tx-extra was never fetched, so it should not appear in the cache.
      expect(ctx3.versionOf<Trip>('tx-extra'), isNull);
    });

    test('Task 3.5: deleting a concurrently updated row still succeeds',
        () async {
      // Insert a row.
      context.insert(Trip(
        id: 'del-lock-1',
        name: 'To Delete',
        destination: 'Rome',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await context.save();

      // ctx1 fetches and updates (bumps z_opt to 1).
      final ctx1 = ModelContext(container);
      await ctx1.fetchOne<Trip>(id: 'del-lock-1');
      ctx1.insert(Trip(
        id: 'del-lock-1',
        name: 'Updated',
        destination: 'Rome',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await ctx1.save();

      // context deletes with stale version — should still succeed.
      final trip = Trip(
        id: 'del-lock-1',
        name: 'To Delete',
        destination: 'Rome',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      );
      context.delete(trip);
      await context.save();

      // Verify the row is gone.
      final result = await context.fetchOne<Trip>(id: 'del-lock-1');
      expect(result, isNull);
    });
  });
}
