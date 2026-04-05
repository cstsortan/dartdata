# Track Registry

This file maintains the registry of all development tracks for the project. Each track represents a distinct body of work with its own spec and implementation plan.

## Status Legend

| Symbol | Status      | Description               |
| ------ | ----------- | ------------------------- |
| `[ ]`  | Pending     | Not yet started           |
| `[~]`  | In Progress | Currently being worked on |
| `[x]`  | Completed   | Finished and verified     |

## Active Tracks

### [ ] context-change-set_20260405: Full ContextChangeSet

**Description:** Implement full ContextChangeSet with per-table change tracking
**Priority:** high
**Folder:** [./tracks/context-change-set_20260405/](./tracks/context-change-set_20260405/)

---

### [ ] query-observer_20260405: QueryObserver\<T\> Widget

**Description:** Reactive QueryObserver widget that re-queries on context changes
**Priority:** high
**Folder:** [./tracks/query-observer_20260405/](./tracks/query-observer_20260405/)

---

### [ ] flutter-providers_20260405: Flutter Provider Integration

**Description:** ModelContainerProvider InheritedWidget and ModelContext.of(BuildContext) lookup
**Priority:** high
**Folder:** [./tracks/flutter-providers_20260405/](./tracks/flutter-providers_20260405/)

---

### [ ] blob-maintenance_20260405: Blob Maintenance (cleanOrphanedBlobs)

**Description:** Implement cleanOrphanedBlobs() to remove unreferenced external files
**Priority:** medium
**Folder:** [./tracks/blob-maintenance_20260405/](./tracks/blob-maintenance_20260405/)

---

### [ ] document-mode_20260405: Document Mode

**Description:** ModelConfiguration.document(directory:) full implementation
**Priority:** medium
**Folder:** [./tracks/document-mode_20260405/](./tracks/document-mode_20260405/)

---

### [ ] error-handling_20260405: Error Handling & Edge Cases

**Description:** Comprehensive error handling, read-only mode, and edge case coverage
**Priority:** medium
**Folder:** [./tracks/error-handling_20260405/](./tracks/error-handling_20260405/)

---

### [x] zpk-integer-fk_20260405: z_pk Integer Foreign Key Resolution

**Description:** Resolve z_pk integer foreign keys across relationships, junction tables, and insert ordering
**Priority:** medium
**Folder:** [./tracks/zpk-integer-fk_20260405/](./tracks/zpk-integer-fk_20260405/)

---

## Completed Tracks

### [x] test-suite_20260405: Full Validation Test Suite

**Description:** Comprehensive TDD test suite covering all core dartdata functionality
**Priority:** critical
**Folder:** [./tracks/test-suite_20260405/](./tracks/test-suite_20260405/)

---

### [x] relationship-enforcement_20260405: Relationship Enforcement & Delete Rules

**Description:** Enforce relationship constraints and cascade/nullify/deny delete rules
**Priority:** critical
**Folder:** [./tracks/relationship-enforcement_20260405/](./tracks/relationship-enforcement_20260405/)

---

### [x] schema-migration_20260405: Schema Migration

**Description:** MigrationPolicy.automatic column adding and resetOnConflict
**Priority:** critical
**Folder:** [./tracks/schema-migration_20260405/](./tracks/schema-migration_20260405/)

---

### [x] optimistic-locking_20260405: z_opt Optimistic Locking

**Description:** z_opt conflict detection on update with version counter
**Priority:** critical
**Folder:** [./tracks/optimistic-locking_20260405/](./tracks/optimistic-locking_20260405/)

---

### [x] generator-attributes_20260405: Generator — @attribute Annotation Reading

**Description:** Read full @attribute annotation parameters (primary key, unique, indexed, columnName, transient)
**Priority:** high
**Folder:** [./tracks/generator-attributes_20260405/](./tracks/generator-attributes_20260405/)

---

### [x] generator-relationships_20260405: Generator — Relationship Emission

**Description:** Emit relationship columns, foreign keys, indexes, and junction tables
**Priority:** high
**Folder:** [./tracks/generator-relationships_20260405/](./tracks/generator-relationships_20260405/)

---

### [x] generator-external-files_20260405: Generator — ExternalFile Field Handling

**Description:** Emit ExternalFile field handling in toMap/fromMap
**Priority:** high
**Folder:** [./tracks/generator-external-files_20260405/](./tracks/generator-external-files_20260405/)

---

### [x] example-package_20260405: dartdata_example Integration Package

**Description:** End-to-end integration package demonstrating dartdata usage
**Priority:** medium
**Folder:** [./tracks/example-package_20260405/](./tracks/example-package_20260405/)

---

## Archived Tracks

<!-- Archived tracks are moved here with reason and date -->

| Track ID | Type | Reason | Archived | Folder |
| -------- | ---- | ------ | -------- | ------ |

---

## Notes

- Track IDs use format `{shortname}_{YYYYMMDD}`
- Tiers: 1 Core Runtime → 2 Code Generator → 3 Flutter Integration → 4 Production Readiness → 5 Integration Testing → 6 Schema Correctness
- Archive completed tracks quarterly
