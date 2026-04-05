# dartdata

A Flutter persistence library inspired by Apple's SwiftData.
Annotate your models, query with type safety, store files — no SQL required.

## Repository layout

```
dartdata/                        ← repo root (you are here)
├── CLAUDE.md
├── API_DESIGN.md                ← full API design document — read this first
├── dartdata/                    ← main library package
│   ├── lib/
│   │   ├── dartdata.dart        ← public barrel export
│   │   └── src/
│   │       ├── annotations/     ← @model, @attribute, @relationship
│   │       ├── context/         ← ModelContainer, ModelContext
│   │       ├── query/           ← Query<T>, Predicate<T>, QueryField<T>
│   │       ├── storage/         ← ExternalFile (state machine)
│   │       └── schema/          ← Schema, ModelDescriptor, MigrationPolicy
│   └── test/
│       ├── helpers/
│       │   └── test_models.dart ← hand-written models (simulate codegen output)
│       ├── model_container_test.dart
│       ├── model_context_test.dart
│       └── external_file_test.dart
└── dartdata_generator/          ← build_runner code generator
    ├── build.yaml
    └── lib/
        └── src/
            └── model_generator.dart
```

## Running tests

Always run from inside the `dartdata` package directory:

```bash
cd dartdata
flutter test                    # run all tests
flutter test test/model_context_test.dart   # single file
flutter test --coverage         # with coverage report
```

## Development approach: TDD

This project uses strict TDD. The cycle is:

1. **Red** — write a failing test in `dartdata/test/`
2. **Green** — write the minimum implementation to make it pass
3. **Refactor** — clean up without breaking tests

Do not write implementation code without a failing test that justifies it.

## Key design decisions (read `API_DESIGN.md` before changing anything)

### SQLite internals (mirrors real SwiftData schema)
- Every model table gets two hidden system columns: `z_pk INTEGER PRIMARY KEY AUTOINCREMENT` (internal integer key used for joins) and `z_opt INTEGER` (optimistic-lock version counter, incremented on every UPDATE).
- Foreign keys use `z_pk` integers, not user-facing UUID strings.
- WAL mode (`PRAGMA journal_mode=WAL`) is always enabled. Do not change this.
- Foreign key enforcement (`PRAGMA foreign_keys=ON`) is always enabled.

### External file storage (mirrors real SwiftData _EXTERNAL_DATA layout)
- `ExternalFile` fields are stored as a UUID filename in a flat `_EXTERNAL_DATA/` directory — **not** a hierarchical path.
- The SQLite column holds the UUID string (the filename), or NULL.
- `ExternalFile` uses a **sealed class state machine** with four states: `_StagedBytesState`, `_StagedPathState`, `_ManagedState`, `_PendingDeletionState`.
- `ExternalFile.file` (the `dart:io File`) is only accessible in `_ManagedState`. It throws `StateError` in all other states.
- All I/O is delegated to `dart:io File` — no bespoke streaming or byte wrappers.

### Code generation
- Annotations live in `dartdata/lib/src/annotations/`. They are plain Dart — no build-time magic.
- The generator (`dartdata_generator`) reads `@model` classes via `source_gen` and emits a `.g.dart` file per model.
- During development, `dartdata/test/helpers/test_models.dart` contains **hand-written** descriptors that simulate generator output. This lets us test `ModelContainer` and `ModelContext` before the generator is complete.
- The generated `$ClassName` descriptor exposes `QueryField<T>` statics used to build type-safe predicates.

### Relationships
- **One-to-one / one-to-many**: declared as plain Dart fields with `@relationship`. Generator emits the foreign key column and index.
- **Simple many-to-many**: declare `List<B>` on both sides + `@relationship(inverse: 'fieldName')` on one side. Generator creates a hidden junction table.
- **Many-to-many with extra fields**: requires an explicit junction `@model`. No auto junction table is generated in this case.

### Platform support
iOS, Android, macOS, Windows, Linux. **Flutter Web is explicitly not supported** (no `dart:io`, no file-based SQLite). Do not add web conditionals.

### No Dart macros
Dart macros were cancelled. Use `build_runner` + `source_gen` only.

## What is implemented

- [x] `@model`, `@attribute`, `@relationship` annotation classes
- [x] `DeleteRule` enum
- [x] `ExternalFile` with sealed state machine
- [x] `Schema`, `ModelDescriptor`, `ColumnDefinition`, `MigrationPolicy`
- [x] `Query<T>`, `Predicate<T>`, `QueryField<T>`, `SortDescriptor<T>`
- [x] `ModelContainer` — opens SQLite, enables WAL + FK, creates tables
- [x] `ModelContext` — insert, fetch, fetchOne, fetchCount, delete, rollback, save, transaction
- [x] `ModelContext.changes` stream (stub — notifies but does not yet carry a full `ContextChangeSet`)
- [x] TDD test suite (26 tests, all currently failing — intentional starting point)
- [x] `dartdata_generator` scaffold (SharedPartBuilder + ModelGenerator skeleton)

## What is not yet implemented

- [ ] Generator: full `@attribute` annotation reading (primary key, unique, indexed, columnName, transient)
- [ ] Generator: relationship column emission + junction table generation
- [ ] Generator: `ExternalFile` field handling in `toMap` / `fromMap`
- [ ] `ModelContext`: full `ExternalFile` persist/delete during save
- [ ] `ModelContext`: full `ContextChangeSet` with per-table change tracking
- [ ] `QueryObserver<T>` Flutter widget
- [ ] `ModelContainerProvider` InheritedWidget
- [ ] `ModelContext.of(BuildContext)` lookup
- [ ] Schema migration (`MigrationPolicy.automatic` column adding, `MigrationPolicy.resetOnConflict`)
- [ ] `cleanOrphanedBlobs()` implementation
- [ ] Relationship fetching (lazy loading of related objects)
- [ ] `ModelConfiguration.document(directory:)` full implementation
- [ ] `z_opt` conflict detection on update

## Dependency notes

- `sqlite3` + `sqlite3_flutter_libs`: SQLite via FFI. Do not switch to `sqflite`.
- `path_provider`: resolves app support directory for the database and blob storage.
- `uuid`: used for primary key generation in user models and blob filenames.
- `build` + `source_gen`: code generation infrastructure. Do not introduce `macros`.
