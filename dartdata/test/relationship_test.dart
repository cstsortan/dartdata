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
  // Task 5.2: Insert Trip with BucketListItem, verify FK stores z_pk integer
  // ---------------------------------------------------------------------------
  group('Relationship — foreign key storage', () {
    test('BucketListItem FK stores Trip z_pk integer after insert + save',
        () async {
      final trip = Trip(
        id: 'trip-1',
        name: 'Grand Tour',
        destination: 'Europe',
        startDate: DateTime.utc(2026, 6, 1),
        endDate: DateTime.utc(2026, 8, 31),
      );
      context.insert(trip);
      await context.save();

      final item = BucketListItem(
        id: 'bli-1',
        title: 'See Eiffel Tower',
        trip: trip,
      );
      context.insert(item);
      await context.save();

      // Verify FK column stores an integer (Trip's z_pk), not a UUID string.
      final rows = container.db.select(
        "SELECT trip_id FROM bucket_list_item WHERE id = 'bli-1'",
      );
      expect(rows.first['trip_id'], isA<int>());

      // The z_pk of trip-1 should be 1 (first inserted row).
      expect(rows.first['trip_id'], equals(1));
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
        await context.save();
        context.insert(BucketListItem(
            id: 'bli-c1', title: 'Item 1', trip: trip));
        context.insert(BucketListItem(
            id: 'bli-c2', title: 'Item 2', trip: trip));
        await context.save();

        context.delete(trip);
        await context.save();

        // After cascade, BucketListItems should also be gone.
        final items = await context.fetch(Query<BucketListItem>());
        expect(items, isEmpty);
      },
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
        await context.save();
        context.insert(LivingAccommodation(
            id: 'acc-1', address: '123 Main St', trip: trip));
        await context.save();

        context.delete(trip);
        await context.save();

        // Verify FK is NULL in raw SQL after nullify.
        final rows = container.db.select(
          "SELECT trip_id FROM living_accommodation WHERE id = 'acc-1'",
        );
        expect(rows.first['trip_id'], isNull);
      },
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
        // Use a separate container with deny descriptor.
        final denyContainer = await ModelContainer.create(
          schema: Schema([
            TripDescriptor(),
            DenyBucketListItemDescriptor(),
          ]),
          configuration: const ModelConfiguration.inMemory(),
        );
        final denyContext = ModelContext(denyContainer);

        final trip = Trip(
          id: 'trip-deny',
          name: 'Deny Trip',
          destination: 'Z',
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 2),
        );
        denyContext.insert(trip);
        await denyContext.save();
        denyContext.insert(BucketListItem(
            id: 'bli-d1', title: 'Block delete', trip: trip));
        await denyContext.save();

        denyContext.delete(trip);
        expect(() async => await denyContext.save(), throwsStateError);

        denyContainer.close();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // DeleteRule.noAction — delete parent, children become orphans
  // ---------------------------------------------------------------------------
  group('DeleteRule.noAction', () {
    test(
      'deleting a Trip leaves orphaned BucketListItems with stale FK',
      () async {
        // Use a separate container with noAction descriptor.
        final noActionContainer = await ModelContainer.create(
          schema: Schema([
            TripDescriptor(),
            NoActionBucketListItemDescriptor(),
          ]),
          configuration: const ModelConfiguration.inMemory(),
        );
        final noActionContext = ModelContext(noActionContainer);

        final trip = Trip(
          id: 'trip-noaction',
          name: 'NoAction Trip',
          destination: 'W',
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 2),
        );
        noActionContext.insert(trip);
        await noActionContext.save();
        noActionContext.insert(BucketListItem(
            id: 'bli-na1', title: 'Orphan Item', trip: trip));
        await noActionContext.save();

        noActionContext.delete(trip);
        await noActionContext.save();

        // Trip is gone.
        final trips = await noActionContext.fetch(Query<Trip>());
        expect(trips, isEmpty);

        // BucketListItem still exists with stale FK (z_pk integer).
        final items = await noActionContext.fetch(Query<BucketListItem>());
        expect(items.length, equals(1));
        // Verify stale FK via raw SQL — it's an integer z_pk.
        final rows = noActionContainer.db.select(
          "SELECT trip_id FROM bucket_list_item WHERE id = 'bli-na1'",
        );
        expect(rows.first['trip_id'], isA<int>());

        noActionContainer.close();
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Task 5.6: One-to-one optional (LivingAccommodation? with null FK)
  // ---------------------------------------------------------------------------
  group('One-to-one optional', () {
    test('LivingAccommodation with null trip stores NULL FK', () async {
      context.insert(LivingAccommodation(
        id: 'acc-orphan',
        address: '456 Elm St',
        trip: null,
      ));
      await context.save();

      // Verify FK column is NULL in SQLite.
      final rows = container.db.select(
        "SELECT trip_id FROM living_accommodation WHERE id = 'acc-orphan'",
      );
      expect(rows.first['trip_id'], isNull);
    });

    test('LivingAccommodation with trip stores z_pk integer FK', () async {
      final trip = Trip(
        id: 'trip-opt',
        name: 'Optional Trip',
        destination: 'W',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      context.insert(trip);
      await context.save();
      context.insert(LivingAccommodation(
        id: 'acc-linked',
        address: '789 Oak Ave',
        trip: trip,
      ));
      await context.save();

      final rows = container.db.select(
        "SELECT trip_id FROM living_accommodation WHERE id = 'acc-linked'",
      );
      // FK should be Trip's z_pk integer, not a UUID string.
      expect(rows.first['trip_id'], isA<int>());
      expect(rows.first['trip_id'], equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Relationship fetching — fetchRelated
  // ---------------------------------------------------------------------------
  group('fetchRelated', () {
    test('returns all BucketListItems related to a Trip', () async {
      final trip = Trip(
        id: 'trip-fetch',
        name: 'Fetch Trip',
        destination: 'A',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      context.insert(trip);
      await context.save();
      final trip2 = Trip(
        id: 'other-trip',
        name: 'Other',
        destination: 'B',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      context.insert(trip2);
      await context.save();
      context.insert(BucketListItem(
          id: 'bli-f1', title: 'Item 1', trip: trip));
      context.insert(BucketListItem(
          id: 'bli-f2', title: 'Item 2', trip: trip));
      context.insert(BucketListItem(
          id: 'bli-other', title: 'Other Item', trip: trip2));
      await context.save();

      final items = await context.fetchRelated<BucketListItem>(
          trip, 'bucketList');
      expect(items.length, equals(2));
      expect(items.map((i) => i.id).toSet(), equals({'bli-f1', 'bli-f2'}));
    });

    test('returns single LivingAccommodation related to a Trip', () async {
      final trip = Trip(
        id: 'trip-acc',
        name: 'Acc Trip',
        destination: 'B',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      context.insert(trip);
      await context.save();
      context.insert(LivingAccommodation(
          id: 'acc-f1', address: '10 Main St', trip: trip));
      await context.save();

      final accs = await context.fetchRelated<LivingAccommodation>(
          trip, 'accommodation');
      expect(accs.length, equals(1));
      expect(accs.first.id, equals('acc-f1'));
    });

    test('returns empty list when no children exist', () async {
      final trip = Trip(
        id: 'trip-empty',
        name: 'Empty Trip',
        destination: 'C',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      context.insert(trip);
      await context.save();

      final items = await context.fetchRelated<BucketListItem>(
          trip, 'bucketList');
      expect(items, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Edge cases
  // ---------------------------------------------------------------------------
  group('Edge cases', () {
    test('nested cascade: Trip → BucketListItem → SubItem all deleted',
        () async {
      final nestedContainer = await ModelContainer.create(
        schema: Schema([
          TripDescriptor(),
          BucketListItemDescriptor(),
          SubItemDescriptor(),
        ]),
        configuration: const ModelConfiguration.inMemory(),
      );
      final ctx = ModelContext(nestedContainer);

      final trip = Trip(
        id: 'trip-nested',
        name: 'Nested',
        destination: 'D',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      ctx.insert(trip);
      await ctx.save();
      final bli = BucketListItem(
          id: 'bli-n1', title: 'Parent Item', trip: trip);
      ctx.insert(bli);
      await ctx.save();
      ctx.insert(SubItem(
          id: 'sub-1', note: 'Sub note', bucketListItem: bli));
      await ctx.save();

      ctx.delete(trip);
      await ctx.save();

      final items = await ctx.fetch(Query<BucketListItem>());
      final subItems = await ctx.fetch(Query<SubItem>());
      expect(items, isEmpty);
      expect(subItems, isEmpty);

      nestedContainer.close();
    });

    test('delete succeeds when relationship target was already deleted (noAction)',
        () async {
      // Bug: _resolveRelationshipFks is called for delete operations,
      // causing StateError when the related parent row no longer exists.
      // Delete only needs map['id'], FK resolution is unnecessary.
      final noActionContainer = await ModelContainer.create(
        schema: Schema([
          TripDescriptor(),
          NoActionBucketListItemDescriptor(),
        ]),
        configuration: const ModelConfiguration.inMemory(),
      );
      final ctx = ModelContext(noActionContainer);

      final trip = Trip(
        id: 'trip-del-orphan',
        name: 'Delete Orphan Trip',
        destination: 'X',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      ctx.insert(trip);
      await ctx.save();

      final item = BucketListItem(
        id: 'bli-del-orphan',
        title: 'Orphan',
        trip: trip,
      );
      ctx.insert(item);
      await ctx.save();

      // Delete parent first (noAction leaves orphan).
      ctx.delete(trip);
      await ctx.save();

      // Now delete the orphan child whose trip reference points to
      // a row that no longer exists. This should NOT throw.
      ctx.delete(item);
      await ctx.save();

      final items = await ctx.fetch(Query<BucketListItem>());
      expect(items, isEmpty);

      noActionContainer.close();
    });

    test('fetch-modify-save preserves FK when relationship field is not hydrated',
        () async {
      // Bug: fromMap() does not populate relationship fields, so fetched
      // objects have trip == null. Re-saving writes null into the FK column,
      // silently destroying the relationship.
      final trip = Trip(
        id: 'trip-roundtrip',
        name: 'Roundtrip Trip',
        destination: 'R',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      context.insert(trip);
      await context.save();

      final item = BucketListItem(
        id: 'bli-roundtrip',
        title: 'Original Title',
        trip: trip,
      );
      context.insert(item);
      await context.save();

      // Verify FK is set initially.
      var rows = container.db.select(
        "SELECT trip_id FROM bucket_list_item WHERE id = 'bli-roundtrip'",
      );
      expect(rows.first['trip_id'], isA<int>());
      expect(rows.first['trip_id'], equals(1));

      // Fetch the item (fromMap does not hydrate trip field).
      final fetched = await context.fetchOne<BucketListItem>(id: 'bli-roundtrip');
      expect(fetched, isNotNull);

      // Modify an unrelated field and re-save.
      fetched!.title = 'Updated Title';
      context.insert(fetched); // upsert
      await context.save();

      // FK must still be intact — not nullified.
      rows = container.db.select(
        "SELECT trip_id FROM bucket_list_item WHERE id = 'bli-roundtrip'",
      );
      expect(rows.first['trip_id'], isA<int>());
      expect(rows.first['trip_id'], equals(1));
    });

    test('deleting a model with no relationships proceeds normally', () async {
      // Photo has no relationships — just a plain model.
      final photoContainer = await ModelContainer.create(
        schema: Schema([PhotoDescriptor()]),
        configuration: const ModelConfiguration.inMemory(),
      );
      final ctx = ModelContext(photoContainer);

      final photo = Photo(id: 'p1', title: 'Sunset');
      ctx.insert(photo);
      await ctx.save();

      ctx.delete(photo);
      await ctx.save();

      final photos = await ctx.fetch(Query<Photo>());
      expect(photos, isEmpty);

      photoContainer.close();
    });

    test('deny rule prevents delete and allows transaction rollback', () async {
      final denyContainer = await ModelContainer.create(
        schema: Schema([
          TripDescriptor(),
          DenyBucketListItemDescriptor(),
        ]),
        configuration: const ModelConfiguration.inMemory(),
      );
      final ctx = ModelContext(denyContainer);

      final trip = Trip(
        id: 'trip-deny-txn',
        name: 'Deny Txn Trip',
        destination: 'E',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      ctx.insert(trip);
      await ctx.save();
      ctx.insert(BucketListItem(
          id: 'bli-dt1', title: 'Block', trip: trip));
      await ctx.save();

      // Deny should throw before any SQL executes.
      ctx.delete(trip);
      expect(() async => await ctx.save(), throwsStateError);

      // Trip and item should still exist after the failed save.
      final trips = await ctx.fetch(Query<Trip>());
      final items = await ctx.fetch(Query<BucketListItem>());
      expect(trips.length, equals(1));
      expect(items.length, equals(1));

      denyContainer.close();
    });
  });
}
