import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_download_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_download_service.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_page_applier.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/reconciliation_issue_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';
import 'package:inventario_frontend/features/sync/data/models/operational_bootstrap_models.dart';

import 'support/operational_bootstrap_test_data.dart';

void main() {
  const request = OperationalBootstrapDownloadRequest(
    profileId: 'profile-a',
    businessId: 'business-a',
    branchId: 'branch-x',
    appDeviceId: 'device-a',
    bundle: 'product_operational',
    dataset: 'products',
    limit: 1000,
  );

  test('single complete page persists final checkpoint and stops', () async {
    final harness = _Harness([bootstrapRpcResponse()]);
    addTearDown(harness.close);

    final result = await harness.service.download(request);

    expect(result.completed, isTrue);
    expect(result.pagesApplied, 1);
    expect(result.rowsReceived, 1);
    expect(result.resumed, isFalse);
    expect(harness.rpc.calls, hasLength(1));
    expect(
      (await harness.checkpoints.getRecord(request.scopeFor('products')))
          ?.status,
      OperationalBootstrapCheckpointStatus.complete,
    );
  });

  test('downloads 1000 + 5, reuses token, accumulates counts, and no page 3',
      () async {
    const token = 'opaque-page-two-token';
    final harness = _Harness([
      bootstrapRpcResponse(
        datasets: {
          'products': bootstrapDatasetPage(
            dataset: 'products',
            rows: bootstrapRows('product', 1000),
            hasMore: true,
            nextPageToken: token,
          ),
        },
      ),
      bootstrapRpcResponse(
        datasets: {
          'products': bootstrapDatasetPage(
            dataset: 'products',
            rows: bootstrapRows('tail', 5),
          ),
        },
      ),
    ]);
    addTearDown(harness.close);

    final result = await harness.service.download(request);

    expect(result.pagesApplied, 2);
    expect(result.rowsReceived, 1005);
    expect(result.completed, isTrue);
    expect(harness.rpc.calls, hasLength(2));
    expect(harness.rpc.calls[1]['p_page_token'], token);
    expect(harness.rpc.calls[1]['p_dataset'], 'products');
  });

  test('transient continuation retries with the persisted page token',
      () async {
    const token = 'resume-after-transient';
    final harness = _Harness(
      [
        bootstrapRpcResponse(
          datasets: {
            'products': bootstrapDatasetPage(
              dataset: 'products',
              rows: bootstrapRows('first', 2),
              hasMore: true,
              nextPageToken: token,
            ),
          },
        ),
        _failure(OperationalBootstrapFailureKind.networkTransient),
        bootstrapRpcResponse(
          datasets: {
            'products': bootstrapDatasetPage(
              dataset: 'products',
              rows: bootstrapRows('second', 1),
            ),
          },
        ),
      ],
      maxTransientRetries: 1,
    );
    addTearDown(harness.close);

    final result = await harness.service.download(request);

    expect(result.completed, isTrue);
    expect(harness.rpc.calls, hasLength(3));
    expect(harness.rpc.calls[1]['p_page_token'], token);
    expect(harness.rpc.calls[2]['p_page_token'], token);
  });

  test('exhausted transient error keeps a resumable checkpoint', () async {
    const token = 'saved-token';
    final harness = _Harness(
      [
        bootstrapRpcResponse(
          datasets: {
            'products': bootstrapDatasetPage(
              dataset: 'products',
              rows: bootstrapRows('first', 1),
              hasMore: true,
              nextPageToken: token,
            ),
          },
        ),
        _failure(OperationalBootstrapFailureKind.networkTransient),
      ],
      maxTransientRetries: 0,
    );
    addTearDown(harness.close);

    await expectLater(
      harness.service.download(request),
      throwsA(_kind(OperationalBootstrapFailureKind.networkTransient)),
    );
    final checkpoint =
        await harness.checkpoints.getRecord(request.scopeFor('products'));
    expect(checkpoint?.status, OperationalBootstrapCheckpointStatus.failed);
    expect(checkpoint?.nextPageToken, token);
    expect(checkpoint?.pagesApplied, 1);
  });

  test('new service instance resumes page 2 and preserves snapshot ID',
      () async {
    const token = 'kill-resume-token';
    final database = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(database.close);
    final first = _Harness.onDatabase(
      database,
      [
        bootstrapRpcResponse(
          snapshotId: 'snapshot-before-kill',
          datasets: {
            'products': bootstrapDatasetPage(
              dataset: 'products',
              rows: bootstrapRows('first', 1),
              hasMore: true,
              nextPageToken: token,
            ),
          },
        ),
        StateError('simulated app kill'),
      ],
      maxTransientRetries: 0,
    );

    await expectLater(first.service.download(request), throwsA(anything));

    final resumed = _Harness.onDatabase(database, [
      bootstrapRpcResponse(
        snapshotId: 'snapshot-before-kill',
        datasets: {
          'products': bootstrapDatasetPage(
            dataset: 'products',
            rows: bootstrapRows('second', 1),
          ),
        },
      ),
    ]);
    final result = await resumed.service.download(request);

    expect(result.resumed, isTrue);
    expect(result.snapshotId, 'snapshot-before-kill');
    expect(result.pagesApplied, 2);
    expect(resumed.rpc.calls.single['p_page_token'], token);
  });

  test('invalid token marks restart_required and explicit restart is fresh',
      () async {
    final harness = _Harness([
      bootstrapRpcResponse(
        snapshotId: 'snapshot-old',
        datasets: {
          'products': bootstrapDatasetPage(
            dataset: 'products',
            rows: bootstrapRows('old', 1),
            hasMore: true,
            nextPageToken: 'invalid-token',
          ),
        },
      ),
      _failure(OperationalBootstrapFailureKind.invalidToken),
      bootstrapRpcResponse(snapshotId: 'snapshot-new'),
    ]);
    addTearDown(harness.close);

    await expectLater(
      harness.service.download(request),
      throwsA(_kind(OperationalBootstrapFailureKind.invalidToken)),
    );
    expect(
      (await harness.checkpoints.getRecord(request.scopeFor('products')))
          ?.status,
      OperationalBootstrapCheckpointStatus.restartRequired,
    );
    await expectLater(
      harness.service.download(request),
      throwsA(_kind(OperationalBootstrapFailureKind.invalidToken)),
    );

    final restarted = await harness.service.download(request, restart: true);
    expect(restarted.restarted, isTrue);
    expect(restarted.resumed, isFalse);
    expect(restarted.snapshotId, 'snapshot-new');
    expect(restarted.completed, isTrue);
  });

  for (final kind in [
    OperationalBootstrapFailureKind.unauthorized,
    OperationalBootstrapFailureKind.forbidden,
  ]) {
    test('$kind propagates and never becomes restart_required', () async {
      final harness = _Harness([
        bootstrapRpcResponse(
          datasets: {
            'products': bootstrapDatasetPage(
              dataset: 'products',
              rows: bootstrapRows('first', 1),
              hasMore: true,
              nextPageToken: 'auth-token',
            ),
          },
        ),
        _failure(kind),
      ]);
      addTearDown(harness.close);

      await expectLater(
          harness.service.download(request), throwsA(_kind(kind)));

      expect(
        (await harness.checkpoints.getRecord(request.scopeFor('products')))
            ?.status,
        OperationalBootstrapCheckpointStatus.failed,
      );
    });
  }

  for (final mismatch in <String, Map<String, Object?>>{
    'branch': {'branchId': 'branch-y'},
    'business': {'businessId': 'business-b'},
    'appDevice': {'appDeviceId': 'device-b'},
    'bundle': {'bundle': 'cash_pos'},
    'dataset': {'datasetRequested': 'product_stock_balances'},
  }.entries) {
    test('${mismatch.key} mismatch opens a blocking scope issue', () async {
      final response = bootstrapRpcResponse(
        branchId: mismatch.value['branchId'] as String? ?? 'branch-x',
        businessId: mismatch.value['businessId'] as String? ?? 'business-a',
        appDeviceId: mismatch.value['appDeviceId'] as String? ?? 'device-a',
        bundle: mismatch.value['bundle'] as String? ?? 'product_operational',
        datasetRequested:
            mismatch.value['datasetRequested'] as String? ?? 'products',
      );
      final harness = _Harness([response]);
      addTearDown(harness.close);

      await expectLater(
        harness.service.download(request),
        throwsA(_kind(OperationalBootstrapFailureKind.scopeMismatch)),
      );
      final issues = await harness.issues.getOpenBlockingIssues(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-x',
      );
      expect(issues, hasLength(1));
      expect(issues.single['issue_type'], 'scope_mismatch');
    });
  }

  test('profile mismatch from authenticated response opens blocker', () async {
    final harness = _Harness([
      bootstrapRpcResponse(profileId: 'profile-b'),
    ]);
    addTearDown(harness.close);

    await expectLater(
      harness.service.download(request),
      throwsA(_kind(OperationalBootstrapFailureKind.scopeMismatch)),
    );
    expect(
      await harness.issues.getOpenBlockingIssues(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-x',
      ),
      hasLength(1),
    );
  });

  test('full bundle starts with dataset null and continues each dataset',
      () async {
    const fullRequest = OperationalBootstrapDownloadRequest(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
      appDeviceId: 'device-a',
      bundle: 'product_operational',
    );
    final harness = _Harness([
      bootstrapRpcResponse(
        datasetRequested: null,
        datasets: {
          'categories': bootstrapDatasetPage(dataset: 'categories'),
          'products': bootstrapDatasetPage(
            dataset: 'products',
            rows: bootstrapRows('first', 1),
            hasMore: true,
            nextPageToken: 'products-next',
          ),
        },
      ),
      bootstrapRpcResponse(
        datasets: {
          'products': bootstrapDatasetPage(
            dataset: 'products',
            rows: bootstrapRows('second', 1),
          ),
        },
      ),
    ]);
    addTearDown(harness.close);

    final result = await harness.service.download(fullRequest);

    expect(result.completed, isTrue);
    expect(result.pagesApplied, 3);
    expect(harness.rpc.calls.first['p_dataset'], isNull);
    expect(harness.rpc.calls.last['p_dataset'], 'products');
  });

  test('supports focal product_stock_balances without bundle assumptions',
      () async {
    const balanceRequest = OperationalBootstrapDownloadRequest(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
      appDeviceId: 'device-a',
      bundle: 'product_operational',
      dataset: 'product_stock_balances',
    );
    final harness = _Harness([
      bootstrapRpcResponse(
        datasetRequested: 'product_stock_balances',
        datasets: {
          'product_stock_balances': bootstrapDatasetPage(
            dataset: 'product_stock_balances',
            rows: bootstrapRows('balance', 2),
          ),
        },
      ),
    ]);
    addTearDown(harness.close);

    final result = await harness.service.download(balanceRequest);

    expect(result.completed, isTrue);
    expect(result.rowsReceived, 2);
    expect(harness.rpc.calls.single['p_dataset'], 'product_stock_balances');
  });

  test('profile, branch, and device each isolate checkpoint resume', () async {
    for (final changed in ['profile', 'branch', 'device']) {
      final database = AppDatabase.executor(NativeDatabase.memory());
      final checkpoints = OperationalBootstrapCheckpointLocalDao(database);
      await checkpoints.beginOrRestart(
        scope: request.scopeFor('products'),
        snapshotId: 'snapshot-a',
        snapshotAt: DateTime.utc(2026, 8, 15),
        authorizationValidatedAt: DateTime.utc(2026, 8, 15),
        nextPageToken: 'profile-a-token',
      );
      await checkpoints.markApplying(request.scopeFor('products'));

      final isolatedRequest = OperationalBootstrapDownloadRequest(
        profileId: changed == 'profile' ? 'profile-b' : 'profile-a',
        businessId: 'business-a',
        branchId: changed == 'branch' ? 'branch-y' : 'branch-x',
        appDeviceId: changed == 'device' ? 'device-b' : 'device-a',
        bundle: 'product_operational',
        dataset: 'products',
      );
      final response = bootstrapRpcResponse(
        profileId: isolatedRequest.profileId,
        branchId: isolatedRequest.branchId,
        appDeviceId: isolatedRequest.appDeviceId,
        snapshotId: 'snapshot-$changed',
      );
      final harness = _Harness.onDatabase(database, [response]);

      final result = await harness.service.download(isolatedRequest);

      expect(result.resumed, isFalse, reason: changed);
      expect(harness.rpc.calls.single['p_page_token'], isNull, reason: changed);
      expect(
        await checkpoints.getRecord(request.scopeFor('products')),
        isNotNull,
        reason: changed,
      );
      await database.close();
    }
  });

  test('page-applier write and checkpoint progress roll back together',
      () async {
    final database = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(database.close);
    final seen = OperationalBootstrapSeenRecordLocalDao(database);
    final failingCheckpoints = _FailingCheckpointDao(database);
    final harness = _Harness.onDatabase(
      database,
      [bootstrapRpcResponse()],
      checkpointDao: failingCheckpoints,
      pageApplier: _DriftMarkerApplier(seen),
    );

    await expectLater(
      harness.service.download(request),
      throwsA(_kind(OperationalBootstrapFailureKind.localPersistence)),
    );
    expect(await seen.exists(_failedMarkerRecord), isFalse);
    expect(
      await failingCheckpoints.getRecord(request.scopeFor('products')),
      isNull,
    );

    final success = _Harness.onDatabase(
      database,
      [bootstrapRpcResponse(snapshotId: 'snapshot-success')],
      pageApplier: _DriftMarkerApplier(seen),
    );
    final result = await success.service.download(request);

    expect(result.completed, isTrue);
    expect(await seen.exists(_markerRecord), isTrue);
    expect(
      (await success.checkpoints.getRecord(request.scopeFor('products')))
          ?.pagesApplied,
      1,
    );
  });
}

OperationalBootstrapException _failure(
  OperationalBootstrapFailureKind kind,
) {
  return OperationalBootstrapException(kind: kind, message: 'test failure');
}

Matcher _kind(OperationalBootstrapFailureKind kind) {
  return isA<OperationalBootstrapException>().having(
    (error) => error.kind,
    'kind',
    kind,
  );
}

class _QueuedRpc {
  _QueuedRpc(this.outcomes);

  final List<Object> outcomes;
  final List<Map<String, Object?>> calls = [];
  var _index = 0;

  Future<Object?> invoke(Map<String, Object?> parameters) async {
    calls.add(Map<String, Object?>.from(parameters));
    if (_index >= outcomes.length) {
      throw StateError('Unexpected RPC call ${_index + 1}.');
    }
    final outcome = outcomes[_index++];
    if (outcome is Exception) {
      throw outcome;
    }
    return outcome;
  }
}

class _Harness {
  _Harness(
    List<Object> outcomes, {
    int maxTransientRetries = 2,
  }) : this.onDatabase(
          AppDatabase.executor(NativeDatabase.memory()),
          outcomes,
          ownsDatabase: true,
          maxTransientRetries: maxTransientRetries,
        );

  _Harness.onDatabase(
    this.database,
    List<Object> outcomes, {
    bool ownsDatabase = false,
    int maxTransientRetries = 2,
    OperationalBootstrapCheckpointLocalDao? checkpointDao,
    OperationalBootstrapPageApplier pageApplier =
        const JournalOnlyOperationalBootstrapPageApplier(),
  })  : _ownsDatabase = ownsDatabase,
        rpc = _QueuedRpc(outcomes),
        checkpoints =
            checkpointDao ?? OperationalBootstrapCheckpointLocalDao(database),
        seen = OperationalBootstrapSeenRecordLocalDao(database),
        issues = ReconciliationIssueLocalDao(database) {
    service = OperationalBootstrapDownloadService(
      database: database,
      remoteDataSource: OperationalBootstrapRemoteDataSource.withInvoker(
        rpc.invoke,
      ),
      checkpointDao: checkpoints,
      seenRecordDao: seen,
      reconciliationIssueDao: issues,
      pageApplier: pageApplier,
      authorizationContextDao: AuthorizedOperationalContextLocalDao(database),
      maxTransientRetries: maxTransientRetries,
      retryDelay: (_) async {},
    );
  }

  final AppDatabase database;
  final bool _ownsDatabase;
  final _QueuedRpc rpc;
  final OperationalBootstrapCheckpointLocalDao checkpoints;
  final OperationalBootstrapSeenRecordLocalDao seen;
  final ReconciliationIssueLocalDao issues;
  late final OperationalBootstrapDownloadService service;

  Future<void> close() async {
    if (_ownsDatabase) {
      await database.close();
    }
  }
}

class _FailingCheckpointDao extends OperationalBootstrapCheckpointLocalDao {
  _FailingCheckpointDao(super.database);

  @override
  Future<void> commitPageProgress({
    required OperationalBootstrapScope scope,
    required String? nextPageToken,
    required int rowsReceived,
    DateTime? authorizationValidatedAt,
  }) {
    throw StateError('simulated checkpoint failure');
  }
}

class _DriftMarkerApplier implements OperationalBootstrapPageApplier {
  const _DriftMarkerApplier(this.seen);

  final OperationalBootstrapSeenRecordLocalDao seen;

  @override
  Future<OperationalBootstrapPageApplyResult> applyPage({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  }) async {
    await seen.recordSeen(
      SeenRecordDraft(
        snapshotId: snapshot.snapshotId,
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-x',
        bundle: 'product_operational',
        dataset: 'products',
        entityId: 'applier-marker',
      ),
    );
    return const OperationalBootstrapPageApplyResult();
  }
}

const _markerRecord = SeenRecordDraft(
  snapshotId: 'snapshot-success',
  profileId: 'profile-a',
  businessId: 'business-a',
  branchId: 'branch-x',
  bundle: 'product_operational',
  dataset: 'products',
  entityId: 'applier-marker',
);

const _failedMarkerRecord = SeenRecordDraft(
  snapshotId: 'snapshot-1',
  profileId: 'profile-a',
  businessId: 'business-a',
  branchId: 'branch-x',
  bundle: 'product_operational',
  dataset: 'products',
  entityId: 'applier-marker',
);
