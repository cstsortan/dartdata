# Implementation Plan: z_pk Integer Foreign Key Resolution

**Track ID:** zpk-integer-fk_20260405
**Spec:** [spec.md](./spec.md)
**Created:** 2026-04-05
**Status:** [~] In Progress

## Overview

Add `getRelationshipIds()` to `ModelDescriptor` so descriptors can report related object UUIDs without knowing about z_pk. `ModelContext` resolves each UUID -> z_pk via SQL lookup and injects the integer into the map before executing INSERT/UPDATE. Delete rules and `fetchRelated` also resolve parent UUID -> z_pk before querying children. The generator and all test models are updated to emit integer FK columns.


## Phase 1: Schema Foundation

Add the `getRelationshipIds()` method to `ModelDescriptor` and update hand-written test models to use object references with integer FK columns.

### Tasks

- [x] Task 1.1: Add `getRelationshipIds()` to `ModelDescriptor` in `dartdata/lib/src/schema/schema.dart` — default empty implementation returning `const {}`
- [x] Task 1.2: Update `BucketListItem` model class to use `Trip? trip` object reference instead of `String? tripId`
- [x] Task 1.3: Update `BucketListItemDescriptor` — `ColumnType.integer` for `trip_id`, `fromMap` without tripId, add `getRelationshipIds` override
- [x] Task 1.4: Update `SubItem` model class to use `BucketListItem? bucketListItem` object reference
- [x] Task 1.5: Update `SubItemDescriptor` — `ColumnType.integer` for `bucket_list_item_id`, `fromMap` without bucketListItemId, add `getRelationshipIds` override
- [x] Task 1.6: Update `LivingAccommodation` model class to use `Trip? trip` object reference
- [x] Task 1.7: Update `LivingAccommodationDescriptor` — `ColumnType.integer` for `trip_id`, add `getRelationshipIds` override
- [x] Task 1.8: Update `DenyBucketListItemDescriptor` and `NoActionBucketListItemDescriptor` with same changes
- [x] Task 1.9: Update `$BucketListItem.tripId` and `$LivingAccommodation.tripId` QueryField statics from `QueryField<String>` to `QueryField<int>`
- [x] Task 1.10: Verify compilation with `dart analyze`

### Verification

- [x] Compilation succeeds (runtime tests may fail until ModelContext is updated)
- [x] `getRelationshipIds()` exists on `ModelDescriptor` with default empty map

## Phase 2: ModelContext FK Resolution

Implement the core FK UUID -> z_pk resolution logic in `ModelContext` for insert/update operations.

### Tasks

- [x] Task 2.1: Write failing test — `BucketListItem FK stores Trip z_pk integer after insert + save` (RED)
- [x] Task 2.2: Implement `_resolveRelationshipFks` private method in `ModelContext` — iterates `getRelationshipIds()`, resolves each UUID via `SELECT z_pk FROM related_table WHERE id = ?`, injects integer into map
- [x] Task 2.3: Call `_resolveRelationshipFks` in `_execute()` for both insert and update paths, before switch
- [x] Task 2.4: Run failing test — verify it passes (GREEN)

### Verification

- [x] FK column stores integer z_pk, not UUID string
- [x] Inserting child with unsaved parent throws `StateError` with clear message

## Phase 3: Delete Rules & fetchRelated

Update `_enforceDeleteRules` and `fetchRelated` to resolve parent UUID -> z_pk before querying child tables.

### Tasks

- [x] Task 3.1: Write failing test — `deleting a Trip cascades to its BucketListItems` with z_pk FK (RED)
- [x] Task 3.2: Add `_resolveZpk` helper method to `ModelContext` — `SELECT z_pk FROM tableName WHERE id = ?`
- [x] Task 3.3: Refactor `_resolveRelationshipFks` to use `_resolveZpk` helper
- [x] Task 3.4: Update `_enforceDeleteRules` — resolve `parentZpk` and pass to cascade/nullify/deny operations
- [x] Task 3.5: Update `_cascadeDelete` and `_denyDelete` signatures to accept `int parentZpk` instead of `String parentId`
- [x] Task 3.6: Update `fetchRelated` — resolve parent UUID -> z_pk before querying children
- [x] Task 3.7: Run cascade test — verify it passes (GREEN)

### Verification

- [x] Cascade delete works with z_pk integer FK columns
- [x] Nullify delete rule sets FK to NULL correctly
- [x] Deny delete rule throws when children exist
- [x] `fetchRelated` returns correct children via z_pk lookup

## Phase 4: Update Relationship Tests

Update all remaining relationship tests to use object references and verify z_pk integer behavior.

### Tasks

- [x] Task 4.1: Update nullify test to use `trip:` object reference and verify NULL FK via raw SQL
- [x] Task 4.2: Update deny test to use `trip:` object reference with parent-before-child save ordering
- [x] Task 4.3: Update noAction test to use `trip:` object reference
- [x] Task 4.4: Update one-to-one optional tests (null trip, linked trip with z_pk verification)
- [x] Task 4.5: Update fetchRelated tests — use `trip:` object refs, add second trip for `bli-other`, parent-before-child save ordering
- [x] Task 4.6: Update nested cascade test — save parent, then child, then grandchild sequentially
- [x] Task 4.7: Update deny+rollback test with object references
- [x] Task 4.8: Run all relationship tests — verify all pass (17/17)
- [x] Task 4.9: Run full `dartdata` test suite — verify all pass (153/153)

### Verification

- [x] All relationship tests pass
- [x] Full `dartdata` test suite passes with zero failures

## Phase 5: Generator Updates

Update the code generator to emit integer FK columns, null in `toMap()`, and `getRelationshipIds()` overrides.

### Tasks

- [x] Task 5.1: Change `fkColumnDefinition` in generator from `ColumnType.text` to `ColumnType.integer`
- [x] Task 5.2: Change `toMap()` emission to output `null` for FK columns (with comment)
- [x] Task 5.3: Add `_generateGetRelationshipIds` method to generator
- [x] Task 5.4: Emit `getRelationshipIds` in descriptor class output
- [x] Task 5.5: Verify generator compiles with `dart analyze`

### Verification

- [x] Generator emits `ColumnType.integer` for FK columns
- [x] Generator emits `null` for FK values in `toMap()`
- [x] Generator emits `getRelationshipIds()` override for descriptors with FK relationships

## Phase 6: Update Example Package

Update the hand-committed `.g.dart` files and tests in `dartdata_example` to match the new integer FK scheme.

### Tasks

- [ ] Task 6.1: Update `attachment.g.dart` — integer FK, null in toMap, getRelationshipIds
- [ ] Task 6.2: Update `category.g.dart` — integer FK, null in toMap, getRelationshipIds
- [ ] Task 6.3: Update `comment.g.dart` — integer FK, null in toMap, getRelationshipIds
- [ ] Task 6.4: Update `post.g.dart` — integer FK, null in toMap, getRelationshipIds
- [ ] Task 6.5: Update `post_tag.g.dart` — integer FK (both post_id and tag_id), null in toMap, getRelationshipIds
- [ ] Task 6.6: Verify compilation with `dart analyze`
- [ ] Task 6.7: Update `dartdata_example/test/relationship_test.dart` — expect integer z_pk in raw SQL assertions
- [ ] Task 6.8: Update `dartdata_example/test/crud_test.dart` — parent-before-child save ordering, integer FK expectations
- [ ] Task 6.9: Update `dartdata_example/test/container_test.dart` — update column type expectations if any
- [ ] Task 6.10: Run `dartdata_example` test suite — verify all pass

### Verification

- [ ] All `.g.dart` files use integer FK columns
- [ ] All example tests pass

## Final Verification

- [ ] All acceptance criteria met
- [ ] `dartdata` tests passing (`flutter test` — zero failures)
- [ ] `dartdata_example` tests passing (`dart test` — zero failures)
- [ ] No UUID strings stored in FK columns (verified via raw SQL spot-check)
- [ ] Generator output matches hand-written test models
- [ ] Ready for review

---

_Generated by Conductor. Tasks will be marked [~] in progress and [x] complete._
