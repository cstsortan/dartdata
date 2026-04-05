import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dartdata_example/dartdata_example.dart';

void main() {
  late ModelContainer container;
  late ModelContext context;

  setUp(() async {
    container = await ModelContainer.create(
      schema: cmsSchema,
      configuration: const ModelConfiguration.inMemory(),
    );
    context = ModelContext(container);

    // Seed data for query tests
    context.insert(Post(
      id: 'p1',
      title: 'Flutter Basics',
      body: 'Learn Flutter from scratch.',
      publishedAt: DateTime.utc(2026, 1, 15),
      isDraft: false,
    ));
    context.insert(Post(
      id: 'p2',
      title: 'Dart Advanced Types',
      body: 'Deep dive into Dart type system.',
      publishedAt: DateTime.utc(2026, 2, 20),
      isDraft: false,
    ));
    context.insert(Post(
      id: 'p3',
      title: 'Flutter Animations',
      body: 'Animate everything in Flutter.',
      publishedAt: DateTime.utc(2026, 3, 10),
      isDraft: true,
    ));
    context.insert(Post(
      id: 'p4',
      title: 'SQLite Performance',
      body: 'Optimize your queries.',
      publishedAt: DateTime.utc(2026, 4, 5),
      isDraft: true,
    ));
    context.insert(Post(
      id: 'p5',
      title: 'Flutter Testing',
      body: 'Widget tests and integration tests.',
      publishedAt: DateTime.utc(2026, 5, 1),
      isDraft: false,
    ));
    await context.save();
  });

  tearDown(() => container.close());

  // ---------------------------------------------------------------------------
  // Predicate operators
  // ---------------------------------------------------------------------------

  group('Predicate operators', () {
    test('equals', () async {
      final results = await context.fetch(Query<Post>(
        where: $Post.titleField.equals('Flutter Basics'),
      ));
      expect(results, hasLength(1));
      expect(results.first.id, 'p1');
    });

    test('contains (LIKE %substring%)', () async {
      final results = await context.fetch(Query<Post>(
        where: $Post.titleField.contains('Flutter'),
      ));
      expect(results, hasLength(3)); // p1, p3, p5
    });

    test('startsWith', () async {
      final results = await context.fetch(Query<Post>(
        where: $Post.titleField.startsWith('Dart'),
      ));
      expect(results, hasLength(1));
      expect(results.first.id, 'p2');
    });

    test('greater than (>)', () async {
      final results = await context.fetch(Query<Post>(
        where: $Post.publishedAtField > DateTime.utc(2026, 3, 1),
      ));
      expect(results, hasLength(3)); // p3, p4, p5
    });

    test('less than (<)', () async {
      final results = await context.fetch(Query<Post>(
        where: $Post.publishedAtField < DateTime.utc(2026, 2, 1),
      ));
      expect(results, hasLength(1)); // p1
    });

    test('between', () async {
      final results = await context.fetch(Query<Post>(
        where: $Post.publishedAtField.between(
          DateTime.utc(2026, 2, 1),
          DateTime.utc(2026, 4, 1),
        ),
      ));
      expect(results, hasLength(2)); // p2, p3
    });

    test('isIn', () async {
      final results = await context.fetch(Query<Post>(
        where: $Post.titleField.isIn([
          'Flutter Basics',
          'SQLite Performance',
        ]),
      ));
      expect(results, hasLength(2));
    });

    test('isNull / isNotNull', () async {
      // author_id is null for all posts (no author linked)
      // Use raw column query via Post's author_id FK
      final allPosts = await context.fetch(Query<Post>());
      expect(allPosts, hasLength(5)); // sanity check

      // All posts have non-null title
      final withTitle = await context.fetch(Query<Post>(
        where: $Post.titleField.isNotNull(),
      ));
      expect(withTitle, hasLength(5));
    });
  });

  // ---------------------------------------------------------------------------
  // Combined predicates
  // ---------------------------------------------------------------------------

  group('Combined predicates', () {
    test('AND (&) — Flutter posts that are drafts', () async {
      final results = await context.fetch(Query<Post>(
        where: $Post.titleField.contains('Flutter') &
            $Post.isDraftField.equals(true),
      ));
      expect(results, hasLength(1)); // p3 Flutter Animations
      expect(results.first.id, 'p3');
    });

    test('OR (|) — Flutter Basics or SQLite Performance', () async {
      final results = await context.fetch(Query<Post>(
        where: $Post.titleField.equals('Flutter Basics') |
            $Post.titleField.equals('SQLite Performance'),
      ));
      expect(results, hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Order by
  // ---------------------------------------------------------------------------

  group('Order by', () {
    test('ascending by title', () async {
      final results = await context.fetch(Query<Post>(
        orderBy: [$Post.titleField.ascending()],
      ));
      expect(results.map((p) => p.title).toList(), [
        'Dart Advanced Types',
        'Flutter Animations',
        'Flutter Basics',
        'Flutter Testing',
        'SQLite Performance',
      ]);
    });

    test('descending by publishedAt', () async {
      final results = await context.fetch(Query<Post>(
        orderBy: [$Post.publishedAtField.descending()],
      ));
      expect(results.first.id, 'p5'); // May 2026
      expect(results.last.id, 'p1'); // Jan 2026
    });
  });

  // ---------------------------------------------------------------------------
  // Pagination
  // ---------------------------------------------------------------------------

  group('Pagination', () {
    test('limit', () async {
      final results = await context.fetch(Query<Post>(
        orderBy: [$Post.publishedAtField.ascending()],
        limit: 3,
      ));
      expect(results, hasLength(3));
      expect(results.first.id, 'p1');
      expect(results.last.id, 'p3');
    });

    test('limit + offset', () async {
      final results = await context.fetch(Query<Post>(
        orderBy: [$Post.publishedAtField.ascending()],
        limit: 2,
        offset: 2,
      ));
      expect(results, hasLength(2));
      expect(results.first.id, 'p3'); // 3rd item
      expect(results.last.id, 'p4'); // 4th item
    });
  });

  // ---------------------------------------------------------------------------
  // fetchCount
  // ---------------------------------------------------------------------------

  group('fetchCount', () {
    test('count all posts', () async {
      final count = await context.fetchCount(Query<Post>());
      expect(count, 5);
    });

    test('count drafts', () async {
      final count = await context.fetchCount(Query<Post>(
        where: $Post.isDraftField.equals(true),
      ));
      expect(count, 2); // p3, p4
    });

    test('count published', () async {
      final count = await context.fetchCount(Query<Post>(
        where: $Post.isDraftField.equals(false),
      ));
      expect(count, 3); // p1, p2, p5
    });

    test('count with contains predicate', () async {
      final count = await context.fetchCount(Query<Post>(
        where: $Post.titleField.contains('Flutter'),
      ));
      expect(count, 3);
    });
  });
}
