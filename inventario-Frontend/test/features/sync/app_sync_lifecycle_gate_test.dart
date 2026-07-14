import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/presentation/widgets/app_sync_lifecycle_gate.dart';

void main() {
  group('AppSyncLifecycleTriggerCode', () {
    test('returns app_start code', () {
      expect(AppSyncLifecycleTrigger.appStart.code, equals('app_start'));
    });

    test('returns app_resume code', () {
      expect(AppSyncLifecycleTrigger.appResume.code, equals('app_resume'));
    });
  });
}
