# Flutter SQLite Wrapper — API Design

> A Flutter persistence library inspired by Apple's SwiftData framework.
> Built on SQLite. Powered by code generation.

---

## Philosophy

SwiftData made persistence feel native to Swift by hiding SQL entirely behind annotations and type-safe queries. This library brings that same philosophy to Dart and Flutter:

- **Annotate, don't configure** — mark a class `@model` and it becomes persistent.
- **Type-safe queries** — no raw SQL strings, no stringly-typed field names.
- **Relationship-aware** — declare relations as plain Dart fields; the library handles joins, cascades, and inverse mappings.
- **Context-scoped mutations** — all writes go through a `ModelContext`, giving you clear transaction boundaries and undo support.
- **SQLite under the hood** — fast, file-based, zero server setup.
- **External file storage** — large binary assets (images, audio, documents) live on disk; SQLite holds only a lightweight reference.

---

## Package Structure

```
flutter_swiftdata/
├── lib/
│   ├── flutter_swiftdata.dart          # Public barrel export
│   ├── src/
│   │   ├── annotations/
│   │   │   ├── model.dart              # @model, @attribute
│   │   │   └── relationship.dart      # @relationship
│   │   ├── context/
│   │   │   ├── model_container.dart
│   │   │   └── model_context.dart
│   │   ├── query/
│   │   │   ├── query.dart             # Query<T>
│   │   │   ├── predicate.dart         # Predicate<T>
│   │   │   └── sort_descriptor.dart
│   │   └── schema/
│   │       └── schema.dart            # Schema, ModelConfiguration
├── flutter_swiftdata_generator/        # build_runner code-gen package
│   └── lib/
│       └── src/
│           └── model_generator.dart
```

---

## 1. `@model` — Declaring a Persistent Model

Annotate any plain Dart class with `@model`. The code generator reads this and produces:
- A SQLite `CREATE TABLE` statement
- A `$ModelName` descriptor class used for type-safe queries
- `toMap()` / `fromMap()` serialization helpers

```dart
import 'package:flutter_swiftdata/flutter_swiftdata.dart';

part 'trip.g.dart'; // generated

@model
class Trip {
  // Every @model gets a persisted primary key by default.
  // You can override the field name or type.
  @attribute(primaryKey: true)
  final String id;

  String name;
  String destination;
  DateTime startDate;
  DateTime endDate;

  @relationship(deleteRule: DeleteRule.cascade)
  List<BucketListItem> bucketList;

  @relationship()
  LivingAccommodation? accommodation;

  Trip({
    String? id,
    required this.name,
    required this.destination,
    required this.startDate,
    required this.endDate,
    this.bucketList = const [],
    this.accommodation,
  }) : id = id ?? const Uuid().v4();
}
```

### `@attribute` options

| Parameter      | Type          | Default  | Description                                      |
|----------------|---------------|----------|--------------------------------------------------|
| `primaryKey`   | `bool`        | `false`  | Marks field as primary key (only one per model). |
| `unique`       | `bool`        | `false`  | Adds a UNIQUE constraint.                        |
| `indexed`      | `bool`        | `false`  | Adds a database index for faster queries.        |
| `columnName`   | `String?`     | `null`   | Override the SQLite column name.                 |
| `transient`    | `bool`        | `false`  | Exclude this field from persistence entirely.    |

```dart
@model
class User {
  @attribute(primaryKey: true)
  final String id;

  @attribute(unique: true, indexed: true)
  String email;

  @attribute(transient: true)
  String? cachedDisplayName; // never written to SQLite
}
```

---

## 2. `ModelContainer` — Setting Up the Store

`ModelContainer` is the root object that owns your schema and the SQLite database connection. Create it once (e.g., in `main()`) and share it via a provider.

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = await ModelContainer.create(
    schema: Schema([Trip.self, BucketListItem.self, LivingAccommodation.self]),
    configuration: ModelConfiguration(
      // Optional: named in-memory database for tests
      // url: ModelConfiguration.inMemory,
      url: 'trips.db',
      migrationPolicy: MigrationPolicy.automatic,
    ),
  );

  runApp(
    ModelContainerProvider(
      container: container,
      child: const MyApp(),
    ),
  );
}
```

### `ModelConfiguration` options

| Parameter         | Type              | Default                       | Description                                   |
|-------------------|-------------------|-------------------------------|-----------------------------------------------|
| `url`             | `String`          | `'default.db'`                | File name (relative to app documents dir) or `:memory:`. |
| `migrationPolicy` | `MigrationPolicy` | `MigrationPolicy.automatic`   | How schema changes are handled.               |
| `isReadOnly`      | `bool`            | `false`                       | Open the database in read-only mode.          |

### `MigrationPolicy`

```dart
enum MigrationPolicy {
  /// Add new columns / tables automatically. Never drops columns.
  automatic,

  /// Throw an error if schema has changed. Use during development.
  none,

  /// Drop and recreate all tables. All data is lost.
  resetOnConflict,
}
```

---

## 3. `ModelContext` — Reading and Writing Data

A `ModelContext` is a short-lived unit of work scoped to a single screen or operation. It tracks inserts, updates, and deletes, and flushes them to SQLite on `save()`.

### Accessing a context

```dart
// Inside a widget
final context = ModelContext.of(context);         // from inherited widget
final context = ModelContext(container);           // manual (e.g., in a service)
```

### Inserting

```dart
final trip = Trip(
  name: 'Grand Tour',
  destination: 'Europe',
  startDate: DateTime(2026, 6, 1),
  endDate: DateTime(2026, 8, 31),
);

context.insert(trip);
await context.save(); // writes to SQLite
```

### Fetching

```dart
// Fetch all
final trips = await context.fetch(Query<Trip>());

// With a predicate and sort
final upcoming = await context.fetch(
  Query<Trip>(
    where: $Trip.startDate > DateTime.now(),
    orderBy: [$Trip.startDate.ascending()],
    limit: 20,
  ),
);

// Fetch by primary key
final trip = await context.fetchOne<Trip>(id: '123');
```

### Updating

Models are reference types after insertion — mutate them directly and call `save()`.

```dart
trip.name = 'Grand Tour 2.0';
await context.save();
```

### Deleting

```dart
context.delete(trip);
await context.save();
```

### Rollback

```dart
context.rollback(); // discards all pending inserts/updates/deletes
```

### Transactions

```dart
await context.transaction(() async {
  context.insert(trip);
  context.insert(bucketListItem);
  // If an exception is thrown here, neither insert is committed.
});
```

---

## 4. `@relationship` — Declaring Relations

Relationships are declared as plain Dart fields on your `@model` class. The generator infers cardinality from the field type:

| Dart field type       | Cardinality   | Stored as                    |
|-----------------------|---------------|------------------------------|
| `RelatedModel?`       | One-to-one    | Foreign key on this table    |
| `RelatedModel`        | One-to-one    | Foreign key on this table (required) |
| `List<RelatedModel>`  | One-to-many   | Foreign key on child table   |

```dart
@model
class Trip {
  // one-to-many: Trip owns many BucketListItems
  @relationship(deleteRule: DeleteRule.cascade)
  List<BucketListItem> bucketList;

  // one-to-one: Trip optionally has one LivingAccommodation
  @relationship(deleteRule: DeleteRule.nullify)
  LivingAccommodation? accommodation;
}

@model
class BucketListItem {
  String title;
  bool isInBucket;

  // inverse of Trip.bucketList
  @relationship(inverse: 'bucketList')
  Trip? trip;
}
```

### `@relationship` options

| Parameter     | Type          | Default              | Description                                                   |
|---------------|---------------|----------------------|---------------------------------------------------------------|
| `deleteRule`  | `DeleteRule`  | `DeleteRule.nullify` | What happens to related objects when this object is deleted.  |
| `inverse`     | `String?`     | `null`               | Field name on the related model that forms the inverse link.  |
| `minimumModelCount` | `int` | `0`                  | Minimum number of related objects (validation only).          |
| `maximumModelCount` | `int?` | `null`              | Maximum number of related objects (null = unlimited).         |

### Many-to-many relationships

For a simple many-to-many, declare `List<B>` on both sides and put `@relationship(inverse:)` on one of them. The library generates the hidden junction table — you never see it or interact with it directly:

```dart
@model
class Movie {
  String title;

  @relationship(inverse: 'movies')
  List<Actor> actors;
}

@model
class Actor {
  String name;
  List<Movie> movies;
}
```

Generated junction table (hidden, managed by the library):
```sql
CREATE TABLE _movie_actor (
  movie_id TEXT REFERENCES movie(id) ON DELETE CASCADE,
  actor_id TEXT REFERENCES actor(id) ON DELETE CASCADE,
  PRIMARY KEY (movie_id, actor_id)
);
```

If you need **extra fields on the relationship** (e.g. the role an actor plays in a movie), SwiftData requires an explicit junction model — and so does this library:

```dart
@model
class Movie {
  String title;

  @relationship(deleteRule: DeleteRule.cascade)
  List<MovieRole> roles;
}

@model
class Actor {
  String name;

  @relationship(deleteRule: DeleteRule.cascade)
  List<MovieRole> roles;
}

@model
class MovieRole {
  String character;
  bool isLead;

  @relationship(inverse: 'roles')
  Movie? movie;

  @relationship(inverse: 'roles')
  Actor? actor;
}
```

### `DeleteRule`

```dart
enum DeleteRule {
  /// Set the foreign key to NULL on the related objects.
  nullify,

  /// Delete all related objects (cascade).
  cascade,

  /// Prevent deletion if related objects exist (throws StateError).
  deny,

  /// Do nothing — related objects become orphans.
  noAction,
}
```

---

## 5. `Query<T>` & Predicates — Type-Safe Queries

The code generator produces a `$ModelName` descriptor class for every `@model`. These descriptors expose typed column references used to build predicates and sort descriptors — no strings, no raw SQL.

### Generated descriptor (example)

For `class Trip`, the generator emits:

```dart
// trip.g.dart (generated — do not edit)
abstract class $Trip {
  static final QueryField<String>   id          = QueryField('id');
  static final QueryField<String>   name        = QueryField('name');
  static final QueryField<String>   destination = QueryField('destination');
  static final QueryField<DateTime> startDate   = QueryField('start_date');
  static final QueryField<DateTime> endDate     = QueryField('end_date');
}
```

### Building a query

```dart
final query = Query<Trip>(
  where: $Trip.destination.equals('Paris') & $Trip.startDate > DateTime.now(),
  orderBy: [$Trip.startDate.ascending(), $Trip.name.descending()],
  limit: 10,
  offset: 0,
);

final results = await context.fetch(query);
```

### `QueryField<T>` operators

| Method / Operator           | SQL equivalent            |
|-----------------------------|---------------------------|
| `.equals(value)`            | `= value`                 |
| `.notEquals(value)`         | `!= value`                |
| `> value`                   | `> value`                 |
| `>= value`                  | `>= value`                |
| `< value`                   | `< value`                 |
| `<= value`                  | `<= value`                |
| `.isNull()`                 | `IS NULL`                 |
| `.isNotNull()`              | `IS NOT NULL`             |
| `.isIn(list)`               | `IN (...)`                |
| `.contains(substring)`      | `LIKE '%substring%'`      |
| `.startsWith(prefix)`       | `LIKE 'prefix%'`          |
| `.between(low, high)`       | `BETWEEN low AND high`    |

### Combining predicates

```dart
// AND
final p = $Trip.destination.equals('Paris') & $Trip.startDate > DateTime.now();

// OR
final p = $Trip.destination.equals('Paris') | $Trip.destination.equals('Rome');

// NOT
final p = !$Trip.destination.equals('Paris');
```

### Sorting

```dart
$Trip.startDate.ascending()   // ORDER BY start_date ASC
$Trip.name.descending()       // ORDER BY name DESC
```

### Counting

```dart
final count = await context.fetchCount(Query<Trip>(
  where: $Trip.destination.equals('Paris'),
));
```

---

## 6. Reactive Queries — `QueryObserver<T>`

For Flutter UI, you often want to rebuild when data changes. `QueryObserver` wraps a `Query` and exposes a stream of results.

```dart
class TripListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return QueryObserver<Trip>(
      query: Query<Trip>(orderBy: [$Trip.startDate.ascending()]),
      builder: (context, trips, child) {
        if (trips == null) return const CircularProgressIndicator();
        return ListView.builder(
          itemCount: trips.length,
          itemBuilder: (_, i) => TripTile(trips[i]),
        );
      },
    );
  }
}
```

Under the hood, `QueryObserver` subscribes to change notifications emitted by `ModelContext.save()` and re-runs the query when relevant tables are modified.

---

## 7. Schema Migrations

With `MigrationPolicy.automatic`, the library handles additive changes (new tables, new columns) without data loss. For destructive changes (renames, type changes), you provide a `MigrationPlan`.

```dart
final container = await ModelContainer.create(
  schema: Schema([Trip.self, BucketListItem.self]),
  configuration: ModelConfiguration(
    url: 'trips.db',
    migrationPolicy: MigrationPolicy.custom(
      MigrationPlan(
        steps: [
          MigrationStep(
            fromVersion: 1,
            toVersion: 2,
            migrate: (db) async {
              await db.execute(
                'ALTER TABLE trip RENAME COLUMN notes TO description',
              );
            },
          ),
        ],
      ),
    ),
  ),
);
```

---

## 8. Testing

Use `ModelConfiguration.inMemory` to get a fresh, isolated in-memory database per test — no file cleanup needed.

```dart
test('inserts and fetches a trip', () async {
  final container = await ModelContainer.create(
    schema: Schema([Trip.self]),
    configuration: ModelConfiguration.inMemory(),
  );
  final context = ModelContext(container);

  final trip = Trip(
    name: 'Test Trip',
    destination: 'Nowhere',
    startDate: DateTime.now(),
    endDate: DateTime.now().add(const Duration(days: 7)),
  );

  context.insert(trip);
  await context.save();

  final results = await context.fetch(Query<Trip>());
  expect(results.length, 1);
  expect(results.first.name, 'Test Trip');
});
```

---

## 9. Full End-to-End Example

```dart
// models/trip.dart
import 'package:flutter_swiftdata/flutter_swiftdata.dart';
part 'trip.g.dart';

@model
class Trip {
  @attribute(primaryKey: true)
  final String id;

  @attribute(indexed: true)
  String name;
  String destination;
  DateTime startDate;
  DateTime endDate;

  @relationship(deleteRule: DeleteRule.cascade)
  List<BucketListItem> bucketList;

  Trip({
    String? id,
    required this.name,
    required this.destination,
    required this.startDate,
    required this.endDate,
    this.bucketList = const [],
  }) : id = id ?? const Uuid().v4();
}

@model
class BucketListItem {
  @attribute(primaryKey: true)
  final String id;

  String title;
  bool isInBucket;

  @relationship(inverse: 'bucketList')
  Trip? trip;

  BucketListItem({
    String? id,
    required this.title,
    this.isInBucket = false,
  }) : id = id ?? const Uuid().v4();
}
```

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final container = await ModelContainer.create(
    schema: Schema([Trip.self, BucketListItem.self]),
    configuration: ModelConfiguration(url: 'trips.db'),
  );

  runApp(ModelContainerProvider(container: container, child: const MyApp()));
}
```

```dart
// trip_list_screen.dart
class TripListScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final modelContext = ModelContext.of(context);

    return Scaffold(
      body: QueryObserver<Trip>(
        query: Query<Trip>(orderBy: [$Trip.startDate.ascending()]),
        builder: (context, trips, _) => ListView(
          children: (trips ?? []).map((t) => ListTile(title: Text(t.name))).toList(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final trip = Trip(
            name: 'New Adventure',
            destination: 'TBD',
            startDate: DateTime.now(),
            endDate: DateTime.now().add(const Duration(days: 14)),
          );
          modelContext.insert(trip);
          await modelContext.save();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

---

## 10. External File Storage — `ExternalFile`

Storing large binary blobs (images, videos, audio, PDFs) directly in SQLite degrades query performance and inflates the database file. SwiftData solves this with `@Attribute(.externalStorage)` — the data lives as a file on disk and SQLite stores only a path reference.

This library mirrors that behaviour, but uses a dedicated **`ExternalFile`** wrapper type instead of `Uint8List?`. This distinction matters: in Dart there is no way to intercept field access and trigger a load transparently, so a plain `Uint8List?` field creates an irresolvable ambiguity — does `null` mean *no file exists*, or *not yet loaded*? `ExternalFile` eliminates that ambiguity entirely.

### The `ExternalFile` type

`ExternalFile` manages a path in the library's blob store and exposes the underlying `dart:io` `File` directly. All reading, writing, and streaming delegates to the standard `dart:io` API — no bespoke wrappers.

```dart
class ExternalFile {
  /// The managed dart:io File. Use this for all reading and writing —
  /// readAsBytes(), openRead(), writeAsBytes(), openWrite(), stat(), etc.
  File get file;

  /// Convenience for file.uri, useful for video players and other APIs
  /// that accept a URI rather than a File.
  Uri get uri;

  /// Mark this ExternalFile for deletion on the next ModelContext.save().
  void delete();

  /// Create an ExternalFile pre-populated with bytes.
  /// The bytes are staged and written to managed storage on save().
  factory ExternalFile.fromBytes(Uint8List data);

  /// Create an ExternalFile from an existing path on disk (e.g., image picker).
  /// The file is copied into managed storage on save().
  factory ExternalFile.fromPath(String path);
}
```

`null` means **no file**. A non-null `ExternalFile` means **a file exists** in managed storage — all I/O goes through `file`.

### Declaring external fields

```dart
@model
class Photo {
  @attribute(primaryKey: true)
  final String id;

  String title;
  DateTime takenAt;

  ExternalFile? imageData;     // large — lazy by default
  ExternalFile? thumbnailData; // smaller, but still off-heap

  Photo({
    String? id,
    required this.title,
    required this.takenAt,
    this.imageData,
    this.thumbnailData,
  }) : id = id ?? const Uuid().v4();
}
```

No extra annotation is needed — the generator recognises `ExternalFile` and `ExternalFile?` field types automatically.

### What the library does under the hood

- On **insert / update**: writes the bytes to `<appSupportDir>/.flutter_swiftdata/blobs/<modelType>/<id>_<fieldName>` and stores that path in the SQLite row.
- On **fetch**: populates the `ExternalFile` handle (with path and size) but does **not** read bytes from disk.
- On **delete**: removes both the SQLite row and all associated blob files.

### Storage layout on disk

```
<appSupportDir>/
└── .flutter_swiftdata/
    └── blobs/
        └── photo/
            ├── a1b2c3_imageData
            └── a1b2c3_thumbnailData
```

### Reading

`ExternalFile.file` is a standard `dart:io` `File`. Use whichever `dart:io` API fits the use case:

```dart
final photos = await context.fetch(
  Query<Photo>(orderBy: [$Photo.takenAt.descending()]),
);

final photo = photos.first;

// Small file — read all bytes at once
if (photo.imageData != null) {
  final bytes = await photo.imageData!.file.readAsBytes();
  setState(() => _image = MemoryImage(bytes));
}

// Check file size without reading content
final stat = await photo.imageData?.file.stat();
print(stat?.size); // bytes, no I/O beyond a stat() call
```

For video, audio, or any file too large to buffer in memory, stream it directly using `dart:io`'s `openRead()`:

```dart
@model
class VideoClip {
  @attribute(primaryKey: true)
  final String id;

  String title;
  Duration duration;
  ExternalFile? videoData;
}

// Stream into a video player — no full buffer needed
final clip = await context.fetchOne<VideoClip>(id: '...');
final stream = clip.videoData!.file.openRead();
await videoPlayerController.setStream(stream);

// Or pass the URI directly to players that accept one
await videoPlayerController.setFile(clip.videoData!.file);
```

### Writing

```dart
// From raw bytes (e.g., image picker)
final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
if (picked != null) {
  final photo = Photo(
    title: 'Sunset',
    takenAt: DateTime.now(),
    imageData: ExternalFile.fromBytes(await picked.readAsBytes()),
  );
  context.insert(photo);
  await context.save(); // staged bytes written to managed storage
}

// From an existing path (avoids loading into memory)
final photo = Photo(
  title: 'Import',
  takenAt: DateTime.now(),
  imageData: ExternalFile.fromPath(picked.path),
);
context.insert(photo);
await context.save(); // file copied into managed storage

// Write a recording or download directly to the managed file via openWrite()
final clip = VideoClip(title: 'Recording', duration: ..., videoData: null);
context.insert(clip);
await context.save(); // row created, videoData still null

clip.videoData = ExternalFile.fromPath(tempRecordingPath);
await context.save(); // file moved into managed storage
```

### Updating and deleting the file

```dart
// Replace the image
photo.imageData?.delete();
photo.imageData = ExternalFile.fromBytes(newBytes);
await context.save(); // old file removed, new file written

// Remove the image entirely
photo.imageData?.delete();
photo.imageData = null;
await context.save();
```

### Implementation — how `ExternalFile` works internally

#### State machine

An `ExternalFile` is always in exactly one of four states, modelled with sealed classes:

```dart
sealed class _ExternalFileState {}

/// File already exists in managed blob storage. [file] is valid.
final class _ManagedState extends _ExternalFileState {
  final File managedFile;
  _ManagedState(this.managedFile);
}

/// Created via fromBytes(). Bytes held in memory, not yet written to disk.
final class _StagedBytesState extends _ExternalFileState {
  final Uint8List bytes;
  _StagedBytesState(this.bytes);
}

/// Created via fromPath(). Source file must be copied to managed storage on save().
final class _StagedPathState extends _ExternalFileState {
  final String sourcePath;
  _StagedPathState(this.sourcePath);
}

/// delete() was called. Managed file (if any) will be removed on save().
final class _PendingDeletionState extends _ExternalFileState {
  final File? managedFile;
  _PendingDeletionState(this.managedFile);
}
```

#### The `ExternalFile` class

```dart
class ExternalFile {
  _ExternalFileState _state;

  // Internal constructor — used by ModelContext when rehydrating from SQLite
  ExternalFile._managed(File file) : _state = _ManagedState(file);

  factory ExternalFile.fromBytes(Uint8List data) =>
      ExternalFile._()  .._state = _StagedBytesState(data);

  factory ExternalFile.fromPath(String path) =>
      ExternalFile._()  .._state = _StagedPathState(path);

  /// Only valid after the owning model has been saved at least once.
  /// Throws StateError if called while still staged.
  File get file {
    return switch (_state) {
      _ManagedState(:final managedFile) => managedFile,
      _ => throw StateError(
          'ExternalFile.file is not available until ModelContext.save() '
          'has been called. Use ExternalFile.fromBytes() and read the bytes '
          'directly if you need access before saving.',
        ),
    };
  }

  Uri get uri => file.uri;

  void delete() {
    _state = _PendingDeletionState(
      switch (_state) {
        _ManagedState(:final managedFile) => managedFile,
        _ => null, // was never persisted — nothing to delete on disk
      },
    );
  }

  // Called by ModelContext.save() — persists staged data and transitions to _ManagedState
  Future<void> _persist(File destination) async {
    switch (_state) {
      case _StagedBytesState(:final bytes):
        await destination.writeAsBytes(bytes);
      case _StagedPathState(:final sourcePath):
        await File(sourcePath).copy(destination.path);
      case _ManagedState():
        break; // already in place, nothing to do
      case _PendingDeletionState():
        throw StateError('Cannot persist a file marked for deletion.');
    }
    _state = _ManagedState(destination);
  }
}
```

#### Managed path layout

Each field gets a deterministic path derived from the model type, model ID, and field name:

```
<appSupportDir>/.flutter_swiftdata/blobs/<ModelType>/<modelId>/<fieldName>
```

For example:
```
.flutter_swiftdata/blobs/Photo/a1b2c3/imageData
.flutter_swiftdata/blobs/Photo/a1b2c3/thumbnailData
```

Grouping by `<modelId>/` means all blobs for a deleted model can be wiped with a single directory removal rather than per-field bookkeeping.

#### How `ModelContext.save()` orchestrates it

`save()` wraps both the SQLite write and the file I/O in a single operation:

```dart
Future<void> save() async {
  await _db.transaction(() async {
    for (final model in _pendingInserts + _pendingUpdates) {
      // 1. Persist any staged ExternalFile fields first
      for (final field in model._externalFileFields) {
        final externalFile = model._getExternalFile(field);
        if (externalFile == null) continue;

        final destination = _blobPath(model, field);
        await destination.parent.create(recursive: true);
        await externalFile._persist(destination);
      }

      // 2. Write the SQLite row (now contains valid managed paths)
      await _db.insert(model._tableName, model.toMap());
    }

    for (final model in _pendingDeletes) {
      // Delete managed blob directory for this model
      final dir = _blobDir(model);
      if (await dir.exists()) await dir.delete(recursive: true);

      await _db.delete(model._tableName, where: 'id = ?', whereArgs: [model.id]);
    }
  });

  _pendingInserts.clear();
  _pendingUpdates.clear();
  _pendingDeletes.clear();
}
```

Because the file writes happen inside `transaction()`, a failure mid-save leaves the SQLite row unchanged — the staged bytes remain in memory and `save()` can be retried safely. (Note: true atomicity between the filesystem and SQLite is inherently best-effort; the `cleanOrphanedBlobs()` utility handles any files that were written before a crash that rolled back the SQLite transaction.)

#### Code generation

The generator recognises `ExternalFile` and `ExternalFile?` field types and:

- Maps the field to a `TEXT` column (stores the managed path, or `NULL`).
- In `toMap()`: emits `field._state is _ManagedState ? managedFile.path : null`.
- In `fromMap()`: emits `ExternalFile._managed(File(row['fieldName']))` when the column is non-null.
- Adds the field name to `_externalFileFields` so `ModelContext` knows which fields to process during `save()`.

### Cleanup and orphan prevention

Blobs are deleted when their owning model is deleted. A maintenance utility sweeps any orphaned files whose parent row no longer exists:

```dart
final removed = await container.cleanOrphanedBlobs();
print('Cleaned up $removed orphaned blob files.');
```

---

---

## 11. Document-Based App Support

Examining a real SwiftData document-based app (`.presentr` file) reveals how Apple structures persistence on disk. The document is not a single file — it is a **package**: a directory that the OS presents as a single opaque file, containing:

```
MyDocument.presentr/          ← directory, appears as one file to the user
├── StoreContent              ← the SQLite database (SwiftData's fixed internal name)
├── StoreContent-shm          ← SQLite shared memory file (WAL mode)
├── StoreContent-wal          ← SQLite Write-Ahead Log
└── (external blobs live here too, alongside the database)
```

SQLite WAL mode (`PRAGMA journal_mode=WAL`) is significant: it allows concurrent reads during writes and is the mode SwiftData uses by default for better performance.

This pattern maps directly onto a Flutter document model. A `ModelContainer` configured in **document mode** points to a directory rather than a bare database file, keeping the SQLite database and all `ExternalFile` blobs co-located and self-contained.

### Document mode `ModelConfiguration`

```dart
// Standard (app database) — single shared store in app support directory
final container = await ModelContainer.create(
  schema: Schema([Trip.self]),
  configuration: ModelConfiguration(url: 'trips.db'),
);

// Document mode — database + blobs live inside a user-facing document directory
final container = await ModelContainer.create(
  schema: Schema([Slide.self, Asset.self]),
  configuration: ModelConfiguration.document(
    directory: Directory('/path/to/MyPresentation.presentr'),
  ),
);
```

In document mode, the internal layout mirrors SwiftData exactly:

```
MyPresentation.presentr/
├── StoreContent              ← SQLite database (WAL mode)
├── StoreContent-shm
├── StoreContent-wal
└── blobs/
    └── Asset/
        └── <id>/
            └── fileData      ← ExternalFile blobs, co-located with the DB
```

Benefits of this layout:
- The entire document — data and assets — is **one directory**. Copy, move, or share it and nothing is left behind.
- Compression (zip) of the directory produces a portable, self-contained archive (exactly what SwiftData does for document transfer).
- WAL mode means the `-shm` and `-wal` files appear only while the database is open; a cleanly-closed document contains only `StoreContent`.

### What the real SwiftData schema looks like

Inspecting an actual SwiftData document database (`StoreContent`) reveals the full picture:

**Tables in a real SwiftData database:**

| Table | Purpose |
|---|---|
| `ZPRESENTATION`, `ZSLIDE`, … | One table per `@Model` class. `Z` prefix on every name — Core Data convention. |
| `Z_PRIMARYKEY` | Entity registry: maps each model class name to an integer entity ID and tracks `Z_MAX` (the highest integer PK used). |
| `Z_METADATA` | Stores the schema version UUID and a serialised plist of container metadata. |
| `Z_MODELCACHE` | Compressed binary blob of the full model schema, used by SwiftData to detect schema changes on open. |
| `ACHANGE` | One row per changed object per transaction. Drives persistent history. |
| `ATRANSACTION` | One row per save. Records timestamp, author, bundle ID, and process ID. |
| `ATRANSACTIONSTRING` | String-interning table — deduplicates repeated author/bundle strings across `ATRANSACTION`. |

**Every model table has three hidden system columns:**

| Column | Type | Purpose |
|---|---|---|
| `Z_PK` | `INTEGER PRIMARY KEY` | Internal integer primary key (not the user-facing UUID). |
| `Z_ENT` | `INTEGER` | Entity type discriminator — matches `Z_PRIMARYKEY.Z_ENT`. Used for inheritance. |
| `Z_OPT` | `INTEGER` | Optimistic-lock version counter. Incremented on every update. Detects write conflicts. |

**Foreign keys are integer-to-integer**, not UUID-to-UUID. `ZSLIDE.ZPRESENTATION` stores the integer `Z_PK` of the parent `ZPRESENTATION` row, not the UUID.

**External storage sentinel format.** When a field is marked for external storage, SwiftData does _not_ store a file path in the column. Instead it stores a 38-byte sentinel blob: `\x02 + <UUID string> + \x00`. The UUID is the filename of the corresponding file in `.StoreContent_SUPPORT/_EXTERNAL_DATA/`. All externally-stored fields across all models share the same flat directory — there is no per-model or per-field subdirectory.

```
# What ZAUDIODATA contains in SQLite (38 bytes):
\x02  443E58F4-ABDE-417D-AA50-963A3A34B87A  \x00
 ↑ marker                                   ↑ null terminator

# Corresponding file on disk:
.StoreContent_SUPPORT/_EXTERNAL_DATA/443E58F4-ABDE-417D-AA50-963A3A34B87A
```

**Change tracking detail.** `ACHANGE.ZCHANGETYPE` is `0` for insert, `1` for update, `2` for delete. `ZENTITY` matches the entity ID in `Z_PRIMARYKEY`, `ZENTITYPK` is the `Z_PK` of the changed row. This is how SwiftData can tell observers exactly which rows changed after a save.

### What this means for our implementation

These findings correct and refine several earlier design choices:

**External blob storage** should use a flat UUID-keyed directory, not the hierarchical `<ModelType>/<modelId>/<fieldName>` path we designed. SwiftData uses a single `_EXTERNAL_DATA/` folder with UUID-named files. This is simpler and immune to model/field renames. The column stores a UUID string (we can drop the `\x02`/`\x00` sentinel markers — those are Core Data binary format internals we don't need to replicate).

**Optimistic locking.** Every row should carry a `z_opt INTEGER` version counter. `ModelContext.save()` increments it on update and checks it hasn't changed since the object was fetched, detecting concurrent-write conflicts.

**Built-in history tracking.** The `ACHANGE` + `ATRANSACTION` tables are how SwiftData powers its persistent history API — and how we will power `QueryObserver`. After every `save()`, the context emits the set of `(entityType, primaryKey, changeType)` tuples to any registered observers, which re-run their queries if affected tables appear in the change set.

**Integer primary keys internally.** Like Core Data, we use integer `Z_PK` values internally for joins and foreign keys. The user-facing `id` field (UUID or other type) is stored as a separate indexed column. This avoids storing 36-character UUID strings in every foreign-key column.

**`Z_MODELCACHE` equivalent.** We store a hash/fingerprint of the current schema in a `_schema_version` table on first open. On subsequent opens we compare it to detect schema drift and decide which `MigrationPolicy` action to take.

### SQLite WAL mode

Both document and standard containers use WAL mode by default:

```dart
// Applied automatically by ModelContainer.create() — no user action needed
await db.execute('PRAGMA journal_mode=WAL');
```

WAL mode gives:
- **Concurrent reads** while a write transaction is in progress (important for `QueryObserver`).
- **Faster commits** — appending to the WAL file is cheaper than writing to the main database file.
- **Crash safety** — incomplete WAL transactions are discarded on next open; committed ones are replayed.

---

## Open Questions / Next Decisions

1. **SQLite package** — ✅ Use `sqlite3` (via FFI). Supports iOS, Android, macOS, Windows, and Linux. `sqflite` is ruled out — Android/iOS only.
2. **Code generation** — ✅ Use `build_runner` + `source_gen`. Dart macros were cancelled and are no longer available.
3. **Many-to-many** — ✅ Mirror SwiftData's behaviour exactly:
   - **Simple many-to-many**: declare `List<B>` on both models, put `@relationship(inverse: 'fieldName')` on one side — the library auto-generates the hidden junction table.
   - **Many-to-many with extra fields** (e.g. a `joinedAt` date): require an explicit junction `@model` with two `@relationship` one-to-many fields. No magic join table is generated in this case.
4. **Undo / undo manager** — Should `ModelContext` support undo stacks like `NSUndoManager`?
5. **Encryption** — Optional SQLCipher integration for encrypted databases?
6. **External storage isolation** — ✅ Each `ModelContainer` gets its own blob directory, scoped by the container's database name:
   ```
   <appSupportDir>/.flutter_swiftdata/<dbName>/blobs/<ModelType>/<modelId>/<fieldName>
   ```
7. **Blob compression** — Should the library optionally gzip blobs before writing to disk?
8. **Platform support** — ✅ iOS, Android, macOS, Windows, and Linux are supported. Flutter Web is explicitly out of scope (no `dart:io`, no file-based SQLite).
