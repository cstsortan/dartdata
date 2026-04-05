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

  group('ModelContext — insert and fetch', () {
    test('insert then fetch returns the inserted model', () async {
      final trip = Trip(
        id: 'abc-123',
        name: 'Grand Tour',
        destination: 'Europe',
        startDate: DateTime(2026, 6, 1),
        endDate: DateTime(2026, 8, 31),
      );

      context.insert(trip);
      await context.save();

      final results = await context.fetch(Query<Trip>());
      expect(results.length, equals(1));
      expect(results.first.id, equals('abc-123'));
      expect(results.first.name, equals('Grand Tour'));
    });

    test('inserting multiple models returns all of them', () async {
      context.insert(Trip(
          id: '1',
          name: 'Trip A',
          destination: 'Paris',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 10)));
      context.insert(Trip(
          id: '2',
          name: 'Trip B',
          destination: 'Rome',
          startDate: DateTime(2026, 2, 1),
          endDate: DateTime(2026, 2, 10)));

      await context.save();

      final results = await context.fetch(Query<Trip>());
      expect(results.length, equals(2));
    });

    test('fetch with predicate filters correctly', () async {
      context.insert(Trip(
          id: '1',
          name: 'Paris Trip',
          destination: 'Paris',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 10)));
      context.insert(Trip(
          id: '2',
          name: 'Rome Trip',
          destination: 'Rome',
          startDate: DateTime(2026, 2, 1),
          endDate: DateTime(2026, 2, 10)));
      await context.save();

      final results = await context.fetch(
        Query<Trip>(where: $Trip.destination.equals('Paris')),
      );

      expect(results.length, equals(1));
      expect(results.first.destination, equals('Paris'));
    });

    test('fetch with orderBy returns results in correct order', () async {
      context.insert(Trip(
          id: '2',
          name: 'B',
          destination: 'Rome',
          startDate: DateTime(2026, 2, 1),
          endDate: DateTime(2026, 2, 10)));
      context.insert(Trip(
          id: '1',
          name: 'A',
          destination: 'Paris',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 10)));
      await context.save();

      final results = await context.fetch(
        Query<Trip>(orderBy: [$Trip.name.ascending()]),
      );

      expect(results.map((t) => t.name), equals(['A', 'B']));
    });

    test('fetch with limit returns correct number of results', () async {
      for (var i = 0; i < 5; i++) {
        context.insert(Trip(
            id: '$i',
            name: 'Trip $i',
            destination: 'City $i',
            startDate: DateTime(2026, 1, i + 1),
            endDate: DateTime(2026, 1, i + 8)));
      }
      await context.save();

      final results = await context.fetch(Query<Trip>(limit: 3));
      expect(results.length, equals(3));
    });

    test('fetchOne returns model by id', () async {
      context.insert(Trip(
          id: 'xyz',
          name: 'Solo',
          destination: 'Tokyo',
          startDate: DateTime(2026, 3, 1),
          endDate: DateTime(2026, 3, 14)));
      await context.save();

      final trip = await context.fetchOne<Trip>(id: 'xyz');
      expect(trip, isNotNull);
      expect(trip!.name, equals('Solo'));
    });

    test('fetchOne returns null for unknown id', () async {
      final trip = await context.fetchOne<Trip>(id: 'does-not-exist');
      expect(trip, isNull);
    });

    test('fetchCount returns the correct count', () async {
      for (var i = 0; i < 4; i++) {
        context.insert(Trip(
            id: '$i',
            name: 'T$i',
            destination: i.isEven ? 'Paris' : 'Rome',
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 1, 2)));
      }
      await context.save();

      final count = await context.fetchCount(
        Query<Trip>(where: $Trip.destination.equals('Paris')),
      );
      expect(count, equals(2));
    });
  });

  group('ModelContext — delete', () {
    test('deleted model is no longer returned by fetch', () async {
      final trip = Trip(
          id: 'del-me',
          name: 'Gone',
          destination: 'Nowhere',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 2));
      context.insert(trip);
      await context.save();

      context.delete(trip);
      await context.save();

      final results = await context.fetch(Query<Trip>());
      expect(results, isEmpty);
    });
  });

  group('ModelContext — rollback', () {
    test('rollback discards pending inserts', () async {
      context.insert(Trip(
          id: '1',
          name: 'Phantom',
          destination: 'X',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 1, 2)));

      context.rollback();
      await context.save();

      final results = await context.fetch(Query<Trip>());
      expect(results, isEmpty);
    });
  });

  group('Predicate operators', () {
    setUp(() async {
      for (final dest in ['Paris', 'Rome', 'Tokyo']) {
        context.insert(Trip(
            id: dest,
            name: 'Trip to $dest',
            destination: dest,
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 1, 10)));
      }
      await context.save();
    });

    test('AND predicate', () async {
      final results = await context.fetch(Query<Trip>(
        where: $Trip.destination.equals('Paris') &
            $Trip.name.startsWith('Trip'),
      ));
      expect(results.length, equals(1));
    });

    test('OR predicate', () async {
      final results = await context.fetch(Query<Trip>(
        where: $Trip.destination.equals('Paris') |
            $Trip.destination.equals('Rome'),
      ));
      expect(results.length, equals(2));
    });

    test('contains predicate', () async {
      final results = await context.fetch(
        Query<Trip>(where: $Trip.name.contains('Tokyo')),
      );
      expect(results.length, equals(1));
      expect(results.first.destination, equals('Tokyo'));
    });

    test('isIn predicate', () async {
      final results = await context.fetch(
        Query<Trip>(
            where: $Trip.destination.isIn(['Paris', 'Tokyo'])),
      );
      expect(results.length, equals(2));
    });
  });
}
