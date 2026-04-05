import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:dartdata_generator/src/model_generator.dart';
import 'package:source_gen/source_gen.dart';
import 'package:test/test.dart';

/// Resolves [source] as a Dart library and returns the [ClassElement] named
/// [className]. The source string should import the annotation-only parts of
/// dartdata (no Flutter dependency).
Future<ClassElement> _resolveClass(String source, String className) async {
  late ClassElement result;
  await resolveSources(
    {
      'dartdata|lib/src/annotations/model.dart': useAssetReader,
      'dartdata|lib/src/annotations/relationship.dart': useAssetReader,
      'dartdata|lib/src/schema/schema.dart': useAssetReader,
      'dartdata|lib/src/storage/external_file.dart': useAssetReader,
      'dartdata|lib/dartdata.dart': useAssetReader,
      'test_lib|lib/model.dart': source,
    },
    (resolver) async {
      final lib = await resolver.libraryFor(
        AssetId('test_lib', 'lib/model.dart'),
      );
      result = lib.getClass(className)!;
    },
  );
  return result;
}

/// Runs the [ModelGenerator] on [classElement] and returns the generated code.
String _generate(ClassElement classElement) {
  final generator = ModelGenerator();
  return generator.generateForAnnotatedElement(
    classElement,
    // The @model ConstantReader is not used for field processing.
    ConstantReader(null),
    // BuildStep is not used by this generator.
    _FakeBuildStep(),
  );
}

void main() {
  // -------------------------------------------------------------------------
  // Phase 1: Annotation Reading Infrastructure
  // -------------------------------------------------------------------------

  group('Phase 1: annotation reading infrastructure', () {
    test('1.1: @attribute(primaryKey: true) sets isPrimaryKey in ColumnDefinition',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';

        @model
        class Foo {
          @attribute(primaryKey: true)
          final String id;

          String name;

          Foo({required this.id, required this.name});
        }
        ''',
        'Foo',
      );

      final output = _generate(cls);

      // The 'id' column should have isPrimaryKey: true
      expect(output, contains('isPrimaryKey: true'));
      // The 'name' column should have isPrimaryKey: false (default)
      expect(
        output,
        contains(RegExp(
            r"columnName: 'name'.*isPrimaryKey: false",
        )),
      );
    });

    test('1.3: field without @attribute uses defaults (all flags false, snake_case)',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';

        @model
        class Bar {
          final String id;
          String firstName;

          Bar({required this.id, required this.firstName});
        }
        ''',
        'Bar',
      );

      final output = _generate(cls);

      // Should use snake_case column name
      expect(output, contains("columnName: 'first_name'"));
      // All flags should be false
      expect(output, contains('isPrimaryKey: false'));
      expect(output, contains('isUnique: false'));
      expect(output, contains('isIndexed: false'));
    });
  });

  // -------------------------------------------------------------------------
  // Phase 2: Individual Attribute Parameters
  // -------------------------------------------------------------------------

  group('Phase 2: individual attribute parameters', () {
    test('2.1: @attribute(unique: true) sets isUnique', () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';

        @model
        class Item {
          final String id;
          @attribute(unique: true)
          String email;

          Item({required this.id, required this.email});
        }
        ''',
        'Item',
      );

      final output = _generate(cls);

      // email column should have isUnique: true
      expect(
        output,
        contains(RegExp(r"columnName: 'email'.*isUnique: true")),
      );
    });

    test('2.3: @attribute(indexed: true) sets isIndexed', () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';

        @model
        class Item {
          final String id;
          @attribute(indexed: true)
          String category;

          Item({required this.id, required this.category});
        }
        ''',
        'Item',
      );

      final output = _generate(cls);

      expect(
        output,
        contains(RegExp(r"columnName: 'category'.*isIndexed: true")),
      );
    });

    test('2.5: @attribute(columnName: "custom_col") overrides column name',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';

        @model
        class Item {
          final String id;
          @attribute(columnName: 'custom_col')
          String myField;

          Item({required this.id, required this.myField});
        }
        ''',
        'Item',
      );

      final output = _generate(cls);

      // Column name should be 'custom_col', not 'my_field'
      expect(output, contains("columnName: 'custom_col'"));
      expect(output, isNot(contains("columnName: 'my_field'")));
      // QueryField should also use custom name
      expect(output, contains("QueryField<String>('custom_col')"));
    });

    test('2.7: @attribute(transient: true) excludes field entirely', () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';

        @model
        class Item {
          final String id;
          String name;
          @attribute(transient: true)
          String cached;

          Item({required this.id, required this.name, required this.cached});
        }
        ''',
        'Item',
      );

      final output = _generate(cls);

      // 'cached' should not appear in columns, toMap, or fromMap
      expect(output, isNot(contains("'cached'")));
      expect(output, contains("'name'")); // non-transient fields remain
    });
  });

  // -------------------------------------------------------------------------
  // Phase 3: Combined Annotations and Integration
  // -------------------------------------------------------------------------

  group('Phase 3: combined annotations', () {
    test('3.1: multiple flags combine correctly', () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';

        @model
        class Product {
          final String id;
          @attribute(unique: true, indexed: true)
          String sku;

          Product({required this.id, required this.sku});
        }
        ''',
        'Product',
      );

      final output = _generate(cls);

      expect(
        output,
        contains(RegExp(r"columnName: 'sku'.*isUnique: true.*isIndexed: true")),
      );
    });

    test('3.3: full model with mixed annotations', () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';

        @model
        class User {
          @attribute(primaryKey: true)
          final String id;

          String name;

          @attribute(unique: true, indexed: true)
          String email;

          @attribute(columnName: 'phone_number')
          String? phone;

          @attribute(transient: true)
          String displayName;

          User({
            required this.id,
            required this.name,
            required this.email,
            this.phone,
            required this.displayName,
          });
        }
        ''',
        'User',
      );

      final output = _generate(cls);

      // id: primaryKey
      expect(output, contains(RegExp(r"columnName: 'id'.*isPrimaryKey: true")));

      // name: all defaults
      expect(output, contains("columnName: 'name'"));

      // email: unique + indexed
      expect(
        output,
        contains(RegExp(r"columnName: 'email'.*isUnique: true.*isIndexed: true")),
      );

      // phone: custom column name
      expect(output, contains("columnName: 'phone_number'"));
      expect(output, isNot(contains("columnName: 'phone'")));

      // displayName: transient — should be absent
      expect(output, isNot(contains("'display_name'")));
      expect(output, isNot(contains("'displayName'")));

      // QueryField for phone should use custom name
      expect(output, contains("QueryField<String>('phone_number')"));
    });
  });

  // -------------------------------------------------------------------------
  // Phase 4: Relationship Emission — To-One
  // -------------------------------------------------------------------------

  group('Phase 4: to-one relationship emission', () {
    test('4.1: optional to-one @relationship produces RelationshipDefinition and FK column',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/annotations/relationship.dart';

        @model
        class LivingAccommodation {
          final String id;
          String address;
          LivingAccommodation({required this.id, required this.address});
        }

        @model
        class Trip {
          @attribute(primaryKey: true)
          final String id;
          String name;

          @relationship()
          LivingAccommodation? accommodation;

          Trip({required this.id, required this.name, this.accommodation});
        }
        ''',
        'Trip',
      );

      final output = _generate(cls);

      // Should produce a RelationshipDefinition with toOne cardinality
      expect(output, contains('RelationshipDefinition('));
      expect(output, contains("fieldName: 'accommodation'"));
      expect(output, contains("relatedTable: 'living_accommodation'"));
      expect(output, contains('cardinality: RelationshipCardinality.toOne'));

      // Should NOT include accommodation as a regular column
      // (the FK column is on this table, named accommodation_id)
      expect(output, contains("columnName: 'accommodation_id'"));
      expect(output, contains('ColumnType.integer'));
    });

    test('4.3: required to-one field emits non-nullable FK column', () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/annotations/relationship.dart';

        @model
        class Trip {
          final String id;
          String name;
          Trip({required this.id, required this.name});
        }

        @model
        class BucketListItem {
          @attribute(primaryKey: true)
          final String id;
          String title;

          @relationship()
          Trip trip;

          BucketListItem({required this.id, required this.title, required this.trip});
        }
        ''',
        'BucketListItem',
      );

      final output = _generate(cls);

      // FK column should be non-nullable for required to-one
      expect(
        output,
        contains(RegExp(r"columnName: 'trip_id'.*isNullable: false")),
      );
    });

    test('4.5: deleteRule from annotation is stored in RelationshipDefinition',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/annotations/relationship.dart';

        @model
        class Trip {
          final String id;
          String name;
          Trip({required this.id, required this.name});
        }

        @model
        class BucketListItem {
          @attribute(primaryKey: true)
          final String id;
          String title;

          @relationship(deleteRule: DeleteRule.cascade)
          Trip? trip;

          BucketListItem({required this.id, required this.title, this.trip});
        }
        ''',
        'BucketListItem',
      );

      final output = _generate(cls);

      expect(output, contains('deleteRule: DeleteRule.cascade'));
    });
  });

  // -------------------------------------------------------------------------
  // Phase 5: Relationship Emission — To-Many
  // -------------------------------------------------------------------------

  group('Phase 5: to-many relationship emission', () {
    test('5.1: List<T> field does NOT add column to parent, emits toMany RelationshipDefinition',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/annotations/relationship.dart';

        @model
        class BucketListItem {
          final String id;
          String title;
          BucketListItem({required this.id, required this.title});
        }

        @model
        class Trip {
          @attribute(primaryKey: true)
          final String id;
          String name;

          @relationship(deleteRule: DeleteRule.cascade, inverse: 'trip')
          List<BucketListItem> bucketList;

          Trip({required this.id, required this.name, required this.bucketList});
        }
        ''',
        'Trip',
      );

      final output = _generate(cls);

      // Should NOT add a bucket_list or bucket_list_id column to Trip
      expect(output, isNot(contains("columnName: 'bucket_list'")));
      expect(output, isNot(contains("columnName: 'bucket_list_id'")));

      // Should emit a toMany RelationshipDefinition
      expect(output, contains("fieldName: 'bucketList'"));
      expect(output, contains("relatedTable: 'bucket_list_item'"));
      expect(output, contains('cardinality: RelationshipCardinality.toMany'));

      // toMany side should NOT have isForeignKeySide
      expect(output, isNot(contains('isForeignKeySide: true')));
    });

    test('5.3: inverse field name is wired into RelationshipDefinition',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/annotations/relationship.dart';

        @model
        class Trip {
          final String id;
          String name;
          Trip({required this.id, required this.name});
        }

        @model
        class BucketListItem {
          @attribute(primaryKey: true)
          final String id;
          String title;

          @relationship(inverse: 'bucketList')
          Trip? trip;

          BucketListItem({required this.id, required this.title, this.trip});
        }
        ''',
        'BucketListItem',
      );

      final output = _generate(cls);

      expect(output, contains("inverseFieldName: 'bucketList'"));
      expect(output, contains("fieldName: 'trip'"));
      expect(output, contains('isForeignKeySide: true'));
    });
  });

  // -------------------------------------------------------------------------
  // Phase 6: Many-to-Many Junction Tables
  // -------------------------------------------------------------------------

  group('Phase 6: many-to-many junction tables', () {
    test('6.1: List<T> with inverse on both-sides-list generates junction table DDL',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/annotations/relationship.dart';

        @model
        class Actor {
          final String id;
          String name;

          @relationship()
          List<Movie> movies;

          Actor({required this.id, required this.name, required this.movies});
        }

        @model
        class Movie {
          @attribute(primaryKey: true)
          final String id;
          String title;

          @relationship(inverse: 'movies')
          List<Actor> actors;

          Movie({required this.id, required this.title, required this.actors});
        }
        ''',
        'Movie',
      );

      final output = _generate(cls);

      // Should generate a junction table name in alphabetical order
      expect(output, contains("'_actor_movie'"));
      // Should reference both tables
      expect(output, contains('actor_id'));
      expect(output, contains('movie_id'));
    });

    test('6.3: explicit junction model does NOT generate hidden junction table',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/annotations/relationship.dart';

        @model
        class Actor {
          final String id;
          String name;
          Actor({required this.id, required this.name});
        }

        @model
        class Movie {
          @attribute(primaryKey: true)
          final String id;
          String title;

          @relationship()
          List<MovieRole> roles;

          Movie({required this.id, required this.title, required this.roles});
        }

        @model
        class MovieRole {
          final String id;
          String characterName;

          @relationship()
          Movie? movie;

          @relationship()
          Actor? actor;

          MovieRole({required this.id, required this.characterName, this.movie, this.actor});
        }
        ''',
        'Movie',
      );

      final output = _generate(cls);

      // Should NOT contain any junction table DDL
      expect(output, isNot(contains("'_")));
    });

    test('6.5: junction table name uses alphabetical order', () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/annotations/relationship.dart';

        @model
        class Zebra {
          final String id;
          String name;

          @relationship()
          List<Apple> favoriteFruits;

          Zebra({required this.id, required this.name, required this.favoriteFruits});
        }

        @model
        class Apple {
          @attribute(primaryKey: true)
          final String id;
          String variety;

          @relationship(inverse: 'favoriteFruits')
          List<Zebra> fans;

          Apple({required this.id, required this.variety, required this.fans});
        }
        ''',
        'Apple',
      );

      final output = _generate(cls);

      // Alphabetical: apple comes before zebra
      expect(output, contains("'_apple_zebra'"));
      // Not the reverse order
      expect(output, isNot(contains("'_zebra_apple'")));
    });
  });

  // -------------------------------------------------------------------------
  // Phase 8: ExternalFile Field Handling
  // -------------------------------------------------------------------------

  group('Phase 8: ExternalFile field handling', () {
    test('8.1: ExternalFile? produces TEXT column with isNullable: true',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/storage/external_file.dart';

        @model
        class Photo {
          @attribute(primaryKey: true)
          final String id;
          String title;
          ExternalFile? imageData;

          Photo({required this.id, required this.title, this.imageData});
        }
        ''',
        'Photo',
      );

      final output = _generate(cls);

      // ExternalFile? should produce a TEXT column
      expect(
        output,
        contains(RegExp(r"columnName: 'image_data'.*type: ColumnType\.text")),
      );
      // Should be nullable
      expect(
        output,
        contains(RegExp(r"columnName: 'image_data'.*isNullable: true")),
      );
    });

    test('8.2: non-nullable ExternalFile produces isNullable: false column',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/storage/external_file.dart';

        @model
        class Document {
          @attribute(primaryKey: true)
          final String id;
          ExternalFile content;

          Document({required this.id, required this.content});
        }
        ''',
        'Document',
      );

      final output = _generate(cls);

      expect(
        output,
        contains(RegExp(r"columnName: 'content'.*isNullable: false")),
      );
    });

    test('8.3: ExternalFile fields appear in externalFileFields list',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/storage/external_file.dart';

        @model
        class Photo {
          @attribute(primaryKey: true)
          final String id;
          String title;
          ExternalFile? imageData;

          Photo({required this.id, required this.title, this.imageData});
        }
        ''',
        'Photo',
      );

      final output = _generate(cls);

      // externalFileFields should contain 'image_data'
      expect(output, contains("externalFileFields"));
      expect(
        output,
        contains(RegExp(r"externalFileFields\s*=>\s*\[\s*'image_data'")),
      );
    });

    test('8.4: ExternalFile fields do NOT generate QueryField statics',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/storage/external_file.dart';

        @model
        class Photo {
          @attribute(primaryKey: true)
          final String id;
          String title;
          ExternalFile? imageData;

          Photo({required this.id, required this.title, this.imageData});
        }
        ''',
        'Photo',
      );

      final output = _generate(cls);

      // Should have QueryField for title
      expect(output, contains("QueryField<String>('title')"));
      // Should NOT have QueryField for imageData / image_data
      expect(output, isNot(contains("imageDataField")));
      expect(output, isNot(contains("image_dataField")));
      expect(output, isNot(contains("QueryField<String>('image_data')")));
    });
  });

  // -------------------------------------------------------------------------
  // Phase 7: Integration — Mixed Relationship Types
  // -------------------------------------------------------------------------

  group('Phase 7: integration — mixed relationship types', () {
    test('7.1: full model with to-one, to-many, and m2m relationships',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/annotations/relationship.dart';

        @model
        class BucketListItem {
          final String id;
          String title;
          BucketListItem({required this.id, required this.title});
        }

        @model
        class LivingAccommodation {
          final String id;
          String address;
          LivingAccommodation({required this.id, required this.address});
        }

        @model
        class Tag {
          final String id;
          String name;
          Tag({required this.id, required this.name});
        }

        @model
        class Trip {
          @attribute(primaryKey: true)
          final String id;
          String name;
          String destination;

          @relationship(deleteRule: DeleteRule.cascade, inverse: 'trip')
          List<BucketListItem> bucketList;

          @relationship(deleteRule: DeleteRule.nullify)
          LivingAccommodation? accommodation;

          @relationship(inverse: 'trips')
          List<Tag> tags;

          Trip({
            required this.id,
            required this.name,
            required this.destination,
            required this.bucketList,
            this.accommodation,
            required this.tags,
          });
        }
        ''',
        'Trip',
      );

      final output = _generate(cls);

      // --- Regular columns (no relationship fields in columns) ---
      expect(output, contains("columnName: 'id'"));
      expect(output, contains("columnName: 'name'"));
      expect(output, contains("columnName: 'destination'"));

      // FK column for to-one accommodation
      expect(output, contains("columnName: 'accommodation_id'"));

      // No columns for to-many fields
      expect(output, isNot(contains("columnName: 'bucket_list'")));
      expect(output, isNot(contains("columnName: 'tags'")));

      // --- RelationshipDefinitions ---
      // to-many: bucketList
      expect(output, contains("fieldName: 'bucketList'"));
      expect(output, contains("relatedTable: 'bucket_list_item'"));
      expect(output, contains("inverseFieldName: 'trip'"));
      expect(output, contains('DeleteRule.cascade'));

      // to-one: accommodation
      expect(output, contains("fieldName: 'accommodation'"));
      expect(output, contains("relatedTable: 'living_accommodation'"));
      expect(output, contains('DeleteRule.nullify'));
      expect(output, contains('isForeignKeySide: true'));

      // many-to-many: tags (has inverse)
      expect(output, contains("fieldName: 'tags'"));
      expect(output, contains("relatedTable: 'tag'"));
      expect(output, contains("inverseFieldName: 'trips'"));

      // --- Junction table for tags ---
      expect(output, contains("'_tag_trip'")); // alphabetical
      expect(output, contains('tag_id'));
      expect(output, contains('trip_id'));
    });

    test('7.4: generated output structure matches hand-written test model format',
        () async {
      final cls = await _resolveClass(
        '''
        import 'package:dartdata/src/annotations/model.dart';
        import 'package:dartdata/src/annotations/relationship.dart';

        @model
        class Trip {
          final String id;
          String name;
          Trip({required this.id, required this.name});
        }

        @model
        class BucketListItem {
          @attribute(primaryKey: true)
          final String id;
          String title;

          @relationship(deleteRule: DeleteRule.cascade, inverse: 'bucketList')
          Trip? trip;

          BucketListItem({required this.id, required this.title, this.trip});
        }
        ''',
        'BucketListItem',
      );

      final output = _generate(cls);

      // Verify the structure matches hand-written BucketListItemDescriptor:
      // - Has RelationshipDefinition with fieldName, relatedTable, cardinality,
      //   inverseFieldName, deleteRule, fkColumnName, isForeignKeySide
      expect(output, contains("fieldName: 'trip'"));
      expect(output, contains("relatedTable: 'trip'"));
      expect(output, contains('RelationshipCardinality.toOne'));
      expect(output, contains("inverseFieldName: 'bucketList'"));
      expect(output, contains('DeleteRule.cascade'));
      expect(output, contains("fkColumnName: 'trip_id'"));
      expect(output, contains('isForeignKeySide: true'));

      // FK column should exist
      expect(output, contains("columnName: 'trip_id'"));
      expect(output, contains('ColumnType.integer'));
    });
  });
}

/// Minimal [BuildStep] implementation for testing. The generator does not
/// use [BuildStep], so all members throw [UnimplementedError].
class _FakeBuildStep implements BuildStep {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
