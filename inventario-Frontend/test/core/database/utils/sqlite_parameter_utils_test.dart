import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/utils/sqlite_parameter_utils.dart';

void main() {
  group('normalizeSqliteParameter', () {
    test('keeps primitive values', () {
      expect(normalizeSqliteParameter(null), isNull);
      expect(normalizeSqliteParameter(true), true);
      expect(normalizeSqliteParameter(10), 10);
      expect(normalizeSqliteParameter(10.5), 10.5);
      expect(normalizeSqliteParameter('abc'), 'abc');
    });

    test('unwraps Drift Variable values', () {
      expect(normalizeSqliteParameter(Variable<String>('abc')), 'abc');
      expect(normalizeSqliteParameter(Variable<int>(7)), 7);
      expect(normalizeSqliteParameter(const Variable<String>(null)), isNull);
    });

    test('converts DateTime to utc iso string', () {
      final value = DateTime.parse('2026-06-26T22:42:26-05:00');
      expect(
        normalizeSqliteParameter(value),
        value.toUtc().toIso8601String(),
      );
    });

    test('converts maps and non-byte lists to json', () {
      final map = {'a': 1, 'b': 'x'};
      final list = ['a', 1];

      expect(normalizeSqliteParameter(map), jsonEncode(map));
      expect(normalizeSqliteParameter(list), jsonEncode(list));
    });

    test('keeps List<int> as bytes', () {
      final bytes = [1, 2, 3];
      expect(normalizeSqliteParameter(bytes), bytes);
    });

    test('normalizes parameter list', () {
      final result = normalizeSqliteParameters([
        Variable<String>('abc'),
        DateTime.parse('2026-06-26T00:00:00Z'),
        {'x': 1},
      ]);

      expect(result[0], 'abc');
      expect(result[1], '2026-06-26T00:00:00.000Z');
      expect(result[2], '{"x":1}');
    });
  });
}
