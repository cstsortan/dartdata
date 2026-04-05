import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dartdata_example/dartdata_example.dart';

void main() {
  test('dump schema', () async {
    final c = await ModelContainer.create(
      schema: cmsSchema,
      configuration: const ModelConfiguration.inMemory(),
    );
    final tables = c.db.select(
      "SELECT name, sql FROM sqlite_master WHERE type='table' ORDER BY name",
    );
    for (final row in tables) {
      print('--- ${row['name']} ---');
      print(row['sql']);
      print('');
    }
    c.close();
  });
}
