# dartdata

A Flutter persistence library inspired by Apple's SwiftData.
Annotate your models, query with type safety, store files — no SQL required.

> **Status:** Early development (v0.1.0). Core APIs are functional but the code generator and several features are still in progress. Not yet published on pub.dev.

## Features

- **`@model` annotation** — mark any Dart class as persistent. The code generator handles SQLite table creation, serialization, and type-safe query descriptors.
- **Type-safe queries** — no raw SQL. Use `Query<T>`, `Predicate<T>`, and `QueryField<T>` to build queries with full IDE autocomplete.
- **Relationships** — declare one-to-one, one-to-many, and many-to-many relations as plain Dart fields. The generator handles foreign keys, joins, and junction tables.
- **External file storage** — store images, audio, or documents on disk with `ExternalFile`. SQLite holds a lightweight UUID reference; the binary lives in a flat `_EXTERNAL_DATA/` directory.
- **Context-scoped mutations** — all writes go through `ModelContext`, giving you clear transaction boundaries and rollback support.
- **SQLite under the hood** — fast, file-based, zero server setup via `sqlite3` FFI.

## Platform support

iOS, Android, macOS, Windows, Linux.

Flutter Web is **not supported** (no `dart:io`, no file-based SQLite).

## Quick start

### 1. Define a model

```dart
import 'package:dartdata/dartdata.dart';

part 'trip.g.dart';

@model
class Trip {
  @attribute(primaryKey: true)
  final String id;

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
```

### 2. Set up the container

```dart
final container = await ModelContainer.create(
  schema: Schema([Trip.self, BucketListItem.self]),
  configuration: ModelConfiguration(
    url: 'trips.db',
    migrationPolicy: MigrationPolicy.automatic,
  ),
);
```

### 3. Read and write data

```dart
final context = ModelContext(container);

// Insert
final trip = Trip(
  name: 'Grand Tour',
  destination: 'Europe',
  startDate: DateTime(2026, 6, 1),
  endDate: DateTime(2026, 8, 31),
);
context.insert(trip);
await context.save();

// Query
final upcoming = await context.fetch(
  Query<Trip>(
    where: $Trip.startDate > DateTime.now(),
    orderBy: [$Trip.startDate.ascending()],
    limit: 20,
  ),
);

// Update
trip.name = 'Grand Tour 2.0';
await context.save();

// Delete
context.delete(trip);
await context.save();
```

## Repository layout

```
dartdata/
├── dartdata/                 # Main library package
│   ├── lib/
│   │   ├── dartdata.dart     # Public barrel export
│   │   └── src/
│   │       ├── annotations/  # @model, @attribute, @relationship
│   │       ├── context/      # ModelContainer, ModelContext
│   │       ├── query/        # Query<T>, Predicate<T>, QueryField<T>
│   │       ├── storage/      # ExternalFile
│   │       └── schema/       # Schema, ModelDescriptor, MigrationPolicy
│   └── test/
└── dartdata_generator/       # build_runner code generator
```

## Running tests

```bash
cd dartdata
flutter test
```

## Dependencies

| Package | Purpose |
|---------|---------|
| `sqlite3` + `sqlite3_flutter_libs` | SQLite via FFI |
| `path_provider` | App directory resolution |
| `uuid` | Primary key and blob filename generation |
| `build` + `source_gen` | Code generation infrastructure |

## License

See [LICENSE](LICENSE) for details.
