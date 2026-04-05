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
      final post = Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      );
      context.insert(post);
      await context.save();

      // Insert comments with FK set via relationship object
      context.insert(Comment(id: 'c1', text: 'Nice!', createdAt: DateTime.utc(2026), post: post));
      context.insert(Comment(id: 'c2', text: 'Great!', createdAt: DateTime.utc(2026), post: post));
      await context.save();

      // Verify comments exist
      expect(await context.fetchCount(Query<Comment>()), 2);

      // Delete the post — should cascade to comments
      final fetched = (await context.fetchOne<Post>(id: 'p1'))!;
      context.delete(fetched);
      await context.save();

      expect(await context.fetchCount(Query<Post>()), 0);
      expect(await context.fetchCount(Query<Comment>()), 0);
    });

    test('deleting Post cascades to Attachments', () async {
      final post = Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      );
      context.insert(post);
      await context.save();

      context.insert(Attachment(id: 'at1', filename: 'file.txt', post: post));
      await context.save();

      expect(await context.fetchCount(Query<Attachment>()), 1);

      final fetched = (await context.fetchOne<Post>(id: 'p1'))!;
      context.delete(fetched);
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
      final post = Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      );
      context.insert(post);
      await context.save();

      // Insert a category linked to the post via relationship
      context.insert(Category(id: 'cat1', name: 'Tech', post: post));
      await context.save();

      // Verify FK is set to the post's UUID
      final before = container.db.select(
        "SELECT post_id FROM category WHERE id = 'cat1'",
      );
      expect(before.first['post_id'], 'p1');

      // Delete the post — should nullify category.post_id
      final fetched = (await context.fetchOne<Post>(id: 'p1'))!;
      context.delete(fetched);
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
  // DeleteRule.nullify — Post → Author (nullify from Post side)
  // ---------------------------------------------------------------------------

  group('DeleteRule.nullify on Post→Author', () {
    test('deleting Author nullifies author_id on Posts', () async {
      final author = Author(id: 'a1', name: 'Alice', email: 'a@test.com');
      context.insert(author);
      context.insert(Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
        author: author,
      ));
      await context.save();

      // Verify FK is set to the author's UUID
      final before = container.db.select(
        "SELECT author_id FROM post WHERE id = 'p1'",
      );
      expect(before.first['author_id'], 'a1');

      // Delete author — Post.author relationship has DeleteRule.nullify
      final fetched = (await context.fetchOne<Author>(id: 'a1'))!;
      context.delete(fetched);
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
  // Explicit junction model (PostTag with pinnedAt)
  // ---------------------------------------------------------------------------

  group('Explicit junction model PostTag', () {
    test('PostTag carries extra pinnedAt field', () async {
      final post = Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      );
      final tag = Tag(id: 't1', name: 'flutter');
      context.insert(post);
      context.insert(tag);
      await context.save();

      context.insert(PostTag(
        id: 'pt1',
        pinnedAt: DateTime.utc(2026, 6, 15),
        post: post,
        tag: tag,
      ));
      await context.save();

      final results = await context.fetch(Query<PostTag>());
      expect(results, hasLength(1));
      expect(results.first.pinnedAt, DateTime.utc(2026, 6, 15));

      // Verify FKs via raw query — should be UUID strings
      final raw = container.db.select(
        "SELECT post_id, tag_id FROM post_tag WHERE id = 'pt1'",
      );
      expect(raw.first['post_id'], 'p1');
      expect(raw.first['tag_id'], 't1');
    });

    test('deleting Post cascades to PostTag entries', () async {
      final post = Post(
        id: 'p1',
        title: 'T',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      );
      final tag = Tag(id: 't1', name: 'flutter');
      context.insert(post);
      context.insert(tag);
      await context.save();

      context.insert(PostTag(id: 'pt1', post: post, tag: tag));
      await context.save();

      expect(await context.fetchCount(Query<PostTag>()), 1);

      // Delete the post — PostTag.post has DeleteRule.cascade
      final fetched = (await context.fetchOne<Post>(id: 'p1'))!;
      context.delete(fetched);
      await context.save();

      expect(await context.fetchCount(Query<Post>()), 0);
      expect(await context.fetchCount(Query<PostTag>()), 0);
    });

    test('deleting Tag succeeds when no PostTag references it', () async {
      context.insert(Tag(id: 't1', name: 'orphan'));
      await context.save();

      final tag = (await context.fetchOne<Tag>(id: 't1'))!;
      context.delete(tag);
      await context.save(); // should not throw

      expect(await context.fetchCount(Query<Tag>()), 0);
    });
  });
}
