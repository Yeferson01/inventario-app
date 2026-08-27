import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/catalog/application/catalog_readiness.dart';
import 'package:inventario_frontend/features/catalog/application/initial_catalog_bootstrap_coordinator.dart';
import 'package:inventario_frontend/features/catalog/data/models/catalog_remote_models.dart';

void main() {
  test('operational ready starts initial catalog outside scheduler policy',
      () async {
    var readiness = _uninitialized;
    var pulls = 0;
    final coordinator = InitialCatalogBootstrapCoordinator(
      readReadiness: (_) async => readiness,
      pullCatalog: ({required businessId}) async {
        pulls++;
        readiness = _ready;
        return _result(CatalogSyncRunStatus.complete);
      },
    );

    final result = await coordinator.ensureCatalogReady(
      businessId: 'business-a',
      operationalReady: true,
    );

    expect(result.outcome, InitialCatalogBootstrapOutcome.completed);
    expect(result.readiness.isReady, isTrue);
    expect(pulls, 1);
    final restartedCoordinator = InitialCatalogBootstrapCoordinator(
      readReadiness: (_) async => readiness,
      pullCatalog: ({required businessId}) async {
        pulls++;
        return _result(CatalogSyncRunStatus.complete);
      },
    );
    final restarted = await restartedCoordinator.ensureCatalogReady(
      businessId: 'business-a',
      operationalReady: true,
    );

    expect(restarted.outcome, InitialCatalogBootstrapOutcome.alreadyReady);
    expect(pulls, 1);
  });

  test('incomplete remains resumable and the next attempt completes', () async {
    var readiness = _uninitialized;
    var pulls = 0;
    final coordinator = InitialCatalogBootstrapCoordinator(
      maxConsecutiveRuns: 1,
      readReadiness: (_) async => readiness,
      pullCatalog: ({required businessId}) async {
        pulls++;
        if (pulls == 1) {
          readiness = _initializing;
          return _result(CatalogSyncRunStatus.incomplete);
        }
        readiness = _ready;
        return _result(CatalogSyncRunStatus.complete);
      },
    );

    final first = await coordinator.ensureCatalogReady(
      businessId: 'business-a',
      operationalReady: true,
    );
    final second = await coordinator.ensureCatalogReady(
      businessId: 'business-a',
      operationalReady: true,
    );

    expect(first.outcome, InitialCatalogBootstrapOutcome.incomplete);
    expect(first.readiness.isReady, isFalse);
    expect(first.readiness.hasResumeCheckpoint, isTrue);
    expect(second.outcome, InitialCatalogBootstrapOutcome.completed);
    expect(second.readiness.isReady, isTrue);
    expect(pulls, 2);
  });

  test('network failure before ready stays inside catalog state', () async {
    var readiness = _uninitialized;
    final coordinator = InitialCatalogBootstrapCoordinator(
      readReadiness: (_) async => readiness,
      pullCatalog: ({required businessId}) async {
        readiness = _failedBeforeReady;
        return _result(CatalogSyncRunStatus.failed);
      },
    );

    final result = await coordinator.ensureCatalogReady(
      businessId: 'business-a',
      operationalReady: true,
    );

    expect(result.outcome, InitialCatalogBootstrapOutcome.failed);
    expect(result.readiness.status, CatalogReadinessStatus.failedBeforeReady);
    expect(result.readiness.isReady, isFalse);
  });

  test('durable completion survives failure and excludes legacy partial state',
      () {
    final readiness = CatalogReadiness.fromSyncState({
      'last_catalog_pull_at': '2026-08-27T12:00:00Z',
      'last_server_time': '2026-08-27T13:00:00Z',
      'last_page_token': null,
      'is_syncing': false,
      'last_error': 'network unavailable',
    });
    final legacy = CatalogReadiness.fromSyncState({
      'last_catalog_pull_at': '2026-08-24T12:00:00Z',
      'last_server_time': '2026-08-24T12:00:00Z',
      'last_since_updated_at': '2026-08-24T12:00:00Z',
      'last_page_token': jsonEncode({'offset': 10000}),
      'is_syncing': false,
    });
    final signedResumeAfterCompletion = CatalogReadiness.fromSyncState({
      'last_catalog_pull_at': '2026-08-26T12:00:00Z',
      'last_server_time': '2026-08-27T12:00:00Z',
      'last_since_updated_at': '2026-08-26T12:00:00Z',
      'last_page_token': jsonEncode({
        'token_version': 1,
        'token': 'signed-value',
      }),
      'is_syncing': false,
    });

    expect(readiness.status, CatalogReadinessStatus.readyWithSyncError);
    expect(readiness.isReady, isTrue);
    expect(readiness.lastError, 'network unavailable');
    expect(legacy.isReady, isFalse);
    expect(legacy.status, CatalogReadinessStatus.initializing);
    expect(signedResumeAfterCompletion.isReady, isTrue);
  });
}

const _uninitialized = CatalogReadiness(
  status: CatalogReadinessStatus.uninitialized,
  isSyncing: false,
  hasResumeCheckpoint: false,
);

const _initializing = CatalogReadiness(
  status: CatalogReadinessStatus.initializing,
  isSyncing: false,
  hasResumeCheckpoint: true,
);

final _ready = CatalogReadiness(
  status: CatalogReadinessStatus.ready,
  isSyncing: false,
  hasResumeCheckpoint: false,
  lastCompletedAt: DateTime.utc(2026, 8, 27, 12),
);

const _failedBeforeReady = CatalogReadiness(
  status: CatalogReadinessStatus.failedBeforeReady,
  isSyncing: false,
  hasResumeCheckpoint: false,
  lastError: 'network unavailable',
);

CatalogSyncRunResult _result(CatalogSyncRunStatus status) {
  return CatalogSyncRunResult(
    pagesPulled: 1,
    recordsReceived: 0,
    recordsApplied: 0,
    masterProductsUpserted: 0,
    productBarcodesUpserted: 0,
    ignoredRecords: 0,
    status: status,
    resumed: status == CatalogSyncRunStatus.incomplete,
    committedCursorAdvanced: status == CatalogSyncRunStatus.complete,
    nextPageTokenPresent: status == CatalogSyncRunStatus.incomplete,
    failureClassification:
        status == CatalogSyncRunStatus.failed ? 'transient_or_unknown' : null,
    failureMessage:
        status == CatalogSyncRunStatus.failed ? 'network unavailable' : null,
  );
}
