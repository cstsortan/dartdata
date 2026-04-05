# z_pk Integer Foreign Key Resolution — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make FK columns store `z_pk` integers instead of UUID strings, aligning with CLAUDE.md and real SwiftData schema.

**Architecture:** Add `getRelationshipIds()` to `ModelDescriptor` so descriptors can report related object UUIDs without knowing about z_pk. `ModelContext` resolves each UUID → z_pk via SQL lookup and injects the integer into the map before executing INSERT/UPDATE. Delete rules and `fetchRelated` also resolve parent UUID �� z_pk before querying children.

**Tech Stack:** Dart, Flutter, SQLite (via `sqlite3` FFI), `source_gen`/`build_runner`

**Spec:** `docs/superpowers/specs/2026-04-05-zpk-integer-fk-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Modify | `dartdata/lib/src/schema/schema.dart:82-108` | Add `getRelationshipIds()` to `ModelDescriptor` |
| Modify | `dartdata/lib/src/context/model_context.dart:109-157` | FK resolution in `_execute()` |
| Modify | `dartdata/lib/src/context/model_context.dart:245-273` | FK resolution in `fetchRelated()` |
| Modify | `dartdata/lib/src/context/model_context.dart:425-495` | FK resolution in delete rules |
| Modify | `dartdata/test/helpers/test_models.dart` | Update models to object refs + integer FK columns |
| Modify | `dartdata/test/relationship_test.dart` | Update tests for object refs + z_pk integers |
| Modify | `dartdata_generator/lib/src/model_generator.dart:93-111` | Generator: null FKs in toMap, getRelationshipIds |
| Modify | `dartdata_generator/lib/src/model_generator.dart:393-397` | Generator: ColumnType.integer for FKs |
| Modify | `dartdata_example/lib/src/models/*.g.dart` (5 files) | Regenerate with integer FK columns |
| Modify | `dartdata_example/test/relationship_test.dart` | Update assertions for z_pk integers |
| Modify | `dartdata_example/test/crud_test.dart` | Update FK-related CRUD tests |
| Modify | `dartdata_example/test/container_test.dart` | Update column type assertions if any |

---

### Task 1: Add `getRelationshipIds()` to `ModelDescriptor`

**Files:**
- Modify: `dartdata/lib/src/schema/schema.dart:82-108`

- [ ] **Step 1: Add the method to ModelDescriptor**

In `dartdata/lib/src/schema/schema.dart`, add after the `getExternalFile` method (line 107):

```dart
  /// Returns FK column names mapped to the related object's UUID string.
  /// ModelContext resolves each UUID to the related row's z_pk integer.
  /// Override in descriptors with FK-side relationships.
  Map<String, String?> getRelationshipIds(Object model) => const {};
```

- [ ] **Step 2: Verify existing tests still pass**

Run: `cd dartdata && flutter test`
Expected: All existing tests pass (no descriptor implements the method yet, and the default returns empty map).

- [ ] **Step 3: Commit**

```bash
git add dartdata/lib/src/schema/schema.dart
git commit -m "feat(schema): add getRelationshipIds() to ModelDescriptor"
```

---

### Task 2: Update hand-written test models to object references + integer FK columns

**Files:**
- Modify: `dartdata/test/helpers/test_models.dart`

- [ ] **Step 1: Update BucketListItem model class**

Replace the `BucketListItem` class (lines 309-328):

```dart
class BucketListItem {
  final String id;
  String title;
  bool isInBucket;
  Trip? trip; // object reference instead of String? tripId

  BucketListItem({
    required this.id,
    required this.title,
    this.isInBucket = false,
    this.trip,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'is_in_bucket': isInBucket ? 1 : 0,
        'trip_id': null, // resolved by ModelContext
      };
}
```

- [ ] **Step 2: Update BucketListItemDescriptor**

Change FK column type from `ColumnType.text` to `ColumnType.integer` (line 356), update `fromMap` to not read `trip_id`, and add `getRelationshipIds` override:

```dart
class BucketListItemDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'bucket_list_item';

  @override
  String get modelClassName => 'BucketListItem';

  @override
  Type get modelType => BucketListItem;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'title', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'is_in_bucket', type: ColumnType.integer),
        const ColumnDefinition(
            columnName: 'trip_id', type: ColumnType.integer, isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [
        const RelationshipDefinition(
          fieldName: 'trip',
          relatedTable: 'trip',
          cardinality: RelationshipCardinality.toOne,
          inverseFieldName: 'bucketList',
          deleteRule: DeleteRule.cascade,
          fkColumnName: 'trip_id',
          isForeignKeySide: true,
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  BucketListItem fromMap(Map<String, Object?> row) => BucketListItem(
        id: row['id'] as String,
        title: row['title'] as String,
        isInBucket: (row['is_in_bucket'] as int) == 1,
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as BucketListItem;
    return m.toMap();
  }

  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as BucketListItem;
    return {'trip_id': m.trip?.id};
  }
}
```

- [ ] **Step 3: Update SubItem model class**

Replace the `SubItem` class (lines 394-410):

```dart
class SubItem {
  final String id;
  String note;
  BucketListItem? bucketListItem;

  SubItem({
    required this.id,
    required this.note,
    this.bucketListItem,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'note': note,
        'bucket_list_item_id': null, // resolved by ModelContext
      };
}
```

- [ ] **Step 4: Update SubItemDescriptor**

Change FK column to `ColumnType.integer`, update `fromMap`, add `getRelationshipIds`:

```dart
class SubItemDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'sub_item';

  @override
  String get modelClassName => 'SubItem';

  @override
  Type get modelType => SubItem;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'note', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'bucket_list_item_id',
            type: ColumnType.integer,
            isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [
        const RelationshipDefinition(
          fieldName: 'bucket_list_item',
          relatedTable: 'bucket_list_item',
          cardinality: RelationshipCardinality.toOne,
          inverseFieldName: 'subItems',
          deleteRule: DeleteRule.cascade,
          fkColumnName: 'bucket_list_item_id',
          isForeignKeySide: true,
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  SubItem fromMap(Map<String, Object?> row) => SubItem(
        id: row['id'] as String,
        note: row['note'] as String,
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as SubItem;
    return m.toMap();
  }

  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as SubItem;
    return {'bucket_list_item_id': m.bucketListItem?.id};
  }
}
```

- [ ] **Step 5: Update LivingAccommodation model class**

Replace the `LivingAccommodation` class (lines 582-598):

```dart
class LivingAccommodation {
  final String id;
  String address;
  Trip? trip; // object reference instead of String? tripId

  LivingAccommodation({
    required this.id,
    required this.address,
    this.trip,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'address': address,
        'trip_id': null, // resolved by ModelContext
      };
}
```

- [ ] **Step 6: Update LivingAccommodationDescriptor**

Change FK column to `ColumnType.integer`, update `fromMap`, add `getRelationshipIds`:

```dart
class LivingAccommodationDescriptor extends ModelDescriptor {
  @override
  String get tableName => 'living_accommodation';

  @override
  String get modelClassName => 'LivingAccommodation';

  @override
  Type get modelType => LivingAccommodation;

  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'address', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'trip_id', type: ColumnType.integer, isNullable: true),
      ];

  @override
  List<RelationshipDefinition> get relationships => [
        const RelationshipDefinition(
          fieldName: 'trip',
          relatedTable: 'trip',
          cardinality: RelationshipCardinality.toOne,
          deleteRule: DeleteRule.nullify,
          fkColumnName: 'trip_id',
          isForeignKeySide: true,
        ),
      ];

  @override
  List<String> get externalFileFields => [];

  @override
  LivingAccommodation fromMap(Map<String, Object?> row) => LivingAccommodation(
        id: row['id'] as String,
        address: row['address'] as String,
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as LivingAccommodation;
    return m.toMap();
  }

  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as LivingAccommodation;
    return {'trip_id': m.trip?.id};
  }
}
```

- [ ] **Step 7: Update DenyBucketListItemDescriptor and NoActionBucketListItemDescriptor**

Apply the same changes as `BucketListItemDescriptor` to both variants: `ColumnType.integer` for `trip_id`, updated `fromMap` (no `tripId`), and `getRelationshipIds` override. The only difference is the `deleteRule` field.

For `DenyBucketListItemDescriptor`:
```dart
  @override
  List<ColumnDefinition> get columns => [
        const ColumnDefinition(
            columnName: 'id',
            type: ColumnType.text,
            isPrimaryKey: true,
            isNullable: false),
        const ColumnDefinition(columnName: 'title', type: ColumnType.text),
        const ColumnDefinition(
            columnName: 'is_in_bucket', type: ColumnType.integer),
        const ColumnDefinition(
            columnName: 'trip_id', type: ColumnType.integer, isNullable: true),
      ];

  // ... relationships unchanged (deleteRule: DeleteRule.deny) ...

  @override
  BucketListItem fromMap(Map<String, Object?> row) => BucketListItem(
        id: row['id'] as String,
        title: row['title'] as String,
        isInBucket: (row['is_in_bucket'] as int) == 1,
      );

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as BucketListItem;
    return m.toMap();
  }

  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as BucketListItem;
    return {'trip_id': m.trip?.id};
  }
```

Apply identical changes to `NoActionBucketListItemDescriptor`.

- [ ] **Step 8: Update `$BucketListItem` and `$LivingAccommodation` QueryField statics**

`$BucketListItem.tripId` uses `QueryField<String>('trip_id')` — this should become `QueryField<int>('trip_id')` since the column is now integer:

```dart
abstract class $BucketListItem {
  static final title = QueryField<String>('title');
  static final tripId = QueryField<int>('trip_id');
}
```

```dart
abstract class $LivingAccommodation {
  static final address = QueryField<String>('address');
  static final tripId = QueryField<int>('trip_id');
}
```

- [ ] **Step 9: Verify compilation**

Run: `cd dartdata && flutter test --no-execute`
Expected: Compilation succeeds (tests will fail at runtime until ModelContext is updated).

- [ ] **Step 10: Commit**

```bash
git add dartdata/test/helpers/test_models.dart
git commit -m "refactor(test-models): use object refs and integer FK columns"
```

---

### Task 3: Add FK resolution to `ModelContext._execute()`

**Files:**
- Modify: `dartdata/lib/src/context/model_context.dart:109-157`

- [ ] **Step 1: Write failing test for FK z_pk resolution on insert**

In `dartdata/test/relationship_test.dart`, the existing test at line 71 (`BucketListItem FK matches Trip id after insert + save`) currently uses `tripId: 'trip-1'`. Update it to use object references and verify z_pk:

```dart
    test('BucketListItem FK stores Trip z_pk integer after insert + save', () async {
      final trip = Trip(
        id: 'trip-1',
        name: 'Grand Tour',
        destination: 'Europe',
        startDate: DateTime.utc(2026, 6, 1),
        endDate: DateTime.utc(2026, 8, 31),
      );
      context.insert(trip);
      await context.save();

      final item = BucketListItem(
        id: 'bli-1',
        title: 'See Eiffel Tower',
        trip: trip,
      );
      context.insert(item);
      await context.save();

      // Verify FK column stores z_pk integer, not UUID string.
      final rows = container.db.select(
        "SELECT trip_id FROM bucket_list_item WHERE id = 'bli-1'",
      );
      final fkValue = rows.first['trip_id'];
      expect(fkValue, isA<int>());

      // Verify it matches the Trip's z_pk.
      final tripZpk = container.db.select(
        "SELECT z_pk FROM trip WHERE id = 'trip-1'",
      ).first['z_pk'] as int;
      expect(fkValue, equals(tripZpk));
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dartdata && flutter test test/relationship_test.dart --name "BucketListItem FK stores Trip z_pk"`
Expected: FAIL — FK column stores NULL because `toMap` returns null for `trip_id` and ModelContext doesn't resolve it yet.

- [ ] **Step 3: Implement `_resolveRelationshipFks` in ModelContext**

In `dartdata/lib/src/context/model_context.dart`, add a new private method after `_resolveExternalFilePaths` (after line 400):

```dart
  /// Resolve FK columns from UUID strings to z_pk integers.
  ///
  /// Uses [descriptor.getRelationshipIds] to get the related object's UUID,
  /// then looks up its z_pk in the database. Injects the integer into [map].
  void _resolveRelationshipFks(
    Object model,
    ModelDescriptor descriptor,
    Map<String, Object?> map,
  ) {
    final fkIds = descriptor.getRelationshipIds(model);
    if (fkIds.isEmpty) return;

    // Build a lookup from fkColumnName → relatedTable.
    final fkToTable = <String, String>{};
    for (final rel in descriptor.relationships) {
      if (rel.isForeignKeySide && rel.fkColumnName != null) {
        fkToTable[rel.fkColumnName!] = rel.relatedTable;
      }
    }

    for (final entry in fkIds.entries) {
      final fkColumn = entry.key;
      final relatedUuid = entry.value;
      if (relatedUuid == null) {
        map[fkColumn] = null;
        continue;
      }

      final relatedTable = fkToTable[fkColumn];
      if (relatedTable == null) {
        throw StateError(
          'No relationship found for FK column "$fkColumn" on '
          '${descriptor.modelClassName}',
        );
      }

      final rows = container.db.select(
        'SELECT z_pk FROM $relatedTable WHERE id = ?',
        [relatedUuid],
      );
      if (rows.isEmpty) {
        throw StateError(
          "Cannot resolve z_pk for $relatedTable with id '$relatedUuid'. "
          'The related object must be saved before referencing it.',
        );
      }
      map[fkColumn] = rows.first['z_pk'] as int;
    }
  }
```

- [ ] **Step 4: Call `_resolveRelationshipFks` in `_execute`**

In `_execute()`, add the call after `_persistExternalFiles` and before the optimistic lock check. At line 127, after `await _persistExternalFiles(op.model, descriptor, map);`:

```dart
        await _persistExternalFiles(op.model, descriptor, map);

        // Resolve FK columns from UUID strings to z_pk integers.
        _resolveRelationshipFks(op.model, descriptor, map);
```

Also add the same call in the `_OperationType.update` case, after `_persistExternalFiles` at line 170:

```dart
      case _OperationType.update:
        await _persistExternalFiles(op.model, descriptor, map);
        _resolveRelationshipFks(op.model, descriptor, map);
```

- [ ] **Step 5: Run the failing test**

Run: `cd dartdata && flutter test test/relationship_test.dart --name "BucketListItem FK stores Trip z_pk"`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add dartdata/lib/src/context/model_context.dart
git commit -m "feat(context): resolve FK UUIDs to z_pk integers on insert/update"
```

---

### Task 4: Update delete rules and `fetchRelated` to use z_pk

**Files:**
- Modify: `dartdata/lib/src/context/model_context.dart:245-273,425-495`

- [ ] **Step 1: Write failing test for cascade delete with z_pk FKs**

Update the existing cascade test in `dartdata/test/relationship_test.dart` (line 103) to use object references:

```dart
    test(
      'deleting a Trip cascades to its BucketListItems',
      () async {
        final trip = Trip(
          id: 'trip-cascade',
          name: 'Cascade Trip',
          destination: 'X',
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 2),
        );
        context.insert(trip);
        await context.save();

        context.insert(BucketListItem(
            id: 'bli-c1', title: 'Item 1', trip: trip));
        context.insert(BucketListItem(
            id: 'bli-c2', title: 'Item 2', trip: trip));
        await context.save();

        context.delete(trip);
        await context.save();

        // After cascade, BucketListItems should also be gone.
        final items = await context.fetch(Query<BucketListItem>());
        expect(items, isEmpty);
      },
    );
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd dartdata && flutter test test/relationship_test.dart --name "deleting a Trip cascades"`
Expected: FAIL — `_enforceDeleteRules` queries `WHERE trip_id = 'trip-cascade'` (UUID string) but the column now stores z_pk integers, so no children are found.

- [ ] **Step 3: Add `_resolveZpk` helper to ModelContext**

Add a helper that resolves a model's UUID to its z_pk. Place it near `_resolveRelationshipFks`:

```dart
  /// Look up the z_pk for [tableName] where id = [uuid].
  /// Returns the integer z_pk, or throws if not found.
  int _resolveZpk(String tableName, String uuid) {
    final rows = container.db.select(
      'SELECT z_pk FROM $tableName WHERE id = ?',
      [uuid],
    );
    if (rows.isEmpty) {
      throw StateError(
        "Cannot resolve z_pk for $tableName with id '$uuid'.",
      );
    }
    return rows.first['z_pk'] as int;
  }
```

Then simplify `_resolveRelationshipFks` to use it — replace the inline SELECT with:

```dart
      map[fkColumn] = _resolveZpk(relatedTable, relatedUuid);
```

- [ ] **Step 4: Update `_enforceDeleteRules` to use z_pk**

Replace lines 436-438 in `_enforceDeleteRules`:

```dart
      final parentDescriptor = _descriptorFor(op.model);
      final parentMap = parentDescriptor.toMap(op.model);
      final parentId = parentMap['id'] as String;
```

With:

```dart
      final parentDescriptor = _descriptorFor(op.model);
      final parentMap = parentDescriptor.toMap(op.model);
      final parentId = parentMap['id'] as String;
      final parentZpk = _resolveZpk(parentDescriptor.tableName, parentId);
```

Then update the three usages below to pass `parentZpk` instead of `parentId`:

```dart
        switch (child.deleteRule) {
          case DeleteRule.cascade:
            _cascadeDelete(child.descriptor, fkColumn, parentZpk);
          case DeleteRule.nullify:
            deferredSql.add(_DeferredSql(
              'UPDATE ${child.descriptor.tableName} SET $fkColumn = NULL WHERE $fkColumn = ?',
              [parentZpk],
            ));
          case DeleteRule.deny:
            _denyDelete(child.descriptor, fkColumn, parentZpk);
          case DeleteRule.noAction:
            break;
        }
```

- [ ] **Step 5: Update `_cascadeDelete` and `_denyDelete` signatures**

Change parameter type from `String parentId` to `int parentZpk`:

```dart
  void _cascadeDelete(
    ModelDescriptor childDescriptor,
    String fkColumn,
    int parentZpk,
  ) {
    final rows = container.db.select(
      'SELECT * FROM ${childDescriptor.tableName} WHERE $fkColumn = ?',
      [parentZpk],
    );

    for (final row in rows) {
      final resolved = _resolveExternalFilePaths(row, childDescriptor);
      final childModel = childDescriptor.fromMap(resolved);
      _pending.add(_PendingOperation(_OperationType.delete, childModel));
    }
  }

  void _denyDelete(
    ModelDescriptor childDescriptor,
    String fkColumn,
    int parentZpk,
  ) {
    final row = container.db.select(
      'SELECT COUNT(*) as c FROM ${childDescriptor.tableName} WHERE $fkColumn = ?',
      [parentZpk],
    );
    final count = row.first['c'] as int;
    if (count > 0) {
      throw StateError(
        'Cannot delete: $count related row(s) exist in '
        '${childDescriptor.tableName} (delete rule: deny)',
      );
    }
  }
```

- [ ] **Step 6: Update `fetchRelated` to use z_pk**

In `fetchRelated` (line 245-278), replace the UUID-based query with z_pk:

```dart
  Future<List<T>> fetchRelated<T>(Object model, String relationshipField) async {
    final parentDescriptor = _descriptorFor(model);
    final parentMap = parentDescriptor.toMap(model);
    final parentId = parentMap['id'] as String;
    final parentZpk = _resolveZpk(parentDescriptor.tableName, parentId);

    // Find the relationship on the parent descriptor.
    final parentRel = parentDescriptor.relationships.firstWhere(
      (r) => r.fieldName == relationshipField,
      orElse: () => throw StateError(
        'No relationship "$relationshipField" on ${parentDescriptor.modelClassName}',
      ),
    );

    // Find the child descriptor for the related table.
    final childDescriptor = container.schema.descriptors.firstWhere(
      (d) => d.tableName == parentRel.relatedTable,
      orElse: () => throw StateError(
        'No descriptor for table "${parentRel.relatedTable}"',
      ),
    );

    // Use explicit fkColumnName, or fall back to convention.
    final fkColumn = parentRel.fkColumnName ??
        '${parentRel.inverseFieldName ?? parentDescriptor.tableName}_id';

    final rows = container.db.select(
      'SELECT * FROM ${childDescriptor.tableName} WHERE $fkColumn = ?',
      [parentZpk],
    );

    return rows.map((row) {
      final resolved = _resolveExternalFilePaths(row, childDescriptor);
      return childDescriptor.fromMap(resolved) as T;
    }).toList();
  }
```

- [ ] **Step 7: Run cascade test**

Run: `cd dartdata && flutter test test/relationship_test.dart --name "deleting a Trip cascades"`
Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add dartdata/lib/src/context/model_context.dart
git commit -m "feat(context): use z_pk integers for delete rules and fetchRelated"
```

---

### Task 5: Update all relationship tests for object references

**Files:**
- Modify: `dartdata/test/relationship_test.dart`

- [ ] **Step 1: Update all remaining tests to use object references**

Every test that creates `BucketListItem`, `SubItem`, or `LivingAccommodation` with `tripId:` or `bucketListItemId:` must change to use `trip:` or `bucketListItem:` object references. Also, parent must be saved before children reference it.

Update the nullify test (line 135):
```dart
    test(
      'deleting a Trip nullifies LivingAccommodation FK',
      () async {
        final trip = Trip(
          id: 'trip-nullify',
          name: 'Nullify Trip',
          destination: 'Y',
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 2),
        );
        context.insert(trip);
        await context.save();

        context.insert(LivingAccommodation(
            id: 'acc-1', address: '123 Main St', trip: trip));
        await context.save();

        context.delete(trip);
        await context.save();

        final accommodations =
            await context.fetch(Query<LivingAccommodation>());
        expect(accommodations.length, equals(1));
        // tripId field is no longer on the model — verify via raw SQL.
        final rows = container.db.select(
          "SELECT trip_id FROM living_accommodation WHERE id = 'acc-1'",
        );
        expect(rows.first['trip_id'], isNull);
      },
    );
```

Update the deny test (line 167):
```dart
    test(
      'deleting a Trip with related BucketListItems throws StateError',
      () async {
        final denyContainer = await ModelContainer.create(
          schema: Schema([
            TripDescriptor(),
            DenyBucketListItemDescriptor(),
          ]),
          configuration: const ModelConfiguration.inMemory(),
        );
        final denyContext = ModelContext(denyContainer);

        final trip = Trip(
          id: 'trip-deny',
          name: 'Deny Trip',
          destination: 'Z',
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 2),
        );
        denyContext.insert(trip);
        await denyContext.save();

        denyContext.insert(BucketListItem(
            id: 'bli-d1', title: 'Block delete', trip: trip));
        await denyContext.save();

        denyContext.delete(trip);
        expect(() async => await denyContext.save(), throwsStateError);

        denyContainer.close();
      },
    );
```

Update the noAction test (line 204):
```dart
    test(
      'deleting a Trip leaves orphaned BucketListItems with stale FK',
      () async {
        final noActionContainer = await ModelContainer.create(
          schema: Schema([
            TripDescriptor(),
            NoActionBucketListItemDescriptor(),
          ]),
          configuration: const ModelConfiguration.inMemory(),
        );
        final noActionContext = ModelContext(noActionContainer);

        final trip = Trip(
          id: 'trip-noaction',
          name: 'NoAction Trip',
          destination: 'W',
          startDate: DateTime.utc(2026, 1, 1),
          endDate: DateTime.utc(2026, 1, 2),
        );
        noActionContext.insert(trip);
        await noActionContext.save();

        noActionContext.insert(BucketListItem(
            id: 'bli-na1', title: 'Orphan Item', trip: trip));
        await noActionContext.save();

        noActionContext.delete(trip);
        await noActionContext.save();

        final trips = await noActionContext.fetch(Query<Trip>());
        expect(trips, isEmpty);

        // BucketListItem still exists — FK is a stale z_pk integer.
        final items = await noActionContext.fetch(Query<BucketListItem>());
        expect(items.length, equals(1));

        noActionContainer.close();
      },
    );
```

Update the one-to-one optional tests (line 250):
```dart
    test('LivingAccommodation with null trip stores NULL FK', () async {
      context.insert(LivingAccommodation(
        id: 'acc-orphan',
        address: '456 Elm St',
        trip: null,
      ));
      await context.save();

      final rows = container.db.select(
        "SELECT trip_id FROM living_accommodation WHERE id = 'acc-orphan'",
      );
      expect(rows.first['trip_id'], isNull);
    });

    test('LivingAccommodation with trip stores z_pk FK value', () async {
      final trip = Trip(
        id: 'trip-opt',
        name: 'Optional Trip',
        destination: 'W',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      context.insert(trip);
      await context.save();

      context.insert(LivingAccommodation(
        id: 'acc-linked',
        address: '789 Oak Ave',
        trip: trip,
      ));
      await context.save();

      final rows = container.db.select(
        "SELECT trip_id FROM living_accommodation WHERE id = 'acc-linked'",
      );
      final fkValue = rows.first['trip_id'];
      expect(fkValue, isA<int>());

      final tripZpk = container.db.select(
        "SELECT z_pk FROM trip WHERE id = 'trip-opt'",
      ).first['z_pk'] as int;
      expect(fkValue, equals(tripZpk));
    });
```

Update fetchRelated tests (line 292) — use `trip:` instead of `tripId:`:
```dart
      context.insert(BucketListItem(
          id: 'bli-f1', title: 'Item 1', trip: trip));
      context.insert(BucketListItem(
          id: 'bli-f2', title: 'Item 2', trip: trip));
```

Note: the `bli-other` item in the fetchRelated test references `'other-trip'` which doesn't exist. With z_pk resolution, this will throw. Change it to either use a second trip object or remove it:

```dart
      final otherTrip = Trip(
        id: 'other-trip',
        name: 'Other Trip',
        destination: 'B',
        startDate: DateTime.utc(2026, 1, 1),
        endDate: DateTime.utc(2026, 1, 2),
      );
      context.insert(otherTrip);
      // ...
      context.insert(BucketListItem(
          id: 'bli-other', title: 'Other Item', trip: otherTrip));
```

Save parent before children in each test:
```dart
      context.insert(trip);
      await context.save();

      context.insert(BucketListItem(..., trip: trip));
      await context.save();
```

Update the LivingAccommodation fetchRelated test similarly.

Update the nested cascade test (line 356):
```dart
      ctx.insert(trip);
      await ctx.save();

      final bli = BucketListItem(
          id: 'bli-n1', title: 'Parent Item', trip: trip);
      ctx.insert(bli);
      await ctx.save();

      ctx.insert(SubItem(
          id: 'sub-1', note: 'Sub note', bucketListItem: bli));
      await ctx.save();
```

Update the deny+rollback test (line 414) similarly.

- [ ] **Step 2: Run all relationship tests**

Run: `cd dartdata && flutter test test/relationship_test.dart`
Expected: All tests PASS.

- [ ] **Step 3: Run full test suite**

Run: `cd dartdata && flutter test`
Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add dartdata/test/relationship_test.dart
git commit -m "test: update relationship tests to use object refs and z_pk integers"
```

---

### Task 6: Update the generator for integer FK columns

**Files:**
- Modify: `dartdata_generator/lib/src/model_generator.dart`

- [ ] **Step 1: Revert `fkColumnDefinition` to `ColumnType.integer`**

In `dartdata_generator/lib/src/model_generator.dart`, line 394, change:

```dart
    return "ColumnDefinition(columnName: '$fkColumnName', type: ColumnType.text, "
```

To:

```dart
    return "ColumnDefinition(columnName: '$fkColumnName', type: ColumnType.integer, "
```

- [ ] **Step 2: Change `toMap()` to emit null for FK columns**

At line 107, replace:

```dart
${relationships.where((r) => r.cardinality == RelationshipCardinality.toOne).map((r) => "      '${r.fkColumnName}': m.${r.fieldName}${r.isNullable ? '?' : ''}.id,").join('\n')}
```

With:

```dart
${relationships.where((r) => r.cardinality == RelationshipCardinality.toOne).map((r) => "      '${r.fkColumnName}': null, // FK resolved by ModelContext").join('\n')}
```

- [ ] **Step 3: Add `_generateGetRelationshipIds` method**

Add a new static method after `_generateGetExternalFile` (after line 160):

```dart
  static String _generateGetRelationshipIds(
      String className, List<_RelationshipInfo> relationships) {
    final fkRels = relationships
        .where((r) => r.cardinality == RelationshipCardinality.toOne)
        .toList();
    if (fkRels.isEmpty) return '';
    final entries = fkRels
        .map((r) =>
            "      '${r.fkColumnName}': m.${r.fieldName}${r.isNullable ? '?' : ''}.id,")
        .join('\n');
    return '''

  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as $className;
    return {
$entries
    };
  }''';
  }
```

- [ ] **Step 4: Emit `getRelationshipIds` in the descriptor class**

At line 110, after `${_generateGetExternalFile(className, fields)}`, add:

```dart
${_generateGetRelationshipIds(className, relationships)}
```

So the descriptor body becomes:

```dart
${_generateGetExternalFile(className, fields)}
${_generateGetRelationshipIds(className, relationships)}
}
```

- [ ] **Step 5: Verify generator compiles**

Run: `cd dartdata_generator && dart analyze`
Expected: No errors.

- [ ] **Step 6: Commit**

```bash
git add dartdata_generator/lib/src/model_generator.dart
git commit -m "feat(generator): emit integer FK columns, null in toMap, getRelationshipIds"
```

---

### Task 7: Update generated `.g.dart` files in dartdata_example

**Files:**
- Modify: `dartdata_example/lib/src/models/attachment.g.dart`
- Modify: `dartdata_example/lib/src/models/category.g.dart`
- Modify: `dartdata_example/lib/src/models/comment.g.dart`
- Modify: `dartdata_example/lib/src/models/post.g.dart`
- Modify: `dartdata_example/lib/src/models/post_tag.g.dart`

These files are hand-committed generated output. Update each one to match the new generator output.

- [ ] **Step 1: Update each `.g.dart` file**

For each of the 5 files, apply three changes:

**a) FK column type: `ColumnType.text` → `ColumnType.integer`**

Example in `comment.g.dart`:
```dart
    // Before:
    ColumnDefinition(columnName: 'post_id', type: ColumnType.text, ...),
    // After:
    ColumnDefinition(columnName: 'post_id', type: ColumnType.integer, ...),
```

**b) `toMap()`: FK value → null**

Example in `comment.g.dart`:
```dart
    // Before:
    'post_id': m.post?.id,
    // After:
    'post_id': null, // FK resolved by ModelContext
```

**c) Add `getRelationshipIds()` override**

Example in `comment.g.dart`:
```dart
  @override
  Map<String, String?> getRelationshipIds(Object model) {
    final m = model as Comment;
    return {
      'post_id': m.post?.id,
    };
  }
```

Apply to all 5 files:
- `attachment.g.dart`: `post_id` FK
- `category.g.dart`: `post_id` FK
- `comment.g.dart`: `post_id` FK
- `post.g.dart`: `author_id` FK
- `post_tag.g.dart`: `post_id` and `tag_id` FKs

- [ ] **Step 2: Verify compilation**

Run: `cd dartdata_example && dart analyze`
Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add dartdata_example/lib/src/models/attachment.g.dart \
       dartdata_example/lib/src/models/category.g.dart \
       dartdata_example/lib/src/models/comment.g.dart \
       dartdata_example/lib/src/models/post.g.dart \
       dartdata_example/lib/src/models/post_tag.g.dart
git commit -m "refactor(example): update generated files with integer FK columns and getRelationshipIds"
```

---

### Task 8: Update dartdata_example tests for z_pk integers

**Files:**
- Modify: `dartdata_example/test/relationship_test.dart`
- Modify: `dartdata_example/test/crud_test.dart`
- Modify: `dartdata_example/test/container_test.dart`

- [ ] **Step 1: Update relationship_test.dart**

All raw SQL assertions that check FK values must expect integers, not UUID strings. For example:

```dart
    // Before:
    expect(raw.first['post_id'], 'p1');
    // After:
    final postZpk = container.db.select(
      "SELECT z_pk FROM post WHERE id = 'p1'",
    ).first['z_pk'] as int;
    expect(raw.first['post_id'], postZpk);
```

Also ensure parents are saved before children in every test.

- [ ] **Step 2: Update crud_test.dart**

Any test that inserts a model with a relationship and checks raw FK values must be updated to expect integers. Tests that only use the ORM API (insert/fetch without raw SQL checks) should still pass — just ensure parent-before-child save ordering.

- [ ] **Step 3: Update container_test.dart**

If any test checks FK column types via `PRAGMA table_info`, update the expected type from `TEXT` to `INTEGER`.

- [ ] **Step 4: Run dartdata_example test suite**

Run: `cd dartdata_example && dart test`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add dartdata_example/test/relationship_test.dart \
       dartdata_example/test/crud_test.dart \
       dartdata_example/test/container_test.dart
git commit -m "test(example): update tests for z_pk integer FK values"
```

---

### Task 9: Run full test suite and verify

**Files:** None (verification only)

- [ ] **Step 1: Run dartdata tests**

Run: `cd dartdata && flutter test`
Expected: All tests PASS.

- [ ] **Step 2: Run dartdata_example tests**

Run: `cd dartdata_example && dart test`
Expected: All tests PASS.

- [ ] **Step 3: Verify no UUID strings in FK columns via raw SQL spot-check**

In a quick ad-hoc test or by adding a temporary assertion: insert a parent and child, then query the FK column and assert it's an integer, not a string.

- [ ] **Step 4: Final commit if any fixups needed**

```bash
git add -A
git commit -m "fix: address any remaining z_pk FK issues"
```
