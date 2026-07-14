import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/scheduled_sync_models.dart';
import 'package:inventario_frontend/features/sync/application/scheduled_sync_policy.dart';

void main() {
  group('ScheduledSyncPolicy', () {
    const policy = ScheduledSyncPolicy();

    test('runs at 11:00 when slot has not completed', () {
      final decision = policy.evaluate(
        now: DateTime(2026, 6, 25, 11, 0),
        completedSlotKeys: {},
      );

      expect(decision.shouldRun, isTrue);
      expect(decision.trigger, ScheduledSyncTrigger.scheduled1100);
      expect(decision.slotKey, equals('2026-06-25:scheduled_1100'));
    });

    test('runs at 23:00 when slot has not completed', () {
      final decision = policy.evaluate(
        now: DateTime(2026, 6, 25, 23, 0),
        completedSlotKeys: {},
      );

      expect(decision.shouldRun, isTrue);
      expect(decision.trigger, ScheduledSyncTrigger.scheduled2300);
      expect(decision.slotKey, equals('2026-06-25:scheduled_2300'));
    });

    test('does not run outside scheduled hours', () {
      final decision = policy.evaluate(
        now: DateTime(2026, 6, 25, 10, 59),
        completedSlotKeys: {},
      );

      expect(decision.shouldRun, isFalse);
    });

    test('does not repeat a completed scheduled slot', () {
      final decision = policy.evaluate(
        now: DateTime(2026, 6, 25, 11, 30),
        completedSlotKeys: {'2026-06-25:scheduled_1100'},
      );

      expect(decision.shouldRun, isFalse);
      expect(decision.trigger, ScheduledSyncTrigger.scheduled1100);
    });

    test('cash close always runs as forced trigger', () {
      final decision = policy.evaluate(
        now: DateTime(2026, 6, 25, 15, 30),
        completedSlotKeys: {'2026-06-25:scheduled_1100'},
        forcedTrigger: ScheduledSyncTrigger.cashClose,
      );

      expect(decision.shouldRun, isTrue);
      expect(decision.trigger, ScheduledSyncTrigger.cashClose);
      expect(decision.slotKey, contains('cash_close'));
    });

    test('manual always runs as forced trigger', () {
      final decision = policy.evaluate(
        now: DateTime(2026, 6, 25, 15, 30),
        completedSlotKeys: {'2026-06-25:scheduled_1100'},
        forcedTrigger: ScheduledSyncTrigger.manual,
      );

      expect(decision.shouldRun, isTrue);
      expect(decision.trigger, ScheduledSyncTrigger.manual);
      expect(decision.slotKey, contains('manual'));
    });
  });
}
