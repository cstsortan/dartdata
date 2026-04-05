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
}

/// Minimal [BuildStep] implementation for testing. The generator does not
/// use [BuildStep], so all members throw [UnimplementedError].
class _FakeBuildStep implements BuildStep {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
