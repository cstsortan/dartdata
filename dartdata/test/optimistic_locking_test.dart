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
}
