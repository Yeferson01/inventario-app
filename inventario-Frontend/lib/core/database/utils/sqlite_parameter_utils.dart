import 'dart:convert';

import 'package:drift/drift.dart';

Object? normalizeSqliteParameter(Object? value) {
  if (value is Variable) {
    return normalizeSqliteParameter(value.value);
  }

  if (value == null) {
    return null;
  }

  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }

  if (value is bool || value is int || value is num || value is String) {
    return value;
  }

  if (value is List<int>) {
    return value;
  }

  if (value is Map || value is List) {
    return jsonEncode(value);
  }

  return value.toString();
}

List<Object?> normalizeSqliteParameters(
  List<Object?> parameters,
) {
  return parameters.map<Object?>(normalizeSqliteParameter).toList(
        growable: false,
      );
}
