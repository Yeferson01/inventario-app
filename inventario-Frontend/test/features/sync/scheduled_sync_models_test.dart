import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/scheduled_sync_models.dart';

void main() {
  group('ScheduledSyncRunResult', () {
    test('serializes to json', () {
      final result = ScheduledSyncRunResult(
        didRun: true,
        trigger: ScheduledSyncTrigger.scheduled1100,
        reason: 'Ventana programada disponible.',
        startedAt: DateTime.parse('2026-06-25T16:00:00Z'),
        finishedAt: DateTime.parse('2026-06-25T16:00:02Z'),
        catalogUploadResult: {
          'batches_uploaded': 1,
        },
        catalogPullResult: {
          'pages_pulled': 1,
        },
      );

      final json = result.toJson();

      expect(json['did_run'], isTrue);
      expect(json['trigger'], equals('scheduled_1100'));
      expect(json['duration_ms'], equals(2000));
      expect(json['catalog_upload_result'], isA<Map<String, dynamic>>());
      expect(json['catalog_pull_result'], isA<Map<String, dynamic>>());
    });
  });

  group('ScheduledSyncDecision', () {
    test('serializes decision to json', () {
      const decision = ScheduledSyncDecision(
        shouldRun: true,
        trigger: ScheduledSyncTrigger.cashClose,
        reason: 'Sync forzado por cierre de caja.',
        slotKey: '2026-06-25:cash_close:123',
      );

      final json = decision.toJson();

      expect(json['should_run'], isTrue);
      expect(json['trigger'], equals('cash_close'));
      expect(json['slot_key'], contains('cash_close'));
    });
  });
}
