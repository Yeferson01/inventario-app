import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_frontend/features/sync/application/productive_scheduled_sync_service.dart';
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

  for (final hour in [11, 23]) {
    testWidgets('active timer invokes scheduler when crossing $hour:00',
        (tester) async {
      var now = DateTime(2026, 9, 16, hour - 1, 59);
      var calls = 0;
      _FakeTimer? timer;

      await tester.pumpWidget(
        ProviderScope(
          child: AppSyncLifecycleGate(
            scopeKey: 'profile|business|branch',
            clock: () => now,
            timerFactory: (duration, callback) {
              timer = _FakeTimer(callback);
              return timer!;
            },
            runner: ({now}) async {
              calls++;
              return const ProductiveScheduledSyncResult(
                didRun: true,
                slotAttempted: true,
                reason: 'ok',
              );
            },
            child: const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      calls = 0;

      now = DateTime(2026, 9, 16, hour);
      timer!.fire();
      await tester.pump();

      expect(calls, 1);
    });
  }
}

class _FakeTimer implements Timer {
  _FakeTimer(this._callback);

  final void Function() _callback;
  bool _isActive = true;

  void fire() {
    if (!_isActive) return;
    _isActive = false;
    _callback();
  }

  @override
  void cancel() => _isActive = false;

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _isActive ? 0 : 1;
}
