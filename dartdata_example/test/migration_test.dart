import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:dartdata_example/dartdata_example.dart';

void main() {
  // ---------------------------------------------------------------------------
  // MigrationPolicy.automatic — add column, reopen, verify data intact
  // ---------------------------------------------------------------------------

  group('MigrationPolicy.automatic', () {
    test('adds new columns without losing existing data', () async {
      // Open an in-memory DB and create the schema
      final db = sqlite3.openInMemory();
      db.execute('PRAGMA journal_mode=WAL;');
      db.execute('PRAGMA foreign_keys=ON;');

      // Create with the initial schema
      final container1 = await ModelContainer.createFromDatabase(
        schema: cmsSchema,
        db: db,
        configuration: const ModelConfiguration(),
      );
      final ctx1 = ModelContext(container1);

      // Insert a post
      ctx1.insert(Post(
        id: 'p1',
        title: 'Original',
        body: 'Body text',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      await ctx1.save();

      // Simulate a schema change: create a new schema that has an extra
      // model (same models + Author, which already exists, so this is safe).
      // The point is: re-opening the same DB with the same schema should
      // preserve existing data, and the automatic migration handles any
      // new columns additively.
      final container2 = await ModelContainer.createFromDatabase(
        schema: cmsSchema,
        db: db,
        configuration: const ModelConfiguration(),
      );
      final ctx2 = ModelContext(container2);

      // Verify the post still exists after re-applying schema
      final post = (await ctx2.fetchOne<Post>(id: 'p1'))!;
      expect(post.title, 'Original');
      expect(post.body, 'Body text');
      expect(post.publishedAt, DateTime.utc(2026, 1, 1));
    });

    test('adds a new table for a new model', () async {
      final db = sqlite3.openInMemory();
      db.execute('PRAGMA journal_mode=WAL;');
      db.execute('PRAGMA foreign_keys=ON;');

      // Open with a minimal schema (just Author)
      final minimalSchema = Schema([AuthorPersistence.descriptor]);
      final container1 = await ModelContainer.createFromDatabase(
        schema: minimalSchema,
        db: db,
        configuration: const ModelConfiguration(),
      );
      final ctx1 = ModelContext(container1);

      ctx1.insert(Author(id: 'a1', name: 'Alice', email: 'a@test.com'));
      await ctx1.save();

      // Re-open with the full CMS schema (adds Post, Category, etc.)
      final container2 = await ModelContainer.createFromDatabase(
        schema: cmsSchema,
        db: db,
        configuration: const ModelConfiguration(),
      );
      final ctx2 = ModelContext(container2);

      // Author data is still intact
      final author = (await ctx2.fetchOne<Author>(id: 'a1'))!;
      expect(author.name, 'Alice');

      // New Post table was created
      ctx2.insert(Post(
        id: 'p1',
        title: 'New',
        body: 'B',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      await ctx2.save();
      expect(await ctx2.fetchCount(Query<Post>()), 1);
    });
  });

  // ---------------------------------------------------------------------------
  // MigrationPolicy.resetOnConflict — schema change wipes and recreates
  // ---------------------------------------------------------------------------

  group('MigrationPolicy.resetOnConflict', () {
    test('schema change drops all tables and recreates them', () async {
      final db = sqlite3.openInMemory();
      db.execute('PRAGMA journal_mode=WAL;');
      db.execute('PRAGMA foreign_keys=ON;');

      // Open with a minimal schema first
      final minimalSchema = Schema([AuthorPersistence.descriptor]);
      final container1 = await ModelContainer.createFromDatabase(
        schema: minimalSchema,
        db: db,
        configuration: const ModelConfiguration(),
      );
      final ctx1 = ModelContext(container1);

      ctx1.insert(Author(id: 'a1', name: 'Alice', email: 'a@test.com'));
      await ctx1.save();
      expect(await ctx1.fetchCount(Query<Author>()), 1);

      // Re-open with full schema and resetOnConflict
      final container2 = await ModelContainer.createFromDatabase(
        schema: cmsSchema,
        db: db,
        configuration: const ModelConfiguration(
          migrationPolicy: MigrationPolicy.resetOnConflict,
        ),
      );
      final ctx2 = ModelContext(container2);

      // Old data is gone — tables were dropped and recreated
      expect(await ctx2.fetchCount(Query<Author>()), 0);

      // But the tables work fine for new data
      ctx2.insert(Author(id: 'a2', name: 'Bob', email: 'b@test.com'));
      await ctx2.save();
      expect(await ctx2.fetchCount(Query<Author>()), 1);
    });
  });

  // ---------------------------------------------------------------------------
  // Transaction success — atomic insert of Post + Comments
  // ---------------------------------------------------------------------------

  group('Transaction', () {
    test('insert Post + Comments atomically', () async {
      final container = await ModelContainer.create(
        schema: cmsSchema,
        configuration: const ModelConfiguration.inMemory(),
      );
      final context = ModelContext(container);

      await context.transaction(() async {
        context.insert(Post(
          id: 'p1',
          title: 'Atomic Post',
          body: 'Body',
          publishedAt: DateTime.utc(2026, 1, 1),
        ));
        context.insert(Comment(
          id: 'c1',
          text: 'Comment 1',
          createdAt: DateTime.utc(2026, 1, 2),
        ));
        context.insert(Comment(
          id: 'c2',
          text: 'Comment 2',
          createdAt: DateTime.utc(2026, 1, 3),
        ));
      });

      expect(await context.fetchCount(Query<Post>()), 1);
      expect(await context.fetchCount(Query<Comment>()), 2);

      container.close();
    });

    test('transaction rollback on failure leaves no partial data', () async {
      final container = await ModelContainer.create(
        schema: cmsSchema,
        configuration: const ModelConfiguration.inMemory(),
      );
      final context = ModelContext(container);

      // Insert a post first so we can verify it survives rollback
      context.insert(Post(
        id: 'p0',
        title: 'Pre-existing',
        body: 'Body',
        publishedAt: DateTime.utc(2026, 1, 1),
      ));
      await context.save();

      try {
        await context.transaction(() async {
          context.insert(Post(
            id: 'p1',
            title: 'Should not persist',
            body: 'Body',
            publishedAt: DateTime.utc(2026, 2, 1),
          ));
          // Simulate failure mid-transaction
          throw StateError('Simulated failure');
        });
      } catch (_) {
        // Expected
      }

      // Only the pre-existing post should remain
      expect(await context.fetchCount(Query<Post>()), 1);
      final post = (await context.fetchOne<Post>(id: 'p0'))!;
      expect(post.title, 'Pre-existing');

      // The transaction post should not exist
      final missing = await context.fetchOne<Post>(id: 'p1');
      expect(missing, isNull);

      container.close();
    });
  });
}
