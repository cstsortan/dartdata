# z_pk Integer Foreign Key Resolution

**Date:** 2026-04-05
**Status:** Approved
**Branch:** feature/example-integration-pkg

## Problem

CLAUDE.md specifies: "Foreign keys use `z_pk` integers, not user-facing UUID strings." The current implementation stores UUID strings in FK columns because `ModelContext` has no mechanism to resolve UUIDs to `z_pk` values. This was a pragmatic workaround — the generator emits `ColumnType.text` FK columns and `toMap()` writes `.id` (UUID string) directly.

A real SwiftData database (inspected: `StoreContent` from a `.presentr` bundle) confirms:
- FK columns like `ZSLIDE.ZPRESENTATION` store `Z_PK` integers
- No `REFERENCES` or `FOREIGN KEY` constraints in DDL
- `Z_PRIMARYKEY` table tracks max z_pk per entity for ID assignment
- Every table has `Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER`

## Design

### Approach: Object references only (Approach A)

Users set relationships via object references (`Comment(post: myPost)`), never raw FK values. `ModelContext` resolves the related object's UUID to its `z_pk` integer at save time.

### 1. Data Model & Schema

- FK columns use `ColumnType.integer`, storing the related row's `z_pk`
- No `REFERENCES` constraint (matching SwiftData)
- Column name convention unchanged (`author_id`, `post_id`, etc.)
- `toMap()` returns `null` for FK columns (same pattern as ExternalFile)
- `fromMap()` unchanged — FK integer columns are not read into model fields (relationship hydration is a separate future concern)

### 2. New Descriptor Method

```dart
/// Returns a map of FK column names to the related object's UUID string.
/// ModelContext resolves each UUID to the related row's z_pk integer.
Map<String, String?> getRelationshipIds(Object model) => const {};
```

Default empty implementation — only descriptors with `isForeignKeySide: true` relationships override it. Parallels the existing `externalFileFields` + `getExternalFile()` pattern.

### 3. ModelContext Resolution Flow

**During `_execute()` (insert/update):**

1. `descriptor.toMap(model)` -> map has `null` for FK columns
2. `descriptor.getRelationshipIds(model)` -> `{'post_id': 'abc-uuid'}`
3. For each entry, resolve: `SELECT z_pk FROM related_table WHERE id = ?`
4. Inject integer into map: `map['post_id'] = 42`
5. Build SQL values as usual

The related table for each FK is found via `descriptor.relationships` (each `RelationshipDefinition` with `isForeignKeySide: true` has `fkColumnName` and `relatedTable`).

**During `_enforceDeleteRules()`:**

Currently uses `parentMap['id']` (UUID string) to query `WHERE fkColumn = ?`. Change to: resolve parent UUID -> z_pk first (`SELECT z_pk FROM parent_table WHERE id = ?`), then query children with `WHERE fkColumn = z_pk_integer`.

**Parent-before-child ordering:**

If a child references a not-yet-persisted parent, the `SELECT z_pk` returns empty. Throw a `StateError` with message: "Cannot resolve z_pk for {tableName} with id '{uuid}'. The related object must be saved before referencing it." Explicit topological ordering of inserts is a future enhancement.

### 4. Generator Changes

- `fkColumnDefinition`: revert to `ColumnType.integer`
- `toMap()`: emit `null` for FK columns with comment
- New `getRelationshipIds()` override: `{'fk_column': m.relatedObject?.id}`
- `fromMap()`: no change

### 5. Test Model Changes

**Hand-written (`test_models.dart`):**

- `BucketListItem.tripId` (String?) -> `BucketListItem.trip` (Trip?) object reference
- Same for `SubItem`, `LivingAccommodation`
- FK column type: `ColumnType.text` -> `ColumnType.integer`
- `toMap()`: return `null` for FK columns
- Add `getRelationshipIds()` override

**Generated `.g.dart` files:**

All 5 files with FK columns (attachment, category, comment, post, post_tag) updated to match.

**Tests:**

- Raw SQL assertions change from expecting UUID strings to expecting integer z_pk values
- Relationship tests use object references instead of raw FK manipulation

## Out of Scope

These items are related but not part of this change. They should be addressed in future tracks:

- **Lazy loading / relationship hydration on fetch** — reconstructing related objects from FK z_pk values during `fromMap()`
- **`Z_PRIMARYKEY` metadata table** — dartdata uses SQLite `AUTOINCREMENT`, not a counter table like Core Data
- **`Z_ENT` entity type column** — dartdata doesn't use entity type IDs
- **Junction table FK resolution** — junction tables use a separate mechanism already
- **Parent-before-child insert ordering** — automatic topological sort of pending operations during save; for now, we throw a clear error if z_pk lookup fails
