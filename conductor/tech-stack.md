# Tech Stack

## Primary Language

- **Dart** (SDK ≥ 3.0) — all library and generator code
- **Shell scripts** — tooling helpers (test runners, coverage scripts)

> **Important:** The core `dartdata` library must remain pure Dart compatible. No Flutter-only APIs (`dart:ui`, `package:flutter/*`) in the library core. This allows integration-style tests to run in a plain Dart VM without a Flutter engine.

## Target Consumer Framework

- **Flutter** (iOS, Android, macOS, Windows, Linux) — explicitly not Flutter Web

## Code Generation

- **build_runner** + **source_gen** — reads `@model` classes and emits `.g.dart` files
- No Dart macros (cancelled upstream)

## Database

- **SQLite** via `sqlite3` FFI (`package:sqlite3` + `sqlite3_flutter_libs`)
- WAL mode always enabled (`PRAGMA journal_mode=WAL`)
- Foreign key enforcement always enabled (`PRAGMA foreign_keys=ON`)
- Schema mirrors real SwiftData internals: `z_pk` integer PK, `z_opt` optimistic-lock counter

## Key Dependencies

| Package | Purpose |
|---|---|
| `sqlite3` | SQLite FFI bindings |
| `sqlite3_flutter_libs` | Bundled SQLite native libs for Flutter targets |
| `path_provider` | Resolves app support directory for DB + blob storage |
| `uuid` | UUID generation for primary keys and blob filenames |
| `build` | Code generation infrastructure |
| `source_gen` | Source generation helpers |

## External File Storage

- Blobs stored in a flat `_EXTERNAL_DATA/` directory (UUID filename, no hierarchy)
- SQLite column holds UUID string or NULL
- Managed via `ExternalFile` sealed state machine

## Distribution

- **pub.dev** — primary package registry
- **GitHub releases** — version tags and release notes
- Packages: `dartdata` (library) + `dartdata_generator` (build_runner generator)

## Platforms Supported

| Platform | Supported |
|---|---|
| iOS | Yes |
| Android | Yes |
| macOS | Yes |
| Windows | Yes |
| Linux | Yes |
| Flutter Web | **No** |
