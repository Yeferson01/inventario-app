import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_sync_coordinator_models.dart';
import 'package:inventario_frontend/features/sync/application/productive_manual_sync_service.dart';
import 'package:inventario_frontend/features/sync/application/scheduled_sync_models.dart';

void main() {
  test('runs the manual coordinator with the exact scoped input', () async {
    AppSyncCoordinatorInput? receivedInput;
    final service = ProductiveManualSyncService(
      inputLoader: () async => _input(),
      coordinator: (input) async {
        receivedInput = input;
        return _completedResult();
      },
    );

    final result = await service.run();

    expect(result.outcome, ProductiveManualSyncOutcome.completed);
    expect(receivedInput?.businessId, 'business-1');
    expect(receivedInput?.branchId, 'branch-1');
    expect(receivedInput?.profileId, 'profile-1');
    expect(receivedInput?.installationId, 'installation-1');
    expect(receivedInput?.metadata?['source'], 'productive_manual_sync');
    expect(result.coordinatorResult?.trigger, ScheduledSyncTrigger.manual);
  });

  test('coalesces concurrent runs into one coordinator invocation', () async {
    final completer = Completer<AppSyncCoordinatorResult>();
    var calls = 0;
    final service = ProductiveManualSyncService(
      inputLoader: () async => _input(),
      coordinator: (_) {
        calls++;
        return completer.future;
      },
    );

    final first = service.run();
    final second = service.run();
    await Future<void>.delayed(Duration.zero);

    expect(calls, 1);
    completer.complete(_completedResult());
    expect((await first).completed, isTrue);
    expect((await second).completed, isTrue);
  });

  test('offline input fails safely without invoking the coordinator', () async {
    var calls = 0;
    final service = ProductiveManualSyncService(
      inputLoader: () async => _input(isOnline: false),
      coordinator: (_) async {
        calls++;
        return _completedResult();
      },
    );

    final result = await service.run();

    expect(result.outcome, ProductiveManualSyncOutcome.unavailable);
    expect(result.message, contains('conexión'));
    expect(calls, 0);
  });

  test('missing authenticated context fails safely before sync', () async {
    var calls = 0;
    final service = ProductiveManualSyncService(
      inputLoader: () async => null,
      coordinator: (_) async {
        calls++;
        return _completedResult();
      },
    );

    final result = await service.run();

    expect(result.outcome, ProductiveManualSyncOutcome.unavailable);
    expect(result.message, contains('sesión autenticada'));
    expect(calls, 0);
  });

  test('partial upload remains visible as a controlled issue', () async {
    final service = ProductiveManualSyncService(
      inputLoader: () async => _input(),
      coordinator: (_) async => _completedResult(batchesPartial: 1),
    );

    final result = await service.run();

    expect(result.outcome, ProductiveManualSyncOutcome.completedWithIssues);
    expect(result.completed, isFalse);
  });
}

AppSyncCoordinatorInput _input({bool isOnline = true}) {
  return AppSyncCoordinatorInput(
    businessId: 'business-1',
    branchId: 'branch-1',
    profileId: 'profile-1',
    installationId: 'installation-1',
    isOnline: isOnline,
    metadata: const {'existing': true},
  );
}

AppSyncCoordinatorResult _completedResult({int batchesPartial = 0}) {
  return AppSyncCoordinatorResult(
    didRun: true,
    didPrepareRuntime: true,
    trigger: ScheduledSyncTrigger.manual,
    reason: 'Sync manual solicitado.',
    scheduledSyncResult: ScheduledSyncRunResult(
      didRun: true,
      trigger: ScheduledSyncTrigger.manual,
      reason: 'Sync manual solicitado.',
      startedAt: DateTime.utc(2026, 9, 7, 12),
      finishedAt: DateTime.utc(2026, 9, 7, 12, 0, 1),
      catalogUploadResult: {
        'batches_partial': batchesPartial,
        'batches_failed': 0,
      },
      catalogPullResult: const {'completed': true},
    ),
  );
}
