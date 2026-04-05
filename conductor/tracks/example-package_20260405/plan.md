# Implementation Plan: dartdata_example Integration Package

**Track ID:** example-package_20260405
**Spec:** [spec.md](./spec.md)
**Created:** 2026-04-05
**Status:** [~] In Progress

## Overview

Create a `dartdata_example/` pure-Dart package with seven CMS domain models that exercise every dartdata feature. Write integration tests in six test files, each covering a distinct feature area. All tests run with `dart test` against a real SQLite database.

## Phase 1: Package Scaffold & Models

Set up the package structure, dependencies, and all seven annotated model classes.

### Tasks

- [x] Task 1.1: Create `dartdata_example/pubspec.yaml` with dependencies on `dartdata`, `dartdata_generator`, `sqlite3`, `uuid`, `build_runner`, `source_gen`, and `test`
- [x] Task 1.2: Create `lib/src/models/author.dart` — `@model` with `@attribute(unique, indexed)` on email, `ExternalFile` photo field
- [x] Task 1.3: Create `lib/src/models/post.dart` — `@model` with `@attribute(primaryKey, indexed, transient, columnName)`, `DateTime`, `bool`, one-to-many owner relationship to `Author`
- [x] Task 1.4: Create `lib/src/models/category.dart` — `@model` with one-to-one relationship to `Post`, `DeleteRule.nullify`
- [x] Task 1.5: Create `lib/src/models/comment.dart` — `@model` with one-to-many from `Post`, `DeleteRule.cascade`
- [x] Task 1.6: Create `lib/src/models/tag.dart` — `@model` with many-to-many with `Post` (auto junction table), `DeleteRule.deny`
- [x] Task 1.7: Create `lib/src/models/post_tag.dart` — explicit junction `@model` (many-to-many with extra field `pinnedAt DateTime?`)
- [x] Task 1.8: Create `lib/src/models/attachment.dart` — `@model` with `ExternalFile`, `DeleteRule.cascade`, one-to-many from `Post`
- [x] Task 1.9: Create `lib/src/schema.dart` — shared `Schema([...])` used by all tests

### Verification

- [x] `dart run build_runner build --delete-conflicting-outputs` completes without errors
- [x] All `.g.dart` files are generated for each model

## Phase 2: Container & CRUD Tests

Write integration tests for database container setup and basic CRUD operations.

### Tasks

- [x] Task 2.1: Create `test/container_test.dart` — verify WAL mode enabled, foreign keys ON, z_pk/z_opt system columns present, all tables created from schema
- [x] Task 2.2: Create `test/crud_test.dart` — insert, fetch, fetchOne, update, delete for each model; verify z_opt increments on update

### Verification

- [x] `flutter test test/container_test.dart` passes (10 tests)
- [x] `flutter test test/crud_test.dart` passes (18 tests)

## Phase 3: Query Tests

Write integration tests for all predicate operators, sort descriptors, and pagination.

### Tasks

- [x] Task 3.1: Create `test/query_test.dart` — test `equals`, `contains`, `startsWith`, `>`, `<`, `between`, `isIn`, `isNull` operators
- [x] Task 3.2: Add AND (`&`) and OR (`|`) combined predicate tests
- [x] Task 3.3: Add `orderBy` ascending/descending tests
- [x] Task 3.4: Add `limit` + `offset` pagination tests
- [x] Task 3.5: Add `fetchCount` tests (count drafts, count comments per post)

### Verification

- [x] `flutter test test/query_test.dart` passes (18 tests)

## Phase 4: Relationship Tests

Write integration tests for relationship enforcement and delete rules.

### Tasks

- [ ] Task 4.1: Create `test/relationship_test.dart` — test `DeleteRule.cascade` (deleting Post removes Comments and Attachments)
- [ ] Task 4.2: Add `DeleteRule.nullify` test (deleting Post nullifies Category FK)
- [ ] Task 4.3: Add `DeleteRule.deny` test (deleting Post blocked when Tags exist)
- [ ] Task 4.4: Add `DeleteRule.noAction` test (Comment → Author)
- [ ] Task 4.5: Add many-to-many auto junction table tests (Post ↔ Tag)
- [ ] Task 4.6: Add explicit junction model tests (PostTag with pinnedAt)

### Verification

- [ ] `dart test test/relationship_test.dart` passes

## Phase 5: ExternalFile Tests

Write integration tests for ExternalFile round-trip lifecycle.

### Tasks

- [ ] Task 5.1: Create `test/external_file_test.dart` — test `ExternalFile.fromBytes` round-trip (write Author photo, fetch, read bytes)
- [ ] Task 5.2: Add `ExternalFile.fromPath` test (copy from temp file for Attachment)
- [ ] Task 5.3: Add `ExternalFile.file` access test (stream read, stat, readAsBytes on managed file)
- [ ] Task 5.4: Add ExternalFile deletion test (deleting model removes blob from `_EXTERNAL_DATA/`)

### Verification

- [ ] `dart test test/external_file_test.dart` passes

## Phase 6: Migration Tests

Write integration tests for schema migration policies.

### Tasks

- [ ] Task 6.1: Create `test/migration_test.dart` — test `MigrationPolicy.automatic` (add a column, reopen container, verify existing data intact)
- [ ] Task 6.2: Add `MigrationPolicy.resetOnConflict` test (schema change wipes and recreates)
- [ ] Task 6.3: Add transaction success test (insert Post + Comments atomically)
- [ ] Task 6.4: Add transaction rollback test (simulated failure mid-transaction)

### Verification

- [ ] `dart test test/migration_test.dart` passes

## Final Verification

- [ ] All acceptance criteria met
- [ ] `dart test` passes with zero failures from `dartdata_example/`
- [ ] All seven models exercise their intended annotation features
- [ ] Feature coverage matrix from EXAMPLE_PLAN.md fully covered
- [ ] Ready for review

---

_Generated by Conductor. Tasks will be marked [~] in progress and [x] complete._
