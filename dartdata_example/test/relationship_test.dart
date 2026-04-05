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
  // DeleteRule.cascade — deleting Post removes Comments and Attachments
  // ---------------------------------------------------------------------------

  group('DeleteRule.cascade', () {
    test('deleting Post cascades to Comments', () async {
      // Insert Post then Comments referencing it via FK
      context.insert(Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      await context.save();

      // Insert comments with FK pointing to post (text ID)
      container.db.execute(
        "INSERT INTO comment (id, text, created_at, post_id, z_opt) "
        "VALUES ('c1', 'Nice!', 0, 'p1', 0)",
      );
      container.db.execute(
        "INSERT INTO comment (id, text, created_at, post_id, z_opt) "
        "VALUES ('c2', 'Great!', 0, 'p1', 0)",
      );

      // Verify comments exist
      expect(await context.fetchCount(Query<Comment>()), 2);

      // Delete the post — should cascade to comments
      final post = (await context.fetchOne<Post>(id: 'p1'))!;
      context.delete(post);
      await context.save();

      expect(await context.fetchCount(Query<Post>()), 0);
      expect(await context.fetchCount(Query<Comment>()), 0);
    });

    test('deleting Post cascades to Attachments', () async {
      context.insert(Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      await context.save();

      container.db.execute(
        "INSERT INTO attachment (id, filename, post_id, z_opt) "
        "VALUES ('at1', 'file.txt', 'p1', 0)",
      );

      expect(await context.fetchCount(Query<Attachment>()), 1);

      final post = (await context.fetchOne<Post>(id: 'p1'))!;
      context.delete(post);
      await context.save();

      expect(await context.fetchCount(Query<Post>()), 0);
      expect(await context.fetchCount(Query<Attachment>()), 0);
    });
  });

  // ---------------------------------------------------------------------------
  // DeleteRule.nullify — deleting Post nullifies FK on Category
  // ---------------------------------------------------------------------------

  group('DeleteRule.nullify', () {
    test('deleting Post nullifies category.post_id FK', () async {
      // Insert a post
      context.insert(Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      await context.save();

      // Insert a category and link it to the post via FK
      context.insert(Category(id: 'cat1', name: 'Tech'));
      await context.save();

      // Manually set the FK on category table
      container.db.execute(
        "UPDATE category SET post_id = 'p1' WHERE id = 'cat1'",
      );

      // Verify FK is set
      final before = container.db.select(
        "SELECT post_id FROM category WHERE id = 'cat1'",
      );
      expect(before.first['post_id'], 'p1');

      // Delete the post — should nullify category.post_id
      final post = (await context.fetchOne<Post>(id: 'p1'))!;
      context.delete(post);
      await context.save();

      // Category still exists but FK is null
      expect(await context.fetchCount(Query<Category>()), 1);
      final after = container.db.select(
        "SELECT post_id FROM category WHERE id = 'cat1'",
      );
      expect(after.first['post_id'], isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // DeleteRule.deny — deleting Tag blocked when Posts reference it via junction
  // ---------------------------------------------------------------------------

  group('DeleteRule.deny', () {
    test('deleting Tag throws when Posts exist in junction table', () async {
      context.insert(Tag(id: 't1', name: 'flutter'));
      context.insert(Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      await context.save();

      // Look up z_pk values for junction table (uses INTEGER references)
      final postZpk = container.db.select(
        "SELECT z_pk FROM post WHERE id = 'p1'",
      ).first['z_pk'] as int;
      final tagZpk = container.db.select(
        "SELECT z_pk FROM tag WHERE id = 't1'",
      ).first['z_pk'] as int;

      // Link them via junction table using z_pk integers
      container.db.execute(
        'INSERT INTO _post_tag (post_id, tag_id) VALUES (?, ?)',
        [postZpk, tagZpk],
      );

      // Attempt to delete tag — SQLite FK constraint should block it
      final tag = (await context.fetchOne<Tag>(id: 't1'))!;
      context.delete(tag);
      expect(() async => await context.save(), throwsA(isA<Exception>()));
    });

    test('deleting Tag succeeds when no Posts reference it', () async {
      context.insert(Tag(id: 't1', name: 'orphan'));
      await context.save();

      final tag = (await context.fetchOne<Tag>(id: 't1'))!;
      context.delete(tag);
      await context.save(); // should not throw

      expect(await context.fetchCount(Query<Tag>()), 0);
    });
  });

  // ---------------------------------------------------------------------------
  // DeleteRule.nullify — Post → Author (nullify from Post side)
  // ---------------------------------------------------------------------------

  group('DeleteRule.nullify on Post→Author', () {
    test('deleting Author nullifies author_id on Posts', () async {
      context.insert(Author(id: 'a1', name: 'Alice', email: 'a@test.com'));
      context.insert(Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      await context.save();

      // Link post to author via FK
      container.db.execute(
        "UPDATE post SET author_id = 'a1' WHERE id = 'p1'",
      );

      final before = container.db.select(
        "SELECT author_id FROM post WHERE id = 'p1'",
      );
      expect(before.first['author_id'], 'a1');

      // Delete author — Post.author relationship has DeleteRule.nullify
      final author = (await context.fetchOne<Author>(id: 'a1'))!;
      context.delete(author);
      await context.save();

      // Post still exists, author_id should be nullified
      expect(await context.fetchCount(Query<Post>()), 1);
      final after = container.db.select(
        "SELECT author_id FROM post WHERE id = 'p1'",
      );
      expect(after.first['author_id'], isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Many-to-many auto junction table (Post ↔ Tag)
  // ---------------------------------------------------------------------------

  group('Many-to-many auto junction table', () {
    test('junction table _post_tag links Posts and Tags', () async {
      context.insert(Post(
        id: 'p1',
        title: 'T1',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      context.insert(Post(
        id: 'p2',
        title: 'T2',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 2),
      ));
      context.insert(Tag(id: 't1', name: 'flutter'));
      context.insert(Tag(id: 't2', name: 'dart'));
      await context.save();

      // Look up z_pk values (junction table uses INTEGER FKs)
      final p1Zpk = container.db.select(
        "SELECT z_pk FROM post WHERE id = 'p1'",
      ).first['z_pk'] as int;
      final p2Zpk = container.db.select(
        "SELECT z_pk FROM post WHERE id = 'p2'",
      ).first['z_pk'] as int;
      final t1Zpk = container.db.select(
        "SELECT z_pk FROM tag WHERE id = 't1'",
      ).first['z_pk'] as int;
      final t2Zpk = container.db.select(
        "SELECT z_pk FROM tag WHERE id = 't2'",
      ).first['z_pk'] as int;

      // Link via junction table using z_pk integers
      container.db.execute(
        'INSERT INTO _post_tag (post_id, tag_id) VALUES (?, ?)',
        [p1Zpk, t1Zpk],
      );
      container.db.execute(
        'INSERT INTO _post_tag (post_id, tag_id) VALUES (?, ?)',
        [p1Zpk, t2Zpk],
      );
      container.db.execute(
        'INSERT INTO _post_tag (post_id, tag_id) VALUES (?, ?)',
        [p2Zpk, t1Zpk],
      );

      // Verify junction rows
      final rows = container.db.select('SELECT * FROM _post_tag');
      expect(rows, hasLength(3));

      // Query tags for p1 via raw SQL join on z_pk
      final tagsForP1 = container.db.select(
        'SELECT t.* FROM tag t '
        'INNER JOIN _post_tag jt ON jt.tag_id = t.z_pk '
        'WHERE jt.post_id = ?',
        [p1Zpk],
      );
      expect(tagsForP1, hasLength(2));
    });
  });

  // ---------------------------------------------------------------------------
  // Explicit junction model (PostTag with pinnedAt)
  // ---------------------------------------------------------------------------

  group('Explicit junction model PostTag', () {
    test('PostTag carries extra pinnedAt field', () async {
      context.insert(Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      context.insert(Tag(id: 't1', name: 'flutter'));
      await context.save();

      context.insert(PostTag(
        id: 'pt1',
        pinnedAt: DateTime.utc(2026, 6, 15),
      ));
      await context.save();

      // Link to post and tag via raw FK update (text IDs, since these are
      // regular FK columns on the explicit junction model)
      container.db.execute(
        "UPDATE post_tag SET post_id = 'p1', tag_id = 't1' WHERE id = 'pt1'",
      );

      final results = await context.fetch(Query<PostTag>());
      expect(results, hasLength(1));
      expect(results.first.pinnedAt, DateTime.utc(2026, 6, 15));

      // Verify FKs via raw query
      final raw = container.db.select(
        "SELECT post_id, tag_id FROM post_tag WHERE id = 'pt1'",
      );
      expect(raw.first['post_id'], 'p1');
      expect(raw.first['tag_id'], 't1');
    });
  });
}
