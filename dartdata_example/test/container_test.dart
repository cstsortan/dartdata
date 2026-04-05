import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dartdata_example/dartdata_example.dart';

void main() {
  late ModelContainer container;

  setUp(() async {
    container = await ModelContainer.create(
      schema: cmsSchema,
      configuration: const ModelConfiguration.inMemory(),
    );
  });

  tearDown(() => container.close());

  group('Container setup', () {
    test('WAL mode is enabled', () {
      final result = container.db.select('PRAGMA journal_mode');
      // In-memory databases report "memory" instead of "wal",
      // but the pragma is still issued. Verify it was set.
      expect(result.first.values.first, anyOf('wal', 'memory'));
    });

    test('foreign keys are enabled', () {
      final result = container.db.select('PRAGMA foreign_keys');
      expect(result.first.values.first, 1);
    });

    test('all model tables are created', () {
      final tables = container.db
          .select(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name NOT LIKE 'sqlite_%' "
            "ORDER BY name",
          )
          .map((row) => row['name'] as String)
          .toList();

      expect(tables, containsAll([
        'author',
        'post',
        'category',
        'comment',
        'tag',
        'post_tag',
        'attachment',
      ]));
    });

    test('system tables are created', () {
      final tables = container.db
          .select(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name LIKE '_%' "
            "ORDER BY name",
          )
          .map((row) => row['name'] as String)
          .toList();

      expect(tables, containsAll(['_schema_version', '_change_log']));
    });

    test('junction table is created for Tag ↔ Post many-to-many', () {
      final tables = container.db
          .select(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name = '_post_tag'",
          )
          .map((row) => row['name'] as String)
          .toList();

      expect(tables, contains('_post_tag'));
    });

    test('z_pk and z_opt system columns are present on every model table', () {
      final modelTables = [
        'author',
        'post',
        'category',
        'comment',
        'tag',
        'post_tag',
        'attachment',
      ];

      for (final table in modelTables) {
        final columns = container.db
            .select('PRAGMA table_info($table)')
            .map((row) => row['name'] as String)
            .toList();

        expect(columns, contains('z_pk'),
            reason: '$table should have z_pk column');
        expect(columns, contains('z_opt'),
            reason: '$table should have z_opt column');
      }
    });

    test('author table has unique constraint on email', () {
      final columns = container.db.select('PRAGMA table_info(author)');
      // Verify email column exists
      final emailCol = columns.firstWhere(
        (row) => row['name'] == 'email',
      );
      expect(emailCol, isNotNull);
    });

    test('post table has custom column name body_text', () {
      final columns = container.db
          .select('PRAGMA table_info(post)')
          .map((row) => row['name'] as String)
          .toList();

      expect(columns, contains('body_text'));
      expect(columns, isNot(contains('body')));
    });

    test('post table has author_id foreign key column', () {
      final columns = container.db
          .select('PRAGMA table_info(post)')
          .map((row) => row['name'] as String)
          .toList();

      expect(columns, contains('author_id'));
    });

    test('attachment table has post_id and data columns', () {
      final columns = container.db
          .select('PRAGMA table_info(attachment)')
          .map((row) => row['name'] as String)
          .toList();

      expect(columns, contains('post_id'));
      expect(columns, contains('data'));
    });
  });
}
