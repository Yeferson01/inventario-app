import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the frontend keeps a single AppDatabase provider authority', () {
    final libDirectory = Directory('lib');
    final canonicalPath = 'lib/core/database/database_provider.dart'
        .replaceAll('/', Platform.pathSeparator);
    final duplicatePath = [
      'lib',
      'core',
      'providers',
      'database_provider.dart',
    ].join(Platform.pathSeparator);
    final declarations = <String>[];
    final declarationPattern = RegExp(
      r'^\s*final(?:\s+[\w<>,?.]+)?\s+appDatabaseProvider\s*=',
      multiLine: true,
    );

    expect(libDirectory.existsSync(), isTrue);

    final dartFiles = libDirectory
        .listSync(recursive: true, followLinks: false)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      if (declarationPattern.hasMatch(file.readAsStringSync())) {
        declarations.add(file.path);
      }
    }

    expect(
      declarations,
      [canonicalPath],
      reason: 'appDatabaseProvider must only be declared by the canonical '
          'core/database provider. Found: ${declarations.join(', ')}',
    );
    expect(File(duplicatePath).existsSync(), isFalse);

    final canonicalSource = File(canonicalPath).readAsStringSync();

    expect(canonicalSource, contains('Provider<AppDatabase>'));
    expect(
      RegExp(r'\bAppDatabase\s*\(\s*\)').allMatches(canonicalSource),
      hasLength(1),
    );
    expect(canonicalSource, contains('ref.onDispose'));
    expect(canonicalSource, contains('db.close()'));
  });
}
