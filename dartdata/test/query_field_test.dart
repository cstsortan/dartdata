import 'package:dartdata/dartdata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Task 1.1: QueryField<T> operators
  // ---------------------------------------------------------------------------
  group('QueryField operators', () {
    final destination = QueryField<String>('destination');
    final startDate = QueryField<DateTime>('start_date');
    final isActive = QueryField<bool>('is_active');

    // -- Equality -------------------------------------------------------------

    test('equals produces correct SQL and argument', () {
      final p = destination.equals('Paris');
      expect(p.sql, equals('destination = ?'));
      expect(p.arguments, equals(['Paris']));
    });

    test('notEquals produces correct SQL and argument', () {
      final p = destination.notEquals('Paris');
      expect(p.sql, equals('destination != ?'));
      expect(p.arguments, equals(['Paris']));
    });

    test('isNull produces correct SQL with no arguments', () {
      final p = destination.isNull();
      expect(p.sql, equals('destination IS NULL'));
      expect(p.arguments, isEmpty);
    });

    test('isNotNull produces correct SQL with no arguments', () {
      final p = destination.isNotNull();
      expect(p.sql, equals('destination IS NOT NULL'));
      expect(p.arguments, isEmpty);
    });

    // -- Comparison -----------------------------------------------------------

    test('> produces correct SQL and encodes DateTime to millis', () {
      final dt = DateTime.utc(2026, 6, 1);
      final p = startDate > dt;
      expect(p.sql, equals('start_date > ?'));
      expect(p.arguments, equals([dt.millisecondsSinceEpoch]));
    });

    test('>= produces correct SQL', () {
      final dt = DateTime.utc(2026, 6, 1);
      final p = startDate >= dt;
      expect(p.sql, equals('start_date >= ?'));
      expect(p.arguments, equals([dt.millisecondsSinceEpoch]));
    });

    test('< produces correct SQL', () {
      final dt = DateTime.utc(2026, 6, 1);
      final p = startDate < dt;
      expect(p.sql, equals('start_date < ?'));
      expect(p.arguments, equals([dt.millisecondsSinceEpoch]));
    });

    test('<= produces correct SQL', () {
      final dt = DateTime.utc(2026, 6, 1);
      final p = startDate <= dt;
      expect(p.sql, equals('start_date <= ?'));
      expect(p.arguments, equals([dt.millisecondsSinceEpoch]));
    });

    test('between produces correct SQL with two arguments', () {
      final low = DateTime.utc(2026, 1, 1);
      final high = DateTime.utc(2026, 12, 31);
      final p = startDate.between(low, high);
      expect(p.sql, equals('start_date BETWEEN ? AND ?'));
      expect(p.arguments, equals([
        low.millisecondsSinceEpoch,
        high.millisecondsSinceEpoch,
      ]));
    });

    // -- Collections ----------------------------------------------------------

    test('isIn produces correct SQL with placeholder list', () {
      final p = destination.isIn(['Paris', 'Rome', 'Tokyo']);
      expect(p.sql, equals('destination IN (?, ?, ?)'));
      expect(p.arguments, equals(['Paris', 'Rome', 'Tokyo']));
    });

    test('isIn with empty list produces empty IN clause', () {
      final p = destination.isIn([]);
      expect(p.sql, equals('destination IN ()'));
      expect(p.arguments, isEmpty);
    });

    // -- String operations ----------------------------------------------------

    test('contains produces LIKE with wildcards', () {
      final p = destination.contains('ar');
      expect(p.sql, equals('destination LIKE ?'));
      expect(p.arguments, equals(['%ar%']));
    });

    test('startsWith produces LIKE with trailing wildcard', () {
      final p = destination.startsWith('Par');
      expect(p.sql, equals('destination LIKE ?'));
      expect(p.arguments, equals(['Par%']));
    });

    test('endsWith produces LIKE with leading wildcard', () {
      final p = destination.endsWith('is');
      expect(p.sql, equals('destination LIKE ?'));
      expect(p.arguments, equals(['%is']));
    });

    // -- Value encoding -------------------------------------------------------

    test('bool values are encoded as 1/0', () {
      final p = isActive.equals(true);
      expect(p.arguments, equals([1]));

      final p2 = isActive.equals(false);
      expect(p2.arguments, equals([0]));
    });

    test('DateTime values are encoded as UTC milliseconds', () {
      final dt = DateTime(2026, 6, 1, 12, 0, 0); // local time
      final p = startDate.equals(dt);
      expect(p.arguments, equals([dt.toUtc().millisecondsSinceEpoch]));
    });

    test('String values are passed through unchanged', () {
      final p = destination.equals('Paris');
      expect(p.arguments, equals(['Paris']));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 1.2: Predicate composition (AND, OR, NOT)
  // ---------------------------------------------------------------------------
  group('Predicate composition', () {
    final destination = QueryField<String>('destination');
    final name = QueryField<String>('name');

    test('AND (&) wraps both sides in parentheses', () {
      final p = destination.equals('Paris') & name.equals('Grand Tour');
      expect(p.sql, equals('(destination = ?) AND (name = ?)'));
      expect(p.arguments, equals(['Paris', 'Grand Tour']));
    });

    test('OR (|) wraps both sides in parentheses', () {
      final p = destination.equals('Paris') | destination.equals('Rome');
      expect(p.sql, equals('(destination = ?) OR (destination = ?)'));
      expect(p.arguments, equals(['Paris', 'Rome']));
    });

    test('NOT (-) wraps predicate', () {
      final p = -destination.equals('Paris');
      expect(p.sql, equals('NOT (destination = ?)'));
      expect(p.arguments, equals(['Paris']));
    });

    test('nested AND + OR produces correct parenthesisation', () {
      final p = (destination.equals('Paris') | destination.equals('Rome')) &
          name.startsWith('Grand');
      expect(
        p.sql,
        equals(
          '((destination = ?) OR (destination = ?)) AND (name LIKE ?)'),
      );
      expect(p.arguments, equals(['Paris', 'Rome', 'Grand%']));
    });

    test('nested NOT + AND produces correct SQL', () {
      final p = -(destination.equals('Paris') & name.equals('Tour'));
      expect(
        p.sql,
        equals('NOT ((destination = ?) AND (name = ?))'),
      );
      expect(p.arguments, equals(['Paris', 'Tour']));
    });

    test('triple AND chains correctly', () {
      final startDate = QueryField<DateTime>('start_date');
      final dt = DateTime.utc(2026, 1, 1);
      final p = destination.equals('Paris') &
          name.startsWith('Grand') &
          (startDate > dt);
      // Left-associative: ((A AND B) AND C)
      expect(p.sql, contains('AND'));
      expect(p.arguments.length, equals(3));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 1.3: SortDescriptor
  // ---------------------------------------------------------------------------
  group('SortDescriptor', () {
    test('ascending() emits ASC SQL fragment', () {
      final field = QueryField<String>('name');
      final sort = field.ascending();
      expect(sort.toSql(), equals('name ASC'));
      expect(sort.ascending, isTrue);
    });

    test('descending() emits DESC SQL fragment', () {
      final field = QueryField<DateTime>('start_date');
      final sort = field.descending();
      expect(sort.toSql(), equals('start_date DESC'));
      expect(sort.ascending, isFalse);
    });

    test('columnName is preserved', () {
      final field = QueryField<String>('destination');
      expect(field.ascending().columnName, equals('destination'));
      expect(field.descending().columnName, equals('destination'));
    });
  });

  // ---------------------------------------------------------------------------
  // Task 1.4: Query<T> construction
  // ---------------------------------------------------------------------------
  group('Query construction', () {
    test('default Query has no where, empty orderBy, no limit, offset 0', () {
      final q = Query<dynamic>();
      expect(q.where, isNull);
      expect(q.orderBy, isEmpty);
      expect(q.limit, isNull);
      expect(q.offset, equals(0));
      expect(q.eagerLoadExternalStorage, isFalse);
    });

    test('where predicate is wired through', () {
      final destination = QueryField<String>('destination');
      final pred = destination.equals('Paris');
      final q = Query<dynamic>(where: pred);
      expect(q.where, same(pred));
    });

    test('orderBy list is wired through', () {
      final name = QueryField<String>('name');
      final sorts = [name.ascending(), name.descending()];
      final q = Query<dynamic>(orderBy: sorts);
      expect(q.orderBy, equals(sorts));
    });

    test('limit and offset are wired through', () {
      final q = Query<dynamic>(limit: 10, offset: 20);
      expect(q.limit, equals(10));
      expect(q.offset, equals(20));
    });

    test('eagerLoadExternalStorage defaults to false', () {
      expect(Query<dynamic>().eagerLoadExternalStorage, isFalse);
    });

    test('eagerLoadExternalStorage can be set to true', () {
      final q = Query<dynamic>(eagerLoadExternalStorage: true);
      expect(q.eagerLoadExternalStorage, isTrue);
    });
  });
}
