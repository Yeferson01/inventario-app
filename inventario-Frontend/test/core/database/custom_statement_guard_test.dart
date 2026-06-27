import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('customStatement blocks must not pass Drift Variable parameters', () {
    final roots = [
      Directory('lib/core'),
      Directory('lib/features'),
    ];

    final violations = <String>[];

    for (final root in roots) {
      if (!root.existsSync()) {
        continue;
      }

      final files = root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'));

      for (final file in files) {
        final text = file.readAsStringSync();
        var index = 0;

        while (true) {
          index = text.indexOf('customStatement(', index);

          if (index == -1) {
            break;
          }

          final block = _extractFunctionCall(text, index);

          if (block.contains('Variable<') || block.contains('Variable(')) {
            final line = '\n'.allMatches(text.substring(0, index)).length + 1;
            violations.add('${file.path}:$line');
          }

          index += 'customStatement('.length;
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason: 'Do not pass Drift Variable<T> into customStatement. '
          'Use raw SQLite values or normalizeSqliteParameters instead. '
          'Violations: ${violations.join(', ')}',
    );
  });
}

String _extractFunctionCall(String text, int startIndex) {
  final openParenIndex = text.indexOf('(', startIndex);

  if (openParenIndex == -1) {
    return text.substring(startIndex);
  }

  var depth = 0;
  var index = openParenIndex;
  String? stringQuote;
  var isTripleString = false;

  while (index < text.length) {
    final char = text[index];

    if (stringQuote != null) {
      if (isTripleString) {
        if (_startsWith(text, index, '$stringQuote$stringQuote$stringQuote')) {
          index += 3;
          stringQuote = null;
          isTripleString = false;
          continue;
        }

        index++;
        continue;
      }

      if (char == r'\') {
        index += 2;
        continue;
      }

      if (char == stringQuote) {
        stringQuote = null;
      }

      index++;
      continue;
    }

    if (_startsWith(text, index, "'''") || _startsWith(text, index, '"""')) {
      stringQuote = text[index];
      isTripleString = true;
      index += 3;
      continue;
    }

    if (char == "'" || char == '"') {
      stringQuote = char;
      isTripleString = false;
      index++;
      continue;
    }

    if (char == '(') {
      depth++;
    } else if (char == ')') {
      depth--;

      if (depth == 0) {
        return text.substring(startIndex, index + 1);
      }
    }

    index++;
  }

  return text.substring(startIndex);
}

bool _startsWith(String text, int index, String pattern) {
  if (index + pattern.length > text.length) {
    return false;
  }

  return text.substring(index, index + pattern.length) == pattern;
}