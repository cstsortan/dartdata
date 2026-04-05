import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:dartdata/src/annotations/model.dart';
import 'package:dartdata/src/annotations/relationship.dart';
import 'package:dartdata/src/schema/schema.dart';
import 'package:source_gen/source_gen.dart';

/// Reads `@model` annotations and generates `.g.dart` files containing:
///
///   - A `$ClassName` descriptor class with [QueryField] static fields.
///   - A [ModelDescriptor] implementation registered with the [Schema].
///   - `toMap()` / `fromMap()` extensions on the model class.
class ModelGenerator extends GeneratorForAnnotation<Model> {
  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@model can only be applied to classes.',
        element: element,
      );
    }

    final className = element.name;
    final tableName = _toSnakeCase(className);
    final fields = _collectFields(element);
    final relationships = _collectRelationships(element);

    // Build FK columns for to-one relationships (they live on this table).
    final fkColumns = relationships
        .where((r) => r.cardinality == RelationshipCardinality.toOne)
        .map((r) => r.fkColumnDefinition)
        .toList();

    // Many-to-many: toMany + inverse set → junction table.
    final junctionTables = relationships
        .where((r) =>
            r.cardinality == RelationshipCardinality.toMany &&
            r.inverse != null)
        .map((r) => r.junctionTableDefinition(tableName))
        .toList();

    return '''
// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

// **************************************************************************
// dartdata ModelGenerator
// **************************************************************************

/// Type-safe query field descriptors for [$className].
abstract class \$$className {
${fields.where((f) => !f.isExternalFile).map((f) => "  static final ${f.queryFieldDeclaration}").join('\n')}
}

/// [ModelDescriptor] for [$className]. Registered via [Schema].
class _${className}Descriptor extends ModelDescriptor {
  @override
  String get tableName => '$tableName';

  @override
  String get modelClassName => '$className';

  @override
  Type get modelType => $className;

  @override
  List<ColumnDefinition> get columns => [
${fields.map((f) => "    ${f.columnDefinition},").join('\n')}
${fkColumns.map((c) => "    $c,").join('\n')}
  ];

  @override
  List<RelationshipDefinition> get relationships => [
${relationships.map((r) => "    ${r.relationshipDefinition},").join('\n')}
  ];

  @override
  List<String> get externalFileFields => [
${fields.where((f) => f.isExternalFile).map((f) => "    '${f.columnName}',").join('\n')}
  ];
${junctionTables.isNotEmpty ? '''

  @override
  List<JunctionTableDefinition> get junctionTables => [
${junctionTables.map((jt) => "    $jt,").join('\n')}
  ];''' : ''}

  @override
  $className fromMap(Map<String, Object?> row) {
    return $className(
${fields.map((f) => "      ${f.name}: ${f.fromMapExpression('row')},").join('\n')}
    );
  }

  @override
  Map<String, Object?> toMap(Object model) {
    final m = model as $className;
    return {
${fields.map((f) => "      '${f.columnName}': ${f.toMapExpressionFor('m')},").join('\n')}
${relationships.where((r) => r.cardinality == RelationshipCardinality.toOne).map((r) => "      '${r.fkColumnName}': m.${r.fieldName}${r.isNullable ? '?' : ''}.id,").join('\n')}
    };
  }
${_generateGetExternalFile(className, fields)}
}

extension ${className}Persistence on $className {
  static final ModelDescriptor descriptor = _${className}Descriptor();
}
''';
  }

  static const _relationshipChecker = TypeChecker.fromUrl(
    'package:dartdata/src/annotations/relationship.dart#relationship',
  );

  List<_FieldInfo> _collectFields(ClassElement element) {
    return element.fields
        .where((f) => !f.isStatic && !f.isSynthetic)
        .where((f) => !_relationshipChecker.hasAnnotationOf(f))
        .map(_FieldInfo.from)
        .where((f) => !f.isTransient)
        .toList();
  }

  List<_RelationshipInfo> _collectRelationships(ClassElement element) {
    return element.fields
        .where((f) => !f.isStatic && !f.isSynthetic)
        .where((f) => _relationshipChecker.hasAnnotationOf(f))
        .map((f) => _RelationshipInfo.from(f, _relationshipChecker))
        .toList();
  }

  static String _generateGetExternalFile(
      String className, List<_FieldInfo> fields) {
    final extFields = fields.where((f) => f.isExternalFile).toList();
    if (extFields.isEmpty) return '';
    final cases = extFields
        .map((f) =>
            "      case '${f.columnName}': return m.${f.name};")
        .join('\n');
    return '''

  @override
  ExternalFile? getExternalFile(Object model, String fieldName) {
    final m = model as $className;
    switch (fieldName) {
$cases
      default: return null;
    }
  }''';
  }

  String _toSnakeCase(String name) {
    return name
        .replaceAllMapped(
            RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}')
        .replaceFirst(RegExp(r'^_'), '');
  }
}


class _FieldInfo {
  final String name;
  final String columnName;
  final String dartType;
  final bool isPrimaryKey;
  final bool isUnique;
  final bool isIndexed;
  final bool isTransient;
  final bool isNullable;
  final bool isExternalFile;

  _FieldInfo({
    required this.name,
    required this.columnName,
    required this.dartType,
    this.isPrimaryKey = false,
    this.isUnique = false,
    this.isIndexed = false,
    this.isTransient = false,
    this.isNullable = true,
    this.isExternalFile = false,
  });

  factory _FieldInfo.from(FieldElement field) {
    final dartType = field.type.getDisplayString(withNullability: true);
    final isExternal = dartType.contains('ExternalFile');

    // Read @attribute annotation if present.
    var isPK = false;
    var isUniq = false;
    var isIdx = false;
    var isTrans = false;
    String? customColumnName;

    final attrAnnotation = _attributeChecker.firstAnnotationOf(field);
    if (attrAnnotation != null) {
      final reader = ConstantReader(attrAnnotation);
      isPK = reader.read('primaryKey').boolValue;
      isUniq = reader.read('unique').boolValue;
      isIdx = reader.read('indexed').boolValue;
      isTrans = reader.read('transient').boolValue;
      final colNameReader = reader.read('columnName');
      if (!colNameReader.isNull) {
        customColumnName = colNameReader.stringValue;
      }
    }

    final colName = customColumnName ?? _toSnakeCase(field.name);

    return _FieldInfo(
      name: field.name,
      columnName: colName,
      dartType: dartType,
      isPrimaryKey: isPK,
      isUnique: isUniq,
      isIndexed: isIdx,
      isTransient: isTrans,
      isNullable: field.type.nullabilitySuffix.name == 'question',
      isExternalFile: isExternal,
    );
  }

  static const _attributeChecker = TypeChecker.fromUrl(
    'package:dartdata/src/annotations/model.dart#attribute',
  );

  String get queryFieldDeclaration {
    final valueType = _queryFieldType();
    return "QueryField<$valueType> ${name}Field = QueryField<$valueType>('$columnName');";
  }

  String get columnDefinition {
    final colType = _columnTypeName();
    return "ColumnDefinition(columnName: '$columnName', type: ColumnType.$colType, "
        "isPrimaryKey: $isPrimaryKey, isUnique: $isUnique, isIndexed: $isIndexed, "
        "isNullable: $isNullable)";
  }

  String fromMapExpression(String row) {
    if (isExternalFile) {
      if (isNullable) {
        return "$row['$columnName'] != null "
            "? ExternalFile.fromManagedPath($row['$columnName'] as String) "
            ": null";
      }
      return "ExternalFile.fromManagedPath($row['$columnName'] as String)";
    }
    final baseType = dartType.replaceAll('?', '').trim();
    if (isNullable) {
      return switch (baseType) {
        'DateTime' =>
          "$row['$columnName'] != null "
              "? DateTime.fromMillisecondsSinceEpoch($row['$columnName'] as int, isUtc: true) "
              ": null",
        'bool' =>
          "$row['$columnName'] != null "
              "? ($row['$columnName'] as int) != 0 "
              ": null",
        _ => "$row['$columnName'] as $dartType",
      };
    }
    return switch (baseType) {
      'DateTime' =>
        "DateTime.fromMillisecondsSinceEpoch($row['$columnName'] as int, isUtc: true)",
      'bool' => "($row['$columnName'] as int) != 0",
      _ => "$row['$columnName'] as $dartType",
    };
  }

  String get toMapExpression {
    if (isExternalFile) return 'null'; // replaced by _persistExternalFiles
    return switch (dartType.replaceAll('?', '').trim()) {
      'DateTime' => '$name${isNullable ? '?' : ''}.toUtc().millisecondsSinceEpoch',
      'bool' => isNullable
          ? '$name != null ? ($name! ? 1 : 0) : null'
          : '$name ? 1 : 0',
      _ => name,
    };
  }

  /// Like [toMapExpression] but prefixed with a model variable name.
  String toMapExpressionFor(String varName) {
    if (isExternalFile) return 'null'; // replaced by _persistExternalFiles
    return switch (dartType.replaceAll('?', '').trim()) {
      'DateTime' => '$varName.$name${isNullable ? '?' : ''}.toUtc().millisecondsSinceEpoch',
      'bool' => isNullable
          ? '$varName.$name != null ? ($varName.$name! ? 1 : 0) : null'
          : '$varName.$name ? 1 : 0',
      _ => '$varName.$name',
    };
  }

  String _queryFieldType() => switch (dartType.replaceAll('?', '').trim()) {
        'int' => 'int',
        'double' => 'double',
        'bool' => 'bool',
        'DateTime' => 'DateTime',
        _ => 'String',
      };

  String _columnTypeName() => switch (dartType.replaceAll('?', '').trim()) {
        'int' => 'integer',
        'double' => 'real',
        'bool' => 'integer',
        'DateTime' => 'integer',
        _ => 'text',
      };

  static String _toSnakeCase(String name) {
    return name
        .replaceAllMapped(
            RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}')
        .replaceFirst(RegExp(r'^_'), '');
  }
}

class _RelationshipInfo {
  final String fieldName;
  final String relatedClassName;
  final String relatedTable;
  final RelationshipCardinality cardinality;
  final bool isNullable;
  final String deleteRuleName;
  final String? inverse;

  _RelationshipInfo({
    required this.fieldName,
    required this.relatedClassName,
    required this.relatedTable,
    required this.cardinality,
    required this.isNullable,
    required this.deleteRuleName,
    this.inverse,
  });

  factory _RelationshipInfo.from(FieldElement field, TypeChecker checker) {
    final annotation = checker.firstAnnotationOf(field)!;
    final reader = ConstantReader(annotation);

    // Read deleteRule enum value.
    final deleteRuleObj = reader.read('deleteRule');
    final deleteRuleName = deleteRuleObj.objectValue.variable!.name;

    // Read inverse.
    final inverseReader = reader.read('inverse');
    final inverse = inverseReader.isNull ? null : inverseReader.stringValue;

    // Determine cardinality and related type from Dart type.
    final fieldType = field.type;
    String relatedClassName;
    RelationshipCardinality cardinality;
    bool isNullable;

    if (fieldType.isDartCoreList) {
      // List<T> → toMany
      cardinality = RelationshipCardinality.toMany;
      isNullable = false;
      final typeArg = (fieldType as InterfaceType).typeArguments.first;
      relatedClassName = typeArg.element!.name!;
    } else {
      // T or T? → toOne
      cardinality = RelationshipCardinality.toOne;
      isNullable =
          fieldType.nullabilitySuffix == NullabilitySuffix.question;
      relatedClassName = fieldType.element!.name!;
    }

    final relatedTable = _toSnakeCase(relatedClassName);

    return _RelationshipInfo(
      fieldName: field.name,
      relatedClassName: relatedClassName,
      relatedTable: relatedTable,
      cardinality: cardinality,
      isNullable: isNullable,
      deleteRuleName: deleteRuleName,
      inverse: inverse,
    );
  }

  /// The FK column name: `<fieldName>_id`.
  String get fkColumnName => '${_toSnakeCase(fieldName)}_id';

  /// Generates a `ColumnDefinition(...)` string for the FK column.
  String get fkColumnDefinition {
    return "ColumnDefinition(columnName: '$fkColumnName', type: ColumnType.text, "
        "isPrimaryKey: false, isUnique: false, isIndexed: false, "
        "isNullable: $isNullable)";
  }

  /// Generates a `JunctionTableDefinition(...)` string for many-to-many.
  /// [ownerTable] is the table of the class that declares `inverse`.
  String junctionTableDefinition(String ownerTable) {
    // Alphabetical order for consistent naming.
    final tables = [ownerTable, relatedTable]..sort();
    final jtName = '_${tables[0]}_${tables[1]}';
    final firstFk = '${tables[0]}_id';
    final secondFk = '${tables[1]}_id';
    return "JunctionTableDefinition("
        "tableName: '$jtName', "
        "firstFkColumn: '$firstFk', "
        "firstTable: '${tables[0]}', "
        "secondFkColumn: '$secondFk', "
        "secondTable: '${tables[1]}', "
        ")";
  }

  /// Generates a `RelationshipDefinition(...)` string.
  String get relationshipDefinition {
    final inverseStr =
        inverse != null ? "inverseFieldName: '$inverse', " : '';
    final fkStr = cardinality == RelationshipCardinality.toOne
        ? "fkColumnName: '$fkColumnName', "
        : '';
    final foreignKeySide = cardinality == RelationshipCardinality.toOne
        ? 'isForeignKeySide: true, '
        : '';
    return "RelationshipDefinition("
        "fieldName: '$fieldName', "
        "relatedTable: '$relatedTable', "
        "cardinality: RelationshipCardinality.${cardinality.name}, "
        "$inverseStr"
        "deleteRule: DeleteRule.$deleteRuleName, "
        "$fkStr"
        "$foreignKeySide"
        ")";
  }

  static String _toSnakeCase(String name) {
    return name
        .replaceAllMapped(
            RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}')
        .replaceFirst(RegExp(r'^_'), '');
  }
}
