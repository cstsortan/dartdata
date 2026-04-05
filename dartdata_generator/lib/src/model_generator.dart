import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:dartdata/dartdata.dart';
import 'package:source_gen/source_gen.dart';

/// Reads `@model` annotations and generates `.g.dart` files containing:
///
///   - A `$ClassName` descriptor class with [QueryField] static fields.
///   - A [ModelDescriptor] implementation registered with the [Schema].
///   - `toMap()` / `fromMap()` extensions on the model class.
class ModelGenerator extends GeneratorForAnnotation<_Model> {
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

    return '''
// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

// **************************************************************************
// dartdata ModelGenerator
// **************************************************************************

/// Type-safe query field descriptors for [$className].
abstract class \$$className {
${fields.map((f) => "  static final ${f.queryFieldDeclaration}").join('\n')}
}

/// [ModelDescriptor] for [$className]. Registered via [Schema].
class _${className}Descriptor extends ModelDescriptor {
  @override
  String get tableName => '$tableName';

  @override
  String get modelClassName => '$className';

  @override
  List<ColumnDefinition> get columns => [
${fields.map((f) => "    ${f.columnDefinition},").join('\n')}
  ];

  @override
  List<RelationshipDefinition> get relationships => []; // TODO

  @override
  List<String> get externalFileFields => [
${fields.where((f) => f.isExternalFile).map((f) => "    '${f.name}',").join('\n')}
  ];

  $className fromMap(Map<String, Object?> row) {
    return $className(
${fields.map((f) => "      ${f.name}: ${f.fromMapExpression('row')},").join('\n')}
    );
  }
}

extension ${className}Persistence on $className {
  static final ModelDescriptor descriptor = _${className}Descriptor();

  Map<String, Object?> toMap() => {
${fields.map((f) => "    '${f.columnName}': ${f.toMapExpression},").join('\n')}
  };
}
''';
  }

  List<_FieldInfo> _collectFields(ClassElement element) {
    return element.fields
        .where((f) => !f.isStatic && !f.isSynthetic)
        .map(_FieldInfo.from)
        .where((f) => !f.isTransient)
        .toList();
  }

  String _toSnakeCase(String name) {
    return name
        .replaceAllMapped(
            RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}')
        .replaceFirst(RegExp(r'^_'), '');
  }
}

// Shim so we can reference the private _Model const from annotations.
typedef _Model = dynamic;

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
    // TODO: read @attribute annotation values via ConstantReader
    final colName = _toSnakeCase(field.name);
    final dartType = field.type.getDisplayString(withNullability: true);
    final isExternal = dartType.contains('ExternalFile');

    return _FieldInfo(
      name: field.name,
      columnName: colName,
      dartType: dartType,
      isNullable: field.type.nullabilitySuffix.name == 'question',
      isExternalFile: isExternal,
    );
  }

  String get queryFieldDeclaration {
    final valueType = _queryFieldType();
    return "QueryField<$valueType> ${name}Field = QueryField<$valueType>('$columnName');";
  }

  String get columnDefinition {
    final colType = _columnType();
    return "ColumnDefinition(columnName: '$columnName', type: ColumnType.$colType, "
        "isPrimaryKey: $isPrimaryKey, isUnique: $isUnique, isIndexed: $isIndexed, "
        "isNullable: $isNullable)";
  }

  String fromMapExpression(String row) {
    if (isExternalFile) {
      return "$row['$columnName'] != null "
          "? ExternalFile.fromManagedPath($row['$columnName'] as String) "
          ": null";
    }
    return switch (dartType.replaceAll('?', '').trim()) {
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
      'bool' => '$name ? 1 : 0',
      _ => name,
    };
  }

  String _queryFieldType() => switch (dartType.replaceAll('?', '').trim()) {
        'int' => 'int',
        'double' => 'double',
        'bool' => 'bool',
        'DateTime' => 'DateTime',
        _ => 'String',
      };

  ColumnType _columnType() => switch (dartType.replaceAll('?', '').trim()) {
        'int' => ColumnType.integer,
        'double' => ColumnType.real,
        'bool' => ColumnType.integer,
        'DateTime' => ColumnType.integer,
        _ => ColumnType.text,
      };

  static String _toSnakeCase(String name) {
    return name
        .replaceAllMapped(
            RegExp(r'[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}')
        .replaceFirst(RegExp(r'^_'), '');
  }
}
