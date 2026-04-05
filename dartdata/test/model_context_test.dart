import 'dart:async';

import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_models.dart';

void main() {
  late ModelContainer container;
  late ModelContext context;

  setUp(() async {
    container = await ModelContainer.create(
      schema: Schema([TripDescriptor(), PhotoDescriptor()]),
      configuration: const ModelConfiguration.inMemory(),
    );
    context = ModelContext(container);
  });

  tearDown(() => container.close());

  // ---------------------------------------------------------------------------
  // Task 4.1: insert + save + fetch round-trip
  // ---------------------------------------------------------------------------
  group('ModelContext — insert and fetch round-trip', () {
    test('insert + save + fetch returns inserted object with correct fields',
        () async {
      final trip = Trip(
        id: 'abc-123',
        name: 'Grand Tour',
        destination: 'Europe',
        startDate: DateTime.utc(2026, 6, 1),
        endDate: DateTime.utc(2026, 8, 31),
      );

      context.insert(trip);
      await context.save();

      final results = await context.fetch(Query<Trip>());
      expect(results.length, equals(1));
      expect(results.first.id, equals('abc-123'));
      expect(results.first.name, equals('Grand Tour'));
      expect(results.first.destination, equals('Europe'));
      expect(results.first.startDate, equals(DateTime.utc(2026, 6, 1)));
      expect(results.first.endDate, equals(DateTime.utc(2026, 8, 31)));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.2: fetch with no predicate returns all rows
  // ---------------------------------------------------------------------------
  group('ModelContext — fetch all', () {
    test('fetch with no predicate returns all rows', () async {
      context.insert(Trip(
          id: '1',
          name: 'Trip A',
          destination: 'Paris',
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 10)));
      context.insert(Trip(
          id: '2',
          name: 'Trip B',
          destination: 'Rome',
          startDate: DateTime.utc(2026, 2, 1),
          endDate: DateTime.utc(2026, 2, 10)));
      context.insert(Trip(
          id: '3',
          name: 'Trip C',
          destination: 'Tokyo',
          startDate: DateTime.utc(2026, 3, 1),
          endDate: DateTime.utc(2026, 3, 10)));
      await context.save();

      final results = await context.fetch(Query<Trip>());
      expect(results.length, equals(3));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.3: fetch with each QueryField operator
  // ---------------------------------------------------------------------------
  group('ModelContext — QueryField operator filtering', () {
    setUp(() async {
      final cities = ['Paris', 'Rome', 'Tokyo', 'Berlin', 'Madrid'];
      for (var i = 0; i < cities.length; i++) {
        context.insert(Trip(
          id: '$i',
          name: 'Trip to ${cities[i]}',
          destination: cities[i],
          startDate: DateTime.utc(2026, i + 1, 1),
          endDate: DateTime.utc(2026, i + 1, 28),
        ));
      }
      await context.save();
    });

    test('equals filters to matching row', () async {
      final results = await context.fetch(
        Query<Trip>(where: $Trip.destination.equals('Paris')),
      );
      expect(results.length, equals(1));
      expect(results.first.destination, equals('Paris'));
    });

    test('notEquals excludes matching row', () async {
      final results = await context.fetch(
        Query<Trip>(where: $Trip.destination.notEquals('Paris')),
      );
      expect(results.length, equals(4));
      expect(results.map((t) => t.destination), isNot(contains('Paris')));
    });

    test('> filters by greater-than on DateTime', () async {
      final cutoff = DateTime.utc(2026, 3, 1);
      final results = await context.fetch(
        Query<Trip>(where: $Trip.startDate > cutoff),
      );
      // April (Berlin) and May (Madrid)
      expect(results.length, equals(2));
    });

    test('>= filters by greater-than-or-equal on DateTime', () async {
      final cutoff = DateTime.utc(2026, 3, 1);
      final results = await context.fetch(
        Query<Trip>(where: $Trip.startDate >= cutoff),
      );
      // March (Tokyo), April (Berlin), May (Madrid)
      expect(results.length, equals(3));
    });

    test('< filters by less-than on DateTime', () async {
      final cutoff = DateTime.utc(2026, 3, 1);
      final results = await context.fetch(
        Query<Trip>(where: $Trip.startDate < cutoff),
      );
      // January (Paris), February (Rome)
      expect(results.length, equals(2));
    });

    test('<= filters by less-than-or-equal on DateTime', () async {
      final cutoff = DateTime.utc(2026, 3, 1);
      final results = await context.fetch(
        Query<Trip>(where: $Trip.startDate <= cutoff),
      );
      // January (Paris), February (Rome), March (Tokyo)
      expect(results.length, equals(3));
    });

    test('isIn filters to matching subset', () async {
      final results = await context.fetch(
        Query<Trip>(where: $Trip.destination.isIn(['Paris', 'Tokyo'])),
      );
      expect(results.length, equals(2));
      expect(
        results.map((t) => t.destination).toSet(),
        equals({'Paris', 'Tokyo'}),
      );
    });

    test('contains filters with LIKE wildcard match', () async {
      final results = await context.fetch(
        Query<Trip>(where: $Trip.destination.contains('ar')),
      );
      // Only Paris contains "ar"
      expect(results.length, equals(1));
      expect(results.first.destination, equals('Paris'));
    });

    test('startsWith filters with prefix match', () async {
      final results = await context.fetch(
        Query<Trip>(where: $Trip.destination.startsWith('To')),
      );
      expect(results.length, equals(1));
      expect(results.first.destination, equals('Tokyo'));
    });

    test('between filters inclusive range on DateTime', () async {
      final low = DateTime.utc(2026, 2, 1);
      final high = DateTime.utc(2026, 4, 1);
      final results = await context.fetch(
        Query<Trip>(where: $Trip.startDate.between(low, high)),
      );
      // February (Rome), March (Tokyo), April (Berlin)
      expect(results.length, equals(3));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.4: fetch with combined predicates (AND, OR, NOT)
  // ---------------------------------------------------------------------------
  group('ModelContext — combined predicates', () {
    setUp(() async {
      for (final dest in ['Paris', 'Rome', 'Tokyo']) {
        context.insert(Trip(
          id: dest,
          name: 'Trip to $dest',
          destination: dest,
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 10),
        ));
      }
      await context.save();
    });

    test('AND predicate returns intersection', () async {
      final results = await context.fetch(Query<Trip>(
        where: $Trip.destination.equals('Paris') &
            $Trip.name.startsWith('Trip'),
      ));
      expect(results.length, equals(1));
      expect(results.first.destination, equals('Paris'));
    });

    test('OR predicate returns union', () async {
      final results = await context.fetch(Query<Trip>(
        where: $Trip.destination.equals('Paris') |
            $Trip.destination.equals('Rome'),
      ));
      expect(results.length, equals(2));
    });

    test('NOT predicate excludes matching rows', () async {
      final results = await context.fetch(Query<Trip>(
        where: -$Trip.destination.equals('Paris'),
      ));
      expect(results.length, equals(2));
      expect(results.map((t) => t.destination), isNot(contains('Paris')));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.5: fetch with orderBy
  // ---------------------------------------------------------------------------
  group('ModelContext — orderBy', () {
    setUp(() async {
      context.insert(Trip(
          id: 'c', name: 'Charlie', destination: 'Tokyo',
          startDate: DateTime.utc(2026, 3, 1), endDate: DateTime.utc(2026, 3, 10)));
      context.insert(Trip(
          id: 'a', name: 'Alpha', destination: 'Paris',
          startDate: DateTime.utc(2026, 1, 1), endDate: DateTime.utc(2026, 1, 10)));
      context.insert(Trip(
          id: 'b', name: 'Bravo', destination: 'Rome',
          startDate: DateTime.utc(2026, 2, 1), endDate: DateTime.utc(2026, 2, 10)));
      await context.save();
    });

    test('ascending order by name', () async {
      final results = await context.fetch(
        Query<Trip>(orderBy: [$Trip.name.ascending()]),
      );
      expect(results.map((t) => t.name).toList(), equals(['Alpha', 'Bravo', 'Charlie']));
    });

    test('descending order by name', () async {
      final results = await context.fetch(
        Query<Trip>(orderBy: [$Trip.name.descending()]),
      );
      expect(results.map((t) => t.name).toList(), equals(['Charlie', 'Bravo', 'Alpha']));
    });

    test('ascending order by startDate', () async {
      final results = await context.fetch(
        Query<Trip>(orderBy: [$Trip.startDate.ascending()]),
      );
      expect(results.map((t) => t.name).toList(), equals(['Alpha', 'Bravo', 'Charlie']));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.6: fetch with limit and offset
  // ---------------------------------------------------------------------------
  group('ModelContext — limit and offset', () {
    setUp(() async {
      for (var i = 0; i < 10; i++) {
        context.insert(Trip(
          id: '$i',
          name: 'Trip $i',
          destination: 'City $i',
          startDate: DateTime.utc(2026, 1, i + 1),
          endDate: DateTime.utc(2026, 1, i + 8),
        ));
      }
      await context.save();
    });

    test('limit returns correct number of results', () async {
      final results = await context.fetch(Query<Trip>(limit: 3));
      expect(results.length, equals(3));
    });

    test('offset skips leading results', () async {
      final all = await context.fetch(
        Query<Trip>(orderBy: [$Trip.startDate.ascending()]),
      );
      final page = await context.fetch(
        Query<Trip>(
          orderBy: [$Trip.startDate.ascending()],
          limit: 3,
          offset: 2,
        ),
      );
      expect(page.length, equals(3));
      expect(page.first.id, equals(all[2].id));
    });

    test('offset beyond total returns empty', () async {
      // OFFSET requires LIMIT in SQLite, so we use a large limit.
      final results = await context.fetch(
        Query<Trip>(limit: 1000, offset: 100),
      );
      expect(results, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.7: fetchOne by id
  // ---------------------------------------------------------------------------
  group('ModelContext — fetchOne', () {
    test('fetchOne returns the correct object by id', () async {
      context.insert(Trip(
        id: 'xyz',
        name: 'Solo',
        destination: 'Tokyo',
        startDate: DateTime.utc(2026, 3, 1),
        endDate: DateTime.utc(2026, 3, 14),
      ));
      await context.save();

      final trip = await context.fetchOne<Trip>(id: 'xyz');
      expect(trip, isNotNull);
      expect(trip!.name, equals('Solo'));
      expect(trip.destination, equals('Tokyo'));
    });

    test('fetchOne returns null for missing id', () async {
      final trip = await context.fetchOne<Trip>(id: 'does-not-exist');
      expect(trip, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.8: fetchCount
  // ---------------------------------------------------------------------------
  group('ModelContext — fetchCount', () {
    setUp(() async {
      for (var i = 0; i < 6; i++) {
        context.insert(Trip(
          id: '$i',
          name: 'T$i',
          destination: i.isEven ? 'Paris' : 'Rome',
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 2),
        ));
      }
      await context.save();
    });

    test('fetchCount with predicate returns filtered count', () async {
      final count = await context.fetchCount(
        Query<Trip>(where: $Trip.destination.equals('Paris')),
      );
      expect(count, equals(3)); // 0, 2, 4
    });

    test('fetchCount without predicate returns total count', () async {
      final count = await context.fetchCount(Query<Trip>());
      expect(count, equals(6));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.9: Mutate fetched object, save, re-fetch
  // ---------------------------------------------------------------------------
  group('ModelContext — update', () {
    test('mutate field, save, re-fetch shows updated value', () async {
      context.insert(Trip(
        id: 'upd-1',
        name: 'Original',
        destination: 'Paris',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 10),
      ));
      await context.save();

      // Fetch, mutate, re-insert (INSERT OR REPLACE), save.
      final trips = await context.fetch(Query<Trip>());
      final trip = trips.first;
      // Create a new Trip with modified name to simulate update via INSERT OR REPLACE.
      final updated = Trip(
        id: trip.id,
        name: 'Updated',
        destination: trip.destination,
        startDate: trip.startDate,
        endDate: trip.endDate,
      );
      context.insert(updated);
      await context.save();

      final refetched = await context.fetchOne<Trip>(id: 'upd-1');
      expect(refetched!.name, equals('Updated'));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.10: delete + save removes row
  // ---------------------------------------------------------------------------
  group('ModelContext — delete', () {
    test('delete + save removes the row; subsequent fetch returns empty',
        () async {
      final trip = Trip(
        id: 'del-me',
        name: 'Gone',
        destination: 'Nowhere',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      context.insert(trip);
      await context.save();

      context.delete(trip);
      await context.save();

      final results = await context.fetch(Query<Trip>());
      expect(results, isEmpty);
    });

    test('delete only removes the targeted row', () async {
      context.insert(Trip(
          id: '1', name: 'Keep', destination: 'A',
          startDate: DateTime.utc(2026, 1, 1), endDate: DateTime.utc(2026, 1, 2)));
      final toDelete = Trip(
          id: '2', name: 'Remove', destination: 'B',
          startDate: DateTime.utc(2026, 1, 1), endDate: DateTime.utc(2026, 1, 2));
      context.insert(toDelete);
      await context.save();

      context.delete(toDelete);
      await context.save();

      final results = await context.fetch(Query<Trip>());
      expect(results.length, equals(1));
      expect(results.first.id, equals('1'));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.11: rollback discards pending inserts
  // ---------------------------------------------------------------------------
  group('ModelContext — rollback', () {
    test('rollback discards pending inserts', () async {
      context.insert(Trip(
        id: '1',
        name: 'Phantom',
        destination: 'X',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      ));

      context.rollback();
      await context.save();

      final results = await context.fetch(Query<Trip>());
      expect(results, isEmpty);
    });

    test('rollback discards pending deletes', () async {
      final trip = Trip(
        id: '1',
        name: 'Saved',
        destination: 'Y',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      context.insert(trip);
      await context.save();

      context.delete(trip);
      context.rollback(); // undo the delete
      await context.save();

      final results = await context.fetch(Query<Trip>());
      expect(results.length, equals(1));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.12: transaction commits on success
  // ---------------------------------------------------------------------------
  group('ModelContext — transaction success', () {
    test('transaction commits all inserts on success', () async {
      await context.transaction(() async {
        context.insert(Trip(
            id: 'tx-1', name: 'TX Trip 1', destination: 'A',
            startDate: DateTime.utc(2026, 1, 1), endDate: DateTime.utc(2026, 1, 2)));
        context.insert(Trip(
            id: 'tx-2', name: 'TX Trip 2', destination: 'B',
            startDate: DateTime.utc(2026, 1, 1), endDate: DateTime.utc(2026, 1, 2)));
      });

      final results = await context.fetch(Query<Trip>());
      expect(results.length, equals(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.13: transaction rolls back on throw
  // ---------------------------------------------------------------------------
  group('ModelContext — transaction rollback', () {
    test('transaction rolls back all inserts when callback throws', () async {
      try {
        await context.transaction(() async {
          context.insert(Trip(
              id: 'tx-fail', name: 'Fail', destination: 'C',
              startDate: DateTime.utc(2026, 1, 1), endDate: DateTime.utc(2026, 1, 2)));
          throw Exception('Simulated failure');
        });
      } catch (_) {
        // expected
      }

      final results = await context.fetch(Query<Trip>());
      expect(results, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Task 4.14: context.changes stream emits after save
  // ---------------------------------------------------------------------------
  group('ModelContext — changes stream', () {
    test('changes stream emits an event after save', () async {
      final events = <ContextChangeSet>[];
      final sub = context.changes.listen(events.add);
      addTearDown(sub.cancel);

      context.insert(Trip(
        id: 'stream-1',
        name: 'Streamed',
        destination: 'Z',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      ));
      await context.save();

      // The notifier fires synchronously, so the event should be there.
      expect(events.length, equals(1));
    });

    test('changes stream does not emit when save has no pending ops', () async {
      final events = <ContextChangeSet>[];
      final sub = context.changes.listen(events.add);
      addTearDown(sub.cancel);

      await context.save(); // nothing pending
      expect(events, isEmpty);
    });

    test('changes stream emits one event per save call', () async {
      final events = <ContextChangeSet>[];
      final sub = context.changes.listen(events.add);
      addTearDown(sub.cancel);

      context.insert(Trip(
          id: 's1', name: 'A', destination: 'X',
          startDate: DateTime.utc(2026, 1, 1), endDate: DateTime.utc(2026, 1, 2)));
      await context.save();

      context.insert(Trip(
          id: 's2', name: 'B', destination: 'Y',
          startDate: DateTime.utc(2026, 1, 1), endDate: DateTime.utc(2026, 1, 2)));
      await context.save();

      expect(events.length, equals(2));
    });
  });
}
