import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_sync_coordinator_models.dart';
import 'package:inventario_frontend/features/sync/application/scheduled_sync_models.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_setup_models.dart';

void main() {
  group('AppSyncCoordinatorInput', () {
    test('serializes to json', () {
      final input = AppSyncCoordinatorInput(
        businessId: 'business-1',
        branchId: 'branch-1',
        profileId: 'profile-1',
        installationId: 'installation-1',
        isOnline: true,
        deviceName: 'Caja Android 1',
        platform: 'android',
        appVersion: '1.0.0',
        osVersion: 'Android 14',
        metadata: {
          'model': 'test-device',
        },
        now: DateTime.parse('2026-06-25T16:00:00Z'),
      );

      final json = input.toJson();

      expect(json['business_id'], equals('business-1'));
      expect(json['branch_id'], equals('branch-1'));
      expect(json['installation_id'], equals('installation-1'));
      expect(json['is_online'], isTrue);
      expect(json['platform'], equals('android'));
      expect(json['metadata'], isA<Map<String, dynamic>>());
    });
  });

  group('AppSyncCoordinatorResult', () {
    test('serializes skipped result', () {
      const result = AppSyncCoordinatorResult(
        didRun: false,
        didPrepareRuntime: false,
        trigger: ScheduledSyncTrigger.scheduled1100,
        reason: 'No estamos en ventana programada.',
      );

      final json = result.toJson();

      expect(json['did_run'], isFalse);
      expect(json['did_prepare_runtime'], isFalse);
      expect(json['trigger'], equals('scheduled_1100'));
      expect(json['runtime_context'], isNull);
      expect(json['operational_context_pull_result'], isNull);
    });

    test('serializes result with runtime and operational context', () {
      final result = AppSyncCoordinatorResult(
        didRun: true,
        didPrepareRuntime: true,
        trigger: ScheduledSyncTrigger.cashClose,
        reason: 'Sync forzado por cierre de caja.',
        runtimeContext: const AppRuntimeContext(
          businessId: 'business-1',
          branchId: 'branch-1',
          profileId: 'profile-1',
          installationId: 'installation-1',
          appDeviceId: 'device-1',
        ),
        operationalContextPullResult: const {
          'business_id': 'business-1',
          'profile_id': 'profile-1',
          'total_applied': 25,
        },
        scheduledSyncResult: ScheduledSyncRunResult(
          didRun: true,
          trigger: ScheduledSyncTrigger.cashClose,
          reason: 'Sync forzado por cierre de caja.',
          startedAt: DateTime.parse('2026-06-25T16:00:00Z'),
          finishedAt: DateTime.parse('2026-06-25T16:00:01Z'),
          catalogUploadResult: {
            'batches_uploaded': 1,
          },
          catalogPullResult: {
            'records_applied': 10,
          },
        ),
      );

      final json = result.toJson();

      expect(json['did_run'], isTrue);
      expect(json['did_prepare_runtime'], isTrue);
      expect(json['trigger'], equals('cash_close'));
      expect(json['runtime_context'], isA<Map<String, dynamic>>());
      expect(
        json['operational_context_pull_result'],
        isA<Map<String, dynamic>>(),
      );
      expect(json['scheduled_sync_result'], isA<Map<String, dynamic>>());
    });
  });
}
