import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_models.dart';

/// Relationship tests.
///
/// NOTE: Most of these tests exercise behaviour that is NOT YET IMPLEMENTED
/// (delete rules, relationship fetching). They document the intended API
/// from API_DESIGN.md and serve as the Red backlog for future implementation.
void main() {
  late ModelContainer container;
  late ModelContext context;

  setUp(() async {
    container = await ModelContainer.create(
      schema: Schema([
        TripDescriptor(),
        BucketListItemDescriptor(),
        LivingAccommodationDescriptor(),
      ]),
      configuration: const ModelConfiguration.inMemory(),
    );
    context = ModelContext(container);
  });

  tearDown(() => container.close());

  // ---------------------------------------------------------------------------
  // Task 5.1: Relationship test models exist
  // (Verified by the fact that setUp creates tables without error)
  // ---------------------------------------------------------------------------
  group('Relationship models — table creation', () {
    test('bucket_list_item table is created', () {
      final tables = container.db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toList();
      expect(tables, contains('bucket_list_item'));
    });

    test('living_accommodation table is created', () {
      final tables = container.db
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'] as String)
          .toList();
      expect(tables, contains('living_accommodation'));
    });

    test('bucket_list_item has trip_id FK column', () {
      final cols = container.db
          .select("PRAGMA table_info(bucket_list_item)")
          .map((r) => r['name'] as String)
          .toList();
      expect(cols, contains('trip_id'));
    });

    test('living_accommodation has trip_id FK column', () {
      final cols = container.db
          .select("PRAGMA table_info(living_accommodation)")
          .map((r) => r['name'] as String)
          .toList();
      expect(cols, contains('trip_id'));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 5.2: Insert Trip with BucketListItem, verify FK
  // ---------------------------------------------------------------------------
  group('Relationship — foreign key storage', () {
    test('BucketListItem FK matches Trip id after insert + save', () async {
      final trip = Trip(
        id: 'trip-1',
        name: 'Grand Tour',
        destination: 'Europe',
        startDate: DateTime.utc(2026, 6, 1),
        endDate: DateTime.utc(2026, 8, 31),
      );
      context.insert(trip);

      final item = BucketListItem(
        id: 'bli-1',
        title: 'See Eiffel Tower',
        tripId: 'trip-1',
      );
      context.insert(item);
      await context.save();

      // Fetch the BucketListItem and verify FK.
      final items = await context.fetch(Query<BucketListItem>());
      expect(items.length, equals(1));
      expect(items.first.tripId, equals('trip-1'));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 5.3: DeleteRule.cascade — delete Trip deletes BucketListItems
  //
  // NOT YET IMPLEMENTED — this test documents intended behaviour.
  // ModelContext does not yet handle cascade deletes automatically.
  // ---------------------------------------------------------------------------
  group('DeleteRule.cascade', () {
    test(
      'deleting a Trip cascades to its BucketListItems',
      () async {
        final trip = Trip(
          id: 'trip-cascade',
          name: 'Cascade Trip',
          destination: 'X',
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 2),
        );
        context.insert(trip);
        context.insert(BucketListItem(
            id: 'bli-c1', title: 'Item 1', tripId: 'trip-cascade'));
        context.insert(BucketListItem(
            id: 'bli-c2', title: 'Item 2', tripId: 'trip-cascade'));
        await context.save();

        context.delete(trip);
        await context.save();

        // After cascade, BucketListItems should also be gone.
        final items = await context.fetch(Query<BucketListItem>());
        expect(items, isEmpty);
      },
      skip: 'DeleteRule.cascade not yet implemented in ModelContext',
    );
  });

  // ---------------------------------------------------------------------------
  // Task 5.4: DeleteRule.nullify — delete Trip nullifies LivingAccommodation FK
  //
  // NOT YET IMPLEMENTED.
  // ---------------------------------------------------------------------------
  group('DeleteRule.nullify', () {
    test(
      'deleting a Trip nullifies LivingAccommodation FK',
      () async {
        final trip = Trip(
          id: 'trip-nullify',
          name: 'Nullify Trip',
          destination: 'Y',
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 2),
        );
        context.insert(trip);
        context.insert(LivingAccommodation(
            id: 'acc-1', address: '123 Main St', tripId: 'trip-nullify'));
        await context.save();

        context.delete(trip);
        await context.save();

        final accommodations =
            await context.fetch(Query<LivingAccommodation>());
        expect(accommodations.length, equals(1));
        expect(accommodations.first.tripId, isNull);
      },
      skip: 'DeleteRule.nullify not yet implemented in ModelContext',
    );
  });

  // ---------------------------------------------------------------------------
  // Task 5.5: DeleteRule.deny — delete Trip with related items throws
  //
  // NOT YET IMPLEMENTED.
  // ---------------------------------------------------------------------------
  group('DeleteRule.deny', () {
    test(
      'deleting a Trip with related BucketListItems throws StateError',
      () async {
        final trip = Trip(
          id: 'trip-deny',
          name: 'Deny Trip',
          destination: 'Z',
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 2),
        );
        context.insert(trip);
        context.insert(BucketListItem(
            id: 'bli-d1', title: 'Block delete', tripId: 'trip-deny'));
        await context.save();

        context.delete(trip);
        expect(() async => await context.save(), throwsStateError);
      },
      skip: 'DeleteRule.deny not yet implemented in ModelContext',
    );
  });

  // ---------------------------------------------------------------------------
  // Task 5.6: One-to-one optional (LivingAccommodation? with null FK)
  // ---------------------------------------------------------------------------
  group('One-to-one optional', () {
    test('LivingAccommodation with null tripId stores NULL FK', () async {
      context.insert(LivingAccommodation(
        id: 'acc-orphan',
        address: '456 Elm St',
        tripId: null,
      ));
      await context.save();

      // Verify FK column is NULL in SQLite.
      final rows = container.db.select(
        "SELECT trip_id FROM living_accommodation WHERE id = 'acc-orphan'",
      );
      expect(rows.first['trip_id'], isNull);
    });

    test('LivingAccommodation with tripId stores the FK value', () async {
      final trip = Trip(
        id: 'trip-opt',
        name: 'Optional Trip',
        destination: 'W',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      context.insert(trip);
      context.insert(LivingAccommodation(
        id: 'acc-linked',
        address: '789 Oak Ave',
        tripId: 'trip-opt',
      ));
      await context.save();

      final rows = container.db.select(
        "SELECT trip_id FROM living_accommodation WHERE id = 'acc-linked'",
      );
      expect(rows.first['trip_id'], equals('trip-opt'));
    });
  });
}
