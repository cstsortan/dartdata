import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../schema/schema.dart';

/// Configuration for a [ModelContainer].
class ModelConfiguration {
  /// Database filename relative to the app's support directory, or `:memory:`.
  final String url;
  final MigrationPolicy migrationPolicy;
  final bool isReadOnly;

  const ModelConfiguration({
    this.url = 'default.db',
    this.migrationPolicy = MigrationPolicy.automatic,
    this.isReadOnly = false,
  });

  /// An isolated in-memory database. Ideal for tests.
  const ModelConfiguration.inMemory()
      : url = ':memory:',
        migrationPolicy = MigrationPolicy.automatic,
        isReadOnly = false;

  /// Document mode — the database and blobs live inside a directory package
  /// (e.g., `MyDocument.myapp/`). Mirrors SwiftData document-based apps.
  factory ModelConfiguration.document({required Directory directory}) =
      _DocumentModelConfiguration;

  bool get isInMemory => url == ':memory:';
}

class _DocumentModelConfiguration extends ModelConfiguration {
  final Directory directory;

  _DocumentModelConfiguration({required this.directory})
      : super(url: p.join(directory.path, 'StoreContent'));
}

/// The root persistence object. Owns the SQLite database connection and the
/// external blob storage directory.
///
/// Create once at app startup and share via a provider:
/// ```dart
/// final container = await ModelContainer.create(
///   schema: Schema([Trip.descriptor, BucketListItem.descriptor]),
///   configuration: ModelConfiguration(url: 'trips.db'),
/// );
/// ```
class ModelContainer {
  final Schema schema;
  final ModelConfiguration configuration;
  final Database db;
  final Directory blobDirectory;

  ModelContainer._({
    required this.schema,
    required this.configuration,
    required this.db,
    required this.blobDirectory,
  });

  /// Creates and opens a [ModelContainer].
  ///
  /// - Enables WAL mode for concurrent read/write access.
  /// - Applies the schema (creating tables if needed) according to
  ///   [ModelConfiguration.migrationPolicy].
  /// - Sets up the external blob directory.
  static Future<ModelContainer> create({
    required Schema schema,
    ModelConfiguration configuration = const ModelConfiguration(),
  }) async {
    final db = await _openDatabase(configuration);
    final blobDir = await _blobDirectory(configuration);

    final container = ModelContainer._(
      schema: schema,
      configuration: configuration,
      db: db,
      blobDirectory: blobDir,
    );

    await container._applySchema();
    return container;
  }

  /// Opens a [ModelContainer] against an already-open [Database].
  ///
  /// Used for testing migration scenarios where the same in-memory database
  /// must be re-opened with a different schema.
  /// Opens a [ModelContainer] against an already-open [Database].
  ///
  /// Used for testing migration scenarios where the same in-memory database
  /// must be re-opened with a different schema. The blob directory defaults
  /// to a temporary directory since the DB is already open.
  static Future<ModelContainer> createFromDatabase({
    required Schema schema,
    required Database db,
    ModelConfiguration configuration = const ModelConfiguration(),
  }) async {
    final blobDir = Directory.systemTemp.createTempSync('dartdata_blobs_');

    final container = ModelContainer._(
      schema: schema,
      configuration: configuration,
      db: db,
      blobDirectory: blobDir,
    );

    await container._applySchema();
    return container;
  }

  static Future<Database> _openDatabase(ModelConfiguration config) async {
    if (config.isInMemory) {
      final db = sqlite3.openInMemory();
      _configurePragmas(db);
      return db;
    }

    final appDir = await getApplicationSupportDirectory();
    final dbPath = p.join(appDir.path, config.url);
    await Directory(p.dirname(dbPath)).create(recursive: true);

    final db = sqlite3.open(dbPath,
        mode: config.isReadOnly ? OpenMode.readOnly : OpenMode.readWriteCreate);
    _configurePragmas(db);
    return db;
  }

  static void _configurePragmas(Database db) {
    db.execute('PRAGMA journal_mode=WAL;');
    db.execute('PRAGMA foreign_keys=ON;');
  }

  static Future<Directory> _blobDirectory(ModelConfiguration config) async {
    if (config.isInMemory) {
      // In-memory databases use a temp directory for blobs.
      return Directory.systemTemp.createTempSync('dartdata_blobs_');
    }
    final appDir = await getApplicationSupportDirectory();
    final dbName = p.basenameWithoutExtension(config.url);
    final dir =
        Directory(p.join(appDir.path, '.dartdata', dbName, '_EXTERNAL_DATA'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _applySchema() async {
    // Create the internal bookkeeping tables.
    db.execute('''
      CREATE TABLE IF NOT EXISTS _schema_version (
        z_name TEXT PRIMARY KEY,
        z_fingerprint TEXT NOT NULL,
        z_version INTEGER NOT NULL DEFAULT 1
      )
    ''');

    db.execute('''
      CREATE TABLE IF NOT EXISTS _change_log (
        z_pk INTEGER PRIMARY KEY AUTOINCREMENT,
        z_table TEXT NOT NULL,
        z_row_pk TEXT NOT NULL,
        z_change_type INTEGER NOT NULL,  -- 0=insert, 1=update, 2=delete
        z_timestamp REAL NOT NULL
      )
    ''');

    final currentFingerprint = schema.fingerprint;

    // Check for an existing fingerprint.
    final existing = db.select(
      "SELECT z_fingerprint FROM _schema_version WHERE z_name = 'schema'",
    );

    if (existing.isEmpty) {
      // First open — create all tables and store the fingerprint.
      for (final descriptor in schema.descriptors) {
        _createTableIfNeeded(descriptor);
      }
      _storeFingerprint(currentFingerprint);
      return;
    }

    final storedFingerprint = existing.first['z_fingerprint'] as String;
    final schemaChanged = storedFingerprint != currentFingerprint;

    switch (configuration.migrationPolicy) {
      case MigrationPolicy.automatic:
        if (schemaChanged) {
          _migrateAutomatic();
          _storeFingerprint(currentFingerprint);
        }
        // Ensure any brand-new tables exist even if fingerprint matched
        // (shouldn't happen, but defensive).
        for (final descriptor in schema.descriptors) {
          _createTableIfNeeded(descriptor);
        }
      case MigrationPolicy.none:
        if (schemaChanged) {
          throw SchemaMismatchError(
            'The on-disk schema fingerprint ($storedFingerprint) does not '
            'match the current schema ($currentFingerprint). '
            'Use MigrationPolicy.automatic or resetOnConflict to handle '
            'schema changes.',
          );
        }
      case MigrationPolicy.resetOnConflict:
        if (schemaChanged) {
          _migrateResetOnConflict();
          _storeFingerprint(currentFingerprint);
        }
    }
  }

  void _storeFingerprint(String fingerprint) {
    db.execute(
      "INSERT OR REPLACE INTO _schema_version (z_name, z_fingerprint, z_version) "
      "VALUES ('schema', '$fingerprint', 1)",
    );
  }

  void _migrateAutomatic() {
    for (final descriptor in schema.descriptors) {
      // Check if table exists.
      final tableExists = db
          .select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='${descriptor.tableName}'",
          )
          .isNotEmpty;

      if (!tableExists) {
        _createTableIfNeeded(descriptor);
        continue;
      }

      // Get existing columns.
      final existingCols = db
          .select("PRAGMA table_info(${descriptor.tableName})")
          .map((r) => r['name'] as String)
          .toSet();

      // Add missing columns (additive only — never drop).
      // SQLite ALTER TABLE ADD COLUMN does not support UNIQUE inline,
      // so uniqueness is enforced via a separate CREATE UNIQUE INDEX.
      for (final col in descriptor.columns) {
        if (!existingCols.contains(col.columnName)) {
          final parts = <String>[col.columnName, _sqlType(col.type)];

          final needsNotNull = col.isPrimaryKey || !col.isNullable;
          if (needsNotNull) {
            parts.add('NOT NULL');
            parts.add('DEFAULT ${_sqlDefault(col.type)}');
          }

          db.execute(
            "ALTER TABLE ${descriptor.tableName} ADD COLUMN ${parts.join(' ')}",
          );

          // Enforce UNIQUE via index (isPrimaryKey implies UNIQUE NOT NULL).
          if (col.isPrimaryKey || col.isUnique) {
            db.execute(
              "CREATE UNIQUE INDEX IF NOT EXISTS "
              "idx_${descriptor.tableName}_${col.columnName}_unique "
              "ON ${descriptor.tableName} (${col.columnName})",
            );
          }
        }
      }
    }
  }

  void _migrateResetOnConflict() {
    // Drop all model tables.
    for (final descriptor in schema.descriptors) {
      db.execute("DROP TABLE IF EXISTS ${descriptor.tableName}");
    }
    // Recreate all tables.
    for (final descriptor in schema.descriptors) {
      _createTableIfNeeded(descriptor);
    }
  }

  void _createTableIfNeeded(ModelDescriptor descriptor) {
    final columns = descriptor.columns.map((col) {
      final parts = <String>[col.columnName, _sqlType(col.type)];
      // z_pk is the real SQLite primary key; user-declared PKs become UNIQUE NOT NULL.
      if (col.isPrimaryKey) {
        parts.add('UNIQUE');
        parts.add('NOT NULL');
      } else {
        if (col.isUnique) parts.add('UNIQUE');
        if (!col.isNullable) parts.add('NOT NULL');
      }
      return parts.join(' ');
    }).join(',\n  ');

    // Every model table also gets the optimistic-lock counter.
    db.execute('''
      CREATE TABLE IF NOT EXISTS ${descriptor.tableName} (
        z_pk INTEGER PRIMARY KEY AUTOINCREMENT,
        z_opt INTEGER NOT NULL DEFAULT 0,
        $columns
      )
    ''');

    // Create indexes for indexed fields.
    for (final col in descriptor.columns.where((c) => c.isIndexed)) {
      db.execute('''
        CREATE INDEX IF NOT EXISTS
        idx_${descriptor.tableName}_${col.columnName}
        ON ${descriptor.tableName} (${col.columnName})
      ''');
    }

    // Auto-index FK columns used in relationships.
    for (final rel in descriptor.relationships) {
      final fkCol = rel.fkColumnName ?? '${rel.fieldName}_id';
      if (descriptor.columns.any((c) => c.columnName == fkCol)) {
        db.execute('''
          CREATE INDEX IF NOT EXISTS
          idx_${descriptor.tableName}_$fkCol
          ON ${descriptor.tableName} ($fkCol)
        ''');
      }
    }

    // Create junction tables for many-to-many relationships.
    for (final jt in descriptor.junctionTables) {
      db.execute('''
        CREATE TABLE IF NOT EXISTS ${jt.tableName} (
          ${jt.firstFkColumn} INTEGER NOT NULL REFERENCES ${jt.firstTable}(z_pk),
          ${jt.secondFkColumn} INTEGER NOT NULL REFERENCES ${jt.secondTable}(z_pk),
          PRIMARY KEY (${jt.firstFkColumn}, ${jt.secondFkColumn})
        )
      ''');
    }
  }

  String _sqlType(ColumnType type) => switch (type) {
        ColumnType.text => 'TEXT',
        ColumnType.integer => 'INTEGER',
        ColumnType.real => 'REAL',
        ColumnType.blob => 'BLOB',
      };

  /// Returns a sensible SQL default literal for [type].
  ///
  /// Used when adding a NOT NULL column via ALTER TABLE to a table that may
  /// already contain rows (SQLite requires a default in that case).
  String _sqlDefault(ColumnType type) => switch (type) {
        ColumnType.text => "''",
        ColumnType.integer => '0',
        ColumnType.real => '0.0',
        ColumnType.blob => "x''",
      };

  /// Remove blob files that have no corresponding row in the database.
  ///
  /// Safe to call at startup or on a background isolate during maintenance.
  /// Returns the number of files removed.
  Future<int> cleanOrphanedBlobs() async {
    // TODO: implement cross-referencing blob UUIDs against the change log.
    return 0;
  }

  /// Close the database connection.
  void close() => db.dispose();
}
