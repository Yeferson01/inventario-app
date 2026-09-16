import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_sync_coordinator_models.dart';
import 'package:inventario_frontend/features/sync/application/productive_manual_sync_service.dart';
import 'package:inventario_frontend/features/sync/application/productive_scheduled_sync_service.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status.dart';
import 'package:inventario_frontend/features/sync/application/scheduled_sync_policy.dart';
import 'package:inventario_frontend/features/sync/application/scheduled_sync_state_store.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_setup_models.dart';

void main() {
  test('SC-01 active 11:00 performs one scheduled execution', () async {
    final fixture = _Fixture();

    final result = await fixture.scheduler.runIfDue(
      now: DateTime(2026, 9, 16, 11),
    );

    expect(result.didRun, isTrue);
    expect(fixture.domainRuns, 6);
    expect(fixture.seenTrigger, ProductiveSyncTrigger.scheduled);
  });

  test('SC-02 active 23:00 performs one scheduled execution', () async {
    final fixture = _Fixture();

    final result = await fixture.scheduler.runIfDue(
      now: DateTime(2026, 9, 16, 23),
    );

    expect(result.didRun, isTrue);
    expect(result.slotKey, endsWith('|2026-09-16|23'));
  });

  test('SC-03 repeated events do not repeat an attempted slot', () async {
    final fixture = _Fixture();
    final now = DateTime(2026, 9, 16, 11, 20);

    await fixture.scheduler.runIfDue(now: now);
    final second = await fixture.scheduler.runIfDue(now: now);

    expect(second.didRun, isFalse);
    expect(second.slotAttempted, isTrue);
    expect(fixture.domainRuns, 6);
  });

  test('SC-04 slot completion is isolated by profile/business/branch',
      () async {
    final fixture = _Fixture();
    final now = DateTime(2026, 9, 16, 11, 20);

    await fixture.scheduler.runIfDue(now: now);
    fixture.input = _input(businessId: 'business-2');
    final second = await fixture.scheduler.runIfDue(now: now);

    expect(second.didRun, isTrue);
    expect(fixture.domainRuns, 12);
    expect(fixture.store.attempted, hasLength(2));
  });

  test('SC-05 resume at 13:00 catches up only the latest 11:00 slot', () async {
    final fixture = _Fixture();

    final result = await fixture.scheduler.runIfDue(
      now: DateTime(2026, 9, 16, 13),
    );

    expect(result.didRun, isTrue);
    expect(result.slotKey, endsWith('|2026-09-16|11'));
    expect(fixture.store.attempted, hasLength(1));
  });

  test('SC-06 offline slot remains eligible for catch-up', () async {
    final fixture = _Fixture(input: _input(isOnline: false));
    final now = DateTime(2026, 9, 16, 13);

    final offline = await fixture.scheduler.runIfDue(now: now);
    fixture.input = _input();
    final catchUp = await fixture.scheduler.runIfDue(now: now);

    expect(offline.didRun, isFalse);
    expect(offline.slotAttempted, isFalse);
    expect(catchUp.didRun, isTrue);
    expect(fixture.domainRuns, 6);
  });

  test('SC-07 reconnect alone does not invoke productive sync', () async {
    final fixture = _Fixture(input: _input(isOnline: false));
    await fixture.scheduler.runIfDue(now: DateTime(2026, 9, 16, 10));

    fixture.input = _input();
    await Future<void>.delayed(Duration.zero);

    expect(fixture.domainRuns, 0);
    expect(fixture.store.attempted, isEmpty);
  });

  test('SC-08 retryable result marks the slot without immediate loop',
      () async {
    final fixture = _Fixture(retryable: true);
    final now = DateTime(2026, 9, 16, 11);

    final first = await fixture.scheduler.runIfDue(now: now);
    final second = await fixture.scheduler.runIfDue(now: now);

    expect(first.syncResult?.outcome, ProductiveManualSyncOutcome.pending);
    expect(second.didRun, isFalse);
    expect(fixture.domainRuns, 6);
  });

  test('SC-09 requires-attention result does not loop the same slot', () async {
    final fixture = _Fixture(requiresAttention: true);
    final now = DateTime(2026, 9, 16, 11);

    final first = await fixture.scheduler.runIfDue(now: now);
    final second = await fixture.scheduler.runIfDue(now: now);

    expect(
      first.syncResult?.outcome,
      ProductiveManualSyncOutcome.requiresAttention,
    );
    expect(second.didRun, isFalse);
    expect(fixture.domainRuns, 6);
  });

  test('SC-10 manual and scheduled collision shares one execution', () async {
    final gate = Completer<ProductiveSyncDomainResult>();
    final fixture = _Fixture(firstDomainGate: gate);

    final manual = fixture.productive.run();
    await Future<void>.delayed(Duration.zero);
    final scheduled = fixture.scheduler.runIfDue(
      now: DateTime(2026, 9, 16, 11),
    );
    await Future<void>.delayed(Duration.zero);

    expect(fixture.domainRuns, 1);
    gate.complete(
      const ProductiveSyncDomainResult.succeeded(
        ProductiveSyncDomain.catalog,
      ),
    );
    await manual;
    final scheduledResult = await scheduled;

    expect(scheduledResult.didRun, isTrue);
    expect(fixture.domainRuns, 6);
  });
}

class _Fixture {
  _Fixture({
    AppSyncCoordinatorInput? input,
    this.retryable = false,
    this.requiresAttention = false,
    this.firstDomainGate,
  }) : input = input ?? _input() {
    productive = ProductiveManualSyncService(
      inputLoader: () async => this.input,
      contextValidator: (received) async {
        seenTrigger = switch (received.metadata?['sync_trigger']) {
          'scheduled' => ProductiveSyncTrigger.scheduled,
          _ => ProductiveSyncTrigger.manual,
        };
        return AppRuntimeContext(
          businessId: received.businessId,
          branchId: received.branchId!,
          profileId: received.profileId!,
          installationId: received.installationId,
          appDeviceId: 'device-1',
        );
      },
      catalogUploadRunner: _runDomain,
      cashRunner: _runDomain,
      posRunner: _runDomain,
      purchasesRunner: _runDomain,
      inventoryRunner: _runDomain,
      catalogRefreshRunner: _runDomain,
      statusLoader: ({
        required scope,
        required isOnline,
        required isSyncing,
      }) async {
        return ProductiveSyncStatus(
          scope: scope,
          connectivity: ProductiveSyncConnectivity.online,
          isSyncing: false,
          pendingSales: 0,
          pendingPurchases: retryable ? 1 : 0,
          pendingCashOperations: 0,
          pendingProductOperations: 0,
          pendingInventoryOperations: 0,
          openIssueCount: 0,
          attentionOperationCount: requiresAttention ? 1 : 0,
        );
      },
    );
    scheduler = ProductiveScheduledSyncService(
      inputLoader: () async => this.input,
      productiveSyncService: productive,
      policy: const ScheduledSyncPolicy(),
      stateStore: store,
    );
  }

  AppSyncCoordinatorInput input;
  final bool retryable;
  final bool requiresAttention;
  final Completer<ProductiveSyncDomainResult>? firstDomainGate;
  final _MemoryStateStore store = _MemoryStateStore();
  late final ProductiveManualSyncService productive;
  late final ProductiveScheduledSyncService scheduler;
  ProductiveSyncTrigger? seenTrigger;
  int domainRuns = 0;

  Future<ProductiveSyncDomainResult> _runDomain(
    ProductiveSyncExecutionContext context,
  ) async {
    domainRuns++;
    if (domainRuns == 1 && firstDomainGate != null) {
      return firstDomainGate!.future;
    }
    if (retryable && domainRuns == 4) {
      return const ProductiveSyncDomainResult.failedRetryable(
        ProductiveSyncDomain.purchases,
      );
    }
    if (requiresAttention && domainRuns == 3) {
      return const ProductiveSyncDomainResult.pending(
        ProductiveSyncDomain.pos,
        requiresAttention: true,
      );
    }
    final domain = switch (domainRuns) {
      1 || 6 => ProductiveSyncDomain.catalog,
      2 => ProductiveSyncDomain.cash,
      3 => ProductiveSyncDomain.pos,
      4 => ProductiveSyncDomain.purchases,
      _ => ProductiveSyncDomain.inventory,
    };
    return ProductiveSyncDomainResult.succeeded(domain);
  }
}

class _MemoryStateStore implements ScheduledSyncStateStore {
  final Set<String> attempted = {};

  @override
  Future<Set<String>> getAttemptedScopedSlotKeys() async => {...attempted};

  @override
  Future<void> markScopedSlotAttempted(String slotKey) async {
    attempted.add(slotKey);
  }

  @override
  Future<Set<String>> getCompletedSlotKeys() async => {};

  @override
  Future<Map<String, dynamic>?> getLastResult() async => null;

  @override
  Future<void> markSlotCompleted(String slotKey) async {}

  @override
  Future<void> saveLastResult(Map<String, dynamic> result) async {}
}

AppSyncCoordinatorInput _input({
  String businessId = 'business-1',
  bool isOnline = true,
}) {
  return AppSyncCoordinatorInput(
    businessId: businessId,
    branchId: 'branch-1',
    profileId: 'profile-1',
    installationId: 'installation-1',
    isOnline: isOnline,
  );
}
