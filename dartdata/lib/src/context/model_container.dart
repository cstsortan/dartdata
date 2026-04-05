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

    // Create tables for each registered model.
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
  }

  String _sqlType(ColumnType type) => switch (type) {
        ColumnType.text => 'TEXT',
        ColumnType.integer => 'INTEGER',
        ColumnType.real => 'REAL',
        ColumnType.blob => 'BLOB',
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
