# Implementation Plan: Full Validation Test Suite

**Track ID:** test-suite_20260405
**Spec:** [spec.md](./spec.md)
**Created:** 2026-04-05
**Status:** [ ] Not Started

## Overview

Write tests in four logical groups, each in its own file under `dartdata/test/`. Start with pure-Dart unit tests (no SQLite) for fast feedback, then progress to integration tests that open an in-memory SQLite database. Each phase ends with a full `flutter test` green run before the next phase begins.

---

## Phase 1: Unit Tests — Query & Predicate Layer

Test the type-safe query building layer without any database involvement.

### Tasks

- [ ] Task 1.1: Write `test/query_field_test.dart` — test all `QueryField<T>` operators: `equals`, `notEquals`, `>`, `>=`, `<`, `<=`, `isNull`, `isNotNull`, `isIn`, `contains`, `startsWith`, `between`. Verify each produces the correct SQL fragment and parameter list.
- [ ] Task 1.2: Write predicate composition tests in the same file — AND (`&`), OR (`|`), NOT (`!`). Verify nested combinations produce correct SQL with proper parenthesisation.
- [ ] Task 1.3: Write `SortDescriptor` tests — `ascending()` and `descending()` emit the correct `ORDER BY` fragment.
- [ ] Task 1.4: Write `Query<T>` construction tests — verify `where`, `orderBy`, `limit`, `offset` are wired through correctly to the SQL builder.

### Verification

- [ ] `flutter test test/query_field_test.dart` passes with zero failures.

---

## Phase 2: Unit Tests — ExternalFile State Machine

Test the sealed `ExternalFile` class state transitions in isolation (no file I/O, no SQLite).

### Tasks

- [ ] Task 2.1: Write `test/external_file_unit_test.dart` — test `ExternalFile.fromBytes(bytes)` creates a `_StagedBytesState`; accessing `.file` throws `StateError`.
- [ ] Task 2.2: Test `ExternalFile.fromPath(path)` creates a `_StagedPathState`; accessing `.file` throws `StateError`.
- [ ] Task 2.3: Test `ExternalFile.fromManagedPath(uuid)` creates a `_ManagedState`; `.file` returns a `dart:io File` pointing to `_EXTERNAL_DATA/<uuid>`.
- [ ] Task 2.4: Test `_PendingDeletionState` — mark for deletion, verify `.file` throws `StateError`.
- [ ] Task 2.5: Test state transitions: staged → managed (simulate `ModelContext.save()` promotion), managed → pending deletion.

### Verification

- [ ] `flutter test test/external_file_unit_test.dart` passes (extends/replaces existing `external_file_test.dart` coverage).

---

## Phase 3: Integration Tests — ModelContainer & Schema

Test SQLite database creation, pragma enforcement, and schema correctness.

### Tasks

- [ ] Task 3.1: Write/extend `test/model_container_test.dart` — verify `ModelContainer.create()` with `inMemory` config opens successfully.
- [ ] Task 3.2: Verify WAL mode is set: `PRAGMA journal_mode` returns `wal`.
- [ ] Task 3.3: Verify foreign keys are enforced: `PRAGMA foreign_keys` returns `1`.
- [ ] Task 3.4: Verify each model table has the hidden `z_pk INTEGER PRIMARY KEY AUTOINCREMENT` and `z_opt INTEGER` columns (query `PRAGMA table_info(<table>)`).
- [ ] Task 3.5: Verify user-declared columns exist with the correct types.
- [ ] Task 3.6: Verify `Schema` with multiple descriptors creates all tables.
- [ ] Task 3.7: Verify `MigrationPolicy.automatic` adds a new column to an existing table without data loss (create container, insert row, recreate container with an extra column in descriptor, verify old row still present and new column is NULL).

### Verification

- [ ] `flutter test test/model_container_test.dart` passes.

---

## Phase 4: Integration Tests — ModelContext CRUD

Test all read/write operations against an in-memory database.

### Tasks

- [ ] Task 4.1: Write/extend `test/model_context_test.dart` — `insert` + `save` + `fetch` round-trip returns the inserted object with correct field values.
- [ ] Task 4.2: `fetch` with no predicate returns all rows.
- [ ] Task 4.3: `fetch` with each `QueryField` operator filters correctly (use `$Trip.destination.equals(...)`, date comparisons, `isIn`, `contains`, etc.).
- [ ] Task 4.4: `fetch` with combined predicates (AND, OR, NOT) returns correct subsets.
- [ ] Task 4.5: `fetch` with `orderBy` returns rows in the correct order (ascending and descending).
- [ ] Task 4.6: `fetch` with `limit` and `offset` returns the correct page.
- [ ] Task 4.7: `fetchOne<T>(id:)` returns the correct object or `null` for a missing id.
- [ ] Task 4.8: `fetchCount` returns the correct integer (with and without a predicate).
- [ ] Task 4.9: Mutate a fetched object's fields, call `save()`, re-fetch — verify updated values are persisted.
- [ ] Task 4.10: `delete` + `save` removes the row; subsequent fetch returns empty.
- [ ] Task 4.11: `rollback()` discards pending inserts — subsequent fetch returns empty.
- [ ] Task 4.12: `transaction()` commits all inserts on success; all rows are fetchable after.
- [ ] Task 4.13: `transaction()` rolls back all inserts when the callback throws; no rows remain.
- [ ] Task 4.14: `context.changes` stream emits an event after `save()`.

### Verification

- [ ] `flutter test test/model_context_test.dart` passes.

---

## Phase 5: Integration Tests — Relationships & Delete Rules

Test relationship wiring and cascade/nullify/deny behaviour.

### Tasks

- [ ] Task 5.1: Add relationship test models to `test/helpers/test_models.dart`: `BucketListItem` (child of `Trip`, one-to-many), `LivingAccommodation` (one-to-one optional on `Trip`).
- [ ] Task 5.2: Write `test/relationship_test.dart` — insert a `Trip` with a `BucketListItem`, save; fetch the `BucketListItem` and verify its foreign key column matches the `Trip.z_pk`.
- [ ] Task 5.3: Test `DeleteRule.cascade` — delete a `Trip`; verify its `BucketListItem` rows are also deleted.
- [ ] Task 5.4: Test `DeleteRule.nullify` — delete a `Trip`; verify the `LivingAccommodation` foreign key column is set to NULL.
- [ ] Task 5.5: Test `DeleteRule.deny` — attempt to delete a `Trip` that has related `BucketListItem` rows; verify a `StateError` (or equivalent) is thrown.
- [ ] Task 5.6: Test one-to-one optional (`LivingAccommodation?`) — insert `Trip` with `accommodation = null`; verify FK column is NULL in SQLite.

### Verification

- [ ] `flutter test test/relationship_test.dart` passes.

---

## Phase 6: Integration Tests — ExternalFile Persistence

Test blob storage end-to-end with ModelContext.

### Tasks

- [ ] Task 6.1: Write/extend `test/external_file_test.dart` — insert a `Photo` with staged bytes, call `save()`; verify the `image_data` column holds a UUID string (not NULL).
- [ ] Task 6.2: Verify the file exists at `_EXTERNAL_DATA/<uuid>` with the correct bytes.
- [ ] Task 6.3: Insert a `Photo` with a staged path (copy of a temp file), call `save()`; verify file exists in `_EXTERNAL_DATA/` and bytes match source.
- [ ] Task 6.4: Delete a `Photo` that has a managed `ExternalFile`, call `save()`; verify the `_EXTERNAL_DATA/<uuid>` file is removed.
- [ ] Task 6.5: Insert a `Photo` with `imageData = null`, call `save()`; verify `image_data` column is NULL.

### Verification

- [ ] `flutter test test/external_file_test.dart` passes.

---

## Final Verification

- [ ] All acceptance criteria met (review spec.md checklist)
- [ ] `flutter test` from `dartdata/` shows zero failures across all test files
- [ ] Coverage has not regressed vs. baseline
- [ ] No new implementation code was written — only test code (this is a pure-test track)
- [ ] Ready for review

---

_Generated by Conductor. Tasks will be marked [~] in progress and [x] complete._
