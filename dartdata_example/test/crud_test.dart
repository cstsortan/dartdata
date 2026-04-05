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
  });

  tearDown(() => container.close());

  // ---------------------------------------------------------------------------
  // Author CRUD
  // ---------------------------------------------------------------------------

  group('Author CRUD', () {
    test('insert and fetch round-trip', () async {
      final author = Author(
        id: 'a1',
        name: 'Alice',
        email: 'alice@example.com',
      );
      context.insert(author);
      await context.save();

      final results = await context.fetch(Query<Author>());
      expect(results, hasLength(1));
      expect(results.first.name, 'Alice');
      expect(results.first.email, 'alice@example.com');
    });

    test('fetchOne by id', () async {
      context.insert(Author(id: 'a1', name: 'Bob', email: 'bob@test.com'));
      await context.save();

      final author = await context.fetchOne<Author>(id: 'a1');
      expect(author, isNotNull);
      expect(author!.name, 'Bob');
    });

    test('update and verify z_opt increments', () async {
      context.insert(Author(id: 'a1', name: 'V1', email: 'v@test.com'));
      await context.save();

      expect(context.versionOf<Author>('a1'), 0);

      // Update by re-inserting with same id
      context.insert(Author(id: 'a1', name: 'V2', email: 'v@test.com'));
      await context.save();

      expect(context.versionOf<Author>('a1'), 1);

      final fetched = await context.fetchOne<Author>(id: 'a1');
      expect(fetched!.name, 'V2');
    });

    test('delete removes record', () async {
      final author = Author(id: 'a1', name: 'Del', email: 'del@test.com');
      context.insert(author);
      await context.save();

      context.delete(author);
      await context.save();

      final result = await context.fetchOne<Author>(id: 'a1');
      expect(result, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Post CRUD
  // ---------------------------------------------------------------------------

  group('Post CRUD', () {
    test('insert and fetch with DateTime and bool fields', () async {
      final post = Post(
        id: 'p1',
        title: 'Hello World',
        body: 'This is the body text.',
        publishedAt: DateTime.utc(2026, 3, 15),
        isDraft: false,
      );
      context.insert(post);
      await context.save();

      final results = await context.fetch(Query<Post>());
      expect(results, hasLength(1));
      expect(results.first.title, 'Hello World');
      expect(results.first.body, 'This is the body text.');
      expect(results.first.publishedAt, DateTime.utc(2026, 3, 15));
      expect(results.first.isDraft, false);
    });

    test('transient field wordCount is not persisted', () async {
      final post = Post(
        id: 'p1',
        title: 'Test',
        body: 'Body',
        publishedAt: DateTime.utc(2026, 1, 1),
        wordCount: 42,
      );
      context.insert(post);
      await context.save();

      // wordCount should default to 0 on fetch (not persisted)
      final fetched = await context.fetchOne<Post>(id: 'p1');
      expect(fetched!.wordCount, 0);
    });

    test('columnName override body_text stores correctly', () async {
      context.insert(Post(
        id: 'p1',
        title: 'T',
        body: 'Custom column body',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      await context.save();

      // Verify via raw SQL that the column is body_text
      final raw = container.db.select(
        "SELECT body_text FROM post WHERE id = 'p1'",
      );
      expect(raw.first['body_text'], 'Custom column body');
    });

    test('z_opt increments on update', () async {
      context.insert(Post(
        id: 'p1',
        title: 'V1',
        body: 'b',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      await context.save();
      expect(context.versionOf<Post>('p1'), 0);

      context.insert(Post(
        id: 'p1',
        title: 'V2',
        body: 'b',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      await context.save();
      expect(context.versionOf<Post>('p1'), 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Category CRUD
  // ---------------------------------------------------------------------------

  group('Category CRUD', () {
    test('insert and fetch', () async {
      context.insert(Category(id: 'c1', name: 'Tech'));
      await context.save();

      final results = await context.fetch(Query<Category>());
      expect(results, hasLength(1));
      expect(results.first.name, 'Tech');
    });

    test('delete', () async {
      final cat = Category(id: 'c1', name: 'Sports');
      context.insert(cat);
      await context.save();

      context.delete(cat);
      await context.save();

      expect(await context.fetchCount(Query<Category>()), 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Comment CRUD
  // ---------------------------------------------------------------------------

  group('Comment CRUD', () {
    test('insert and fetch with DateTime', () async {
      context.insert(Comment(
        id: 'cm1',
        text: 'Great post!',
        createdAt: DateTime.utc(2026, 4, 1, 12, 30),
      ));
      await context.save();

      final results = await context.fetch(Query<Comment>());
      expect(results, hasLength(1));
      expect(results.first.text, 'Great post!');
      expect(results.first.createdAt, DateTime.utc(2026, 4, 1, 12, 30));
    });
  });

  // ---------------------------------------------------------------------------
  // Tag CRUD
  // ---------------------------------------------------------------------------

  group('Tag CRUD', () {
    test('insert and fetch', () async {
      context.insert(Tag(id: 't1', name: 'flutter'));
      context.insert(Tag(id: 't2', name: 'dart'));
      await context.save();

      final results = await context.fetch(Query<Tag>());
      expect(results, hasLength(2));
    });

    test('unique constraint on name prevents duplicates', () async {
      context.insert(Tag(id: 't1', name: 'flutter'));
      await context.save();

      context.insert(Tag(id: 't2', name: 'flutter'));
      expect(() async => await context.save(), throwsA(anything));
    });
  });

  // ---------------------------------------------------------------------------
  // PostTag CRUD (explicit junction model)
  // ---------------------------------------------------------------------------

  group('PostTag CRUD', () {
    test('insert with pinnedAt DateTime?', () async {
      context.insert(PostTag(
        id: 'pt1',
        pinnedAt: DateTime.utc(2026, 5, 1),
      ));
      await context.save();

      final results = await context.fetch(Query<PostTag>());
      expect(results, hasLength(1));
      expect(results.first.pinnedAt, DateTime.utc(2026, 5, 1));
    });

    test('insert with null pinnedAt', () async {
      context.insert(PostTag(id: 'pt1'));
      await context.save();

      final results = await context.fetch(Query<PostTag>());
      expect(results, hasLength(1));
      expect(results.first.pinnedAt, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Attachment CRUD
  // ---------------------------------------------------------------------------

  group('Attachment CRUD', () {
    test('insert and fetch', () async {
      context.insert(Attachment(id: 'at1', filename: 'photo.jpg'));
      await context.save();

      final results = await context.fetch(Query<Attachment>());
      expect(results, hasLength(1));
      expect(results.first.filename, 'photo.jpg');
    });
  });

  // ---------------------------------------------------------------------------
  // Cross-cutting
  // ---------------------------------------------------------------------------

  group('Cross-cutting', () {
    test('multiple models can be inserted in one save', () async {
      context.insert(Author(id: 'a1', name: 'X', email: 'x@test.com'));
      context.insert(Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      context.insert(Tag(id: 't1', name: 'misc'));
      await context.save();

      expect(await context.fetchCount(Query<Author>()), 1);
      expect(await context.fetchCount(Query<Post>()), 1);
      expect(await context.fetchCount(Query<Tag>()), 1);
    });

    test('rollback discards pending inserts', () async {
      context.insert(Author(id: 'a1', name: 'Ghost', email: 'g@test.com'));
      context.rollback();
      await context.save();

      expect(await context.fetchCount(Query<Author>()), 0);
    });
  });
}
