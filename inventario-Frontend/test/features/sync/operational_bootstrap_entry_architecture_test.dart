import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('debug recovery caller delegates to the Application entry provider', () {
    final source = File(
      'lib/features/sync/presentation/screens/'
      'app_e2e_real_controlled_test_screen.dart',
    ).readAsStringSync();
    final start = source.indexOf('Future<void> _runOperationalBootstrap()');
    final end = source.indexOf('Future<void> _run(', start);
    final method = source.substring(start, end);

    expect(method, contains('operationalBootstrapEntryRunnerProvider'));
    expect(method, isNot(contains('Dao')));
    expect(method, isNot(contains('.rpc(')));
  });

  test('scheduled sync does not import or invoke operational bootstrap', () {
    final source = File(
      'lib/features/sync/application/scheduled_sync_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('OperationalBootstrap')));
    expect(source, isNot(contains('operational_bootstrap')));
  });
}
