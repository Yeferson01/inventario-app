import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/product_stock_balance_local_dao.dart';
import 'package:inventario_frontend/features/sync/application/inventory_balance_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/application/inventory_balance_snapshot_applier.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_download_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_download_service.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_page_applier.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_page_applier_router.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/inventory_balance_reconciliation_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/inventory_movement_acknowledgement_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/reconciliation_issue_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/inventory_balance_reconciliation_models.dart';
import 'package:inventario_frontend/features/sync/data/models/inventory_movement_acknowledgement_models.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';
import 'package:inventario_frontend/features/sync/data/models/operational_bootstrap_models.dart';

import 'support/operational_bootstrap_test_data.dart';

void main() {
  late AppDatabase database;

  setUp(() => database = AppDatabase.executor(NativeDatabase.memory()));
  tearDown(() => database.close());

  test('ACK datasource chunks 401 operations and maps reversed results by ID',
      () async {
    var calls = 0;
    final datasource =
        InventoryMovementAcknowledgementRemoteDataSource.withInvoker(
            (parameters) async {
      calls += 1;
      final operations = parameters['p_operations']! as List;
      return _ackResponse(
        operations.reversed
            .map((item) => (item as Map)['movement_id'].toString())
            .toList(),
      );
    });
    final operations = List.generate(
      401,
      (index) => InventoryMovementAcknowledgementOperation(
        movementId: 'movement-$index',
        idempotencyKey: 'key-$index',
        sourceType: 'manual_adjustment',
        sourceId: null,
        sourceItemId: null,
        productId: 'product-$index',
        quantityChange: 1,
      ),
    );

    final result = await datasource.lookup(
      businessId: 'business-a',
      branchId: 'branch-x',
      appDeviceId: 'device-a',
      operations: operations,
    );

    expect(calls, 3);
    expect(result, hasLength(401));
    expect(result['movement-0']!.status,
        InventoryMovementAcknowledgementStatus.notFound);
    expect(result['movement-400']!.movementId, 'movement-400');
  });

  test(
      'sale, purchase and adjustment rebase from remote base, not old operative',
      () async {
    await _insertMovement(
      database,
      id: 'sale-movement',
      productId: 'sale-product',
      sourceType: 'sale',
      sourceId: 'sale-1',
      sourceItemId: 'sale-item-1',
      quantity: -2,
    );
    await _insertMovement(
      database,
      id: 'purchase-movement',
      productId: 'purchase-product',
      sourceType: 'purchase',
      sourceId: 'purchase-1',
      sourceItemId: 'purchase-item-1',
      quantity: 5,
      unitCost: 4,
    );
    await _insertMovement(
      database,
      id: 'adjustment-movement',
      productId: 'adjustment-product',
      sourceType: 'manual_adjustment',
      quantity: 3,
      unitCost: 2,
    );
    final harness = _Harness(
      database,
      rows: [
        _balanceRow('sale-product', onHand: 10, averageCost: 2),
        _balanceRow('purchase-product', onHand: 10, averageCost: 2),
        _balanceRow('adjustment-product', onHand: 10, averageCost: 2),
      ],
    );

    final result = await harness.service.reconcile(_request);

    expect(result.converged, isTrue);
    expect(await _onHand(database, 'sale-product'), 8);
    expect(await _onHand(database, 'purchase-product'), 15);
    expect(await _onHand(database, 'adjustment-product'), 13);
    expect(await _averageCost(database, 'purchase-product'), 2.67);
    expect(await _averageCost(database, 'adjustment-product'), 2);
  });

  test('mixed pending movements add only not-found deltas', () async {
    await _insertMovement(
      database,
      id: 'sale-movement',
      productId: 'product-1',
      sourceType: 'sale',
      sourceId: 'sale-1',
      sourceItemId: 'sale-item-1',
      quantity: -2,
    );
    await _insertMovement(
      database,
      id: 'purchase-movement',
      productId: 'product-1',
      sourceType: 'purchase',
      sourceId: 'purchase-1',
      sourceItemId: 'purchase-item-1',
      quantity: 5,
      unitCost: 4,
    );
    await _insertMovement(
      database,
      id: 'adjustment-movement',
      productId: 'product-1',
      sourceType: 'manual_adjustment',
      quantity: 1,
    );
    final harness = _Harness(
      database,
      rows: [_balanceRow('product-1', onHand: 10, averageCost: 2)],
      statusFor: (_, id) =>
          id == 'adjustment-movement' ? 'applied' : 'not_found',
    );

    await harness.service.reconcile(_request);

    expect(await _onHand(database, 'product-1'), 13);
    expect((await _balance(database, 'product-1'))['quantity_available'], 13);
  });

  test('purchase and sale become applied without double counting', () async {
    await _insertMovement(
      database,
      id: 'purchase-movement',
      productId: 'purchase-product',
      sourceType: 'purchase',
      sourceId: 'purchase-1',
      sourceItemId: 'purchase-item-1',
      quantity: 5,
      unitCost: 4,
    );
    await _insertMovement(
      database,
      id: 'sale-movement',
      productId: 'sale-product',
      sourceType: 'sale',
      sourceId: 'sale-1',
      sourceItemId: 'sale-item-1',
      quantity: -2,
    );
    final remoteRows = <Map<String, Object?>>[
      _balanceRow('purchase-product', onHand: 10, averageCost: 2),
      _balanceRow('sale-product', onHand: 10, averageCost: 2),
    ];
    final harness = _Harness(
      database,
      rows: remoteRows,
      statusFor: (call, _) => call < 2 ? 'not_found' : 'applied',
    );

    await harness.service.reconcile(_request);
    expect(await _onHand(database, 'purchase-product'), 15);
    expect(await _onHand(database, 'sale-product'), 8);

    remoteRows
      ..clear()
      ..addAll([
        _balanceRow('purchase-product', onHand: 15, averageCost: 2.67),
        _balanceRow('sale-product', onHand: 8, averageCost: 2),
      ]);
    await harness.service.reconcile(_request);

    expect(await _onHand(database, 'purchase-product'), 15);
    expect(await _onHand(database, 'sale-product'), 8);
  });

  test('applied movement is not added and repeated convergence is idempotent',
      () async {
    await _insertMovement(
      database,
      id: 'purchase-movement',
      productId: 'product-1',
      sourceType: 'purchase',
      sourceId: 'purchase-1',
      sourceItemId: 'purchase-item-1',
      quantity: 5,
      unitCost: 4,
    );
    final harness = _Harness(
      database,
      rows: [_balanceRow('product-1', onHand: 15, averageCost: 2.67)],
      statusFor: (_, __) => 'applied',
    );

    await harness.service.reconcile(_request);
    await harness.service.reconcile(_request);

    expect(await _onHand(database, 'product-1'), 15);
    expect(await _issueRows(database), isEmpty);
    expect(await database.select(database.localSyncBatches).get(), isEmpty);
    expect(await database.select(database.localSyncMutations).get(), isEmpty);
  });

  test('server-authoritative transfer is preserved without ACK or double count',
      () async {
    await _insertMovement(
      database,
      id: 'transfer-movement',
      productId: 'product-1',
      sourceType: 'transfer',
      sourceId: 'transfer-1',
      quantity: -1,
      serverApplied: true,
    );
    final harness = _Harness(
      database,
      rows: [_balanceRow('product-1', onHand: 29, averageCost: 0)],
    );

    expect((await harness.service.reconcile(_request)).converged, isTrue);
    expect((await harness.service.reconcile(_request)).converged, isTrue);

    expect(await _onHand(database, 'product-1'), 29);
    expect(harness.requestedMovementIds, isEmpty);
    expect(await database.select(database.localInventoryMovements).get(),
        hasLength(1));
    expect(await _issueRows(database), isEmpty);
  });

  test('unknown movement source remains a recovery blocker', () async {
    await _insertBalance(database, 'product-1', operative: 10);
    await _insertMovement(
      database,
      id: 'unknown-movement',
      productId: 'product-1',
      sourceType: 'unknown-source',
      sourceId: 'unknown-1',
      quantity: 1,
      serverApplied: true,
    );
    final harness = _Harness(
      database,
      rows: [_balanceRow('product-1', onHand: 10)],
    );

    final result = await harness.service.reconcile(_request);

    expect(result.converged, isFalse);
    expect(await _onHand(database, 'product-1'), 10);
    expect(
      (await _issueRows(database)).single['issue_type'],
      'unsupported_inventory_movement',
    );
  });

  test('partial outbox obeys ACK and terminal-applied plus not-found blocks',
      () async {
    await _insertBalance(database, 'applied', operative: 70);
    await _insertBalance(database, 'inconsistent', operative: 80);
    await _insertMovement(
      database,
      id: 'applied-movement',
      productId: 'applied',
      sourceType: 'manual_adjustment',
      quantity: 3,
    );
    await _insertMovement(
      database,
      id: 'inconsistent-movement',
      productId: 'inconsistent',
      sourceType: 'manual_adjustment',
      quantity: 4,
    );
    await _insertMovementOutbox(database, 'applied-movement');
    await _insertMovementOutbox(database, 'inconsistent-movement');
    final harness = _Harness(
      database,
      rows: [
        _balanceRow('applied', onHand: 13),
        _balanceRow('inconsistent', onHand: 10),
      ],
      statusFor: (_, id) => id == 'applied-movement' ? 'applied' : 'not_found',
    );

    final result = await harness.service.reconcile(_request);

    expect(result.converged, isFalse);
    expect(await _onHand(database, 'applied'), 13);
    expect(await _onHand(database, 'inconsistent'), 80);
    expect(
      (await _issueRows(database)).single['issue_type'],
      'terminal_local_movement_not_found',
    );
  });

  test('missing item, rejected and ambiguous preserve operative values',
      () async {
    await _insertBalance(database, 'missing', operative: 77);
    await _insertBalance(database, 'rejected', operative: 88);
    await _insertBalance(database, 'ambiguous', operative: 99);
    await _insertMovement(
      database,
      id: 'missing-movement',
      productId: 'missing',
      sourceType: 'sale',
      sourceId: 'sale-1',
      quantity: -1,
    );
    await _insertMovement(
      database,
      id: 'rejected-movement',
      productId: 'rejected',
      sourceType: 'manual_adjustment',
      quantity: 1,
    );
    await _insertMovement(
      database,
      id: 'ambiguous-movement',
      productId: 'ambiguous',
      sourceType: 'manual_adjustment',
      quantity: 1,
    );
    final harness = _Harness(
      database,
      rows: [
        _balanceRow('missing', onHand: 10),
        _balanceRow('rejected', onHand: 10),
        _balanceRow('ambiguous', onHand: 10),
      ],
      statusFor: (_, id) => switch (id) {
        'rejected-movement' => 'rejected',
        'ambiguous-movement' => 'ambiguous',
        _ => 'not_found',
      },
    );

    final result = await harness.service.reconcile(_request);

    expect(result.converged, isFalse);
    expect(await _onHand(database, 'missing'), 77);
    expect(await _onHand(database, 'rejected'), 88);
    expect(await _onHand(database, 'ambiguous'), 99);
    expect(
      (await _issueRows(database)).map((row) => row['issue_type']),
      containsAll([
        'missing_source_item_id',
        'inventory_movement_rejected',
        'inventory_movement_ambiguous',
      ]),
    );
  });

  test('clean tombstone invalidates while tombstone with pending blocks',
      () async {
    await _insertBalance(database, 'clean', operative: 4);
    await _insertBalance(database, 'pending', operative: 7);
    await _insertMovement(
      database,
      id: 'pending-movement',
      productId: 'pending',
      sourceType: 'manual_adjustment',
      quantity: 2,
    );
    final harness = _Harness(
      database,
      rows: [
        _balanceRow('clean', onHand: 0, tombstone: true),
        _balanceRow('pending', onHand: 0, tombstone: true),
      ],
    );

    final result = await harness.service.reconcile(_request);

    expect(result.converged, isFalse);
    expect(await _onHand(database, 'clean'), 0);
    expect((await _balance(database, 'clean'))['deleted_at'], isNotNull);
    expect(await _onHand(database, 'pending'), 7);
    expect((await _balance(database, 'pending'))['deleted_at'], isNull);
  });

  test('random local balance ID survives remote staging', () async {
    await _insertBalance(database, 'product-1', id: 'local-random');
    final harness = _Harness(
      database,
      rows: [_balanceRow('product-1', onHand: 10)],
    );

    await harness.service.reconcile(_request);

    expect((await _balance(database, 'product-1'))['id'], 'local-random');
  });

  test('clean balance absent from complete snapshot is soft-invalidated',
      () async {
    await _insertBalance(database, 'stale', operative: 12);
    final harness = _Harness(database, rows: const []);

    final result = await harness.service.reconcile(_request);

    expect(result.converged, isTrue);
    expect(await _onHand(database, 'stale'), 0);
    expect((await _balance(database, 'stale'))['deleted_at'], isNotNull);
  });

  test('a proven applied acknowledgement resolves its prior rejection issue',
      () async {
    await _insertMovement(
      database,
      id: 'movement-1',
      productId: 'product-1',
      sourceType: 'manual_adjustment',
      quantity: 2,
    );
    final harness = _Harness(
      database,
      rows: [_balanceRow('product-1', onHand: 12)],
      statusFor: (call, _) => call < 2 ? 'rejected' : 'applied',
    );

    expect((await harness.service.reconcile(_request)).converged, isFalse);
    expect((await harness.service.reconcile(_request)).converged, isTrue);

    final issues = await _issueRows(database);
    expect(issues, hasLength(1));
    expect(issues.single['status'], 'resolved');
  });

  test('business and branch movement isolation is strict', () async {
    await _insertMovement(
      database,
      id: 'same-scope',
      productId: 'product-1',
      sourceType: 'manual_adjustment',
      quantity: 2,
    );
    await _insertMovement(
      database,
      id: 'other-branch',
      productId: 'product-1',
      sourceType: 'manual_adjustment',
      quantity: 50,
      branchId: 'branch-y',
    );
    await _insertMovement(
      database,
      id: 'other-business',
      productId: 'product-1',
      sourceType: 'manual_adjustment',
      quantity: 100,
      businessId: 'business-b',
    );
    final harness = _Harness(
      database,
      rows: [_balanceRow('product-1', onHand: 10)],
    );

    await harness.service.reconcile(_request);

    expect(await _onHand(database, 'product-1'), 12);
    expect(harness.requestedMovementIds, {'same-scope'});
  });

  test('ACK change retries and three unstable attempts open one blocker',
      () async {
    await _insertMovement(
      database,
      id: 'movement-1',
      productId: 'product-1',
      sourceType: 'manual_adjustment',
      quantity: 2,
    );
    final stableAfterRetry = _Harness(
      database,
      rows: [_balanceRow('product-1', onHand: 10)],
      statusFor: (call, _) => call == 0 ? 'not_found' : 'applied',
    );

    final retried = await stableAfterRetry.service.reconcile(_request);
    expect(retried.attempts, 2);
    expect(await _onHand(database, 'product-1'), 10);

    final unstable = _Harness(
      database,
      rows: [_balanceRow('product-1', onHand: 10)],
      statusFor: (call, _) => call.isEven ? 'not_found' : 'applied',
      maxAttempts: 3,
    );
    final blocked = await unstable.service.reconcile(_request);
    expect(blocked.converged, isFalse);
    expect(blocked.attempts, 3);
    expect(
      (await _issueRows(database)).where(
          (row) => row['issue_type'] == 'inventory_convergence_unstable'),
      hasLength(1),
    );
  });

  test('new movement before commit causes a retry', () async {
    await _insertMovement(
      database,
      id: 'movement-1',
      productId: 'product-1',
      sourceType: 'manual_adjustment',
      quantity: 1,
    );
    var inserted = false;
    late _Harness harness;
    harness = _Harness(
      database,
      rows: [_balanceRow('product-1', onHand: 10)],
      beforeFinalization: () async {
        if (inserted) return;
        inserted = true;
        await _insertMovement(
          database,
          id: 'movement-2',
          productId: 'product-1',
          sourceType: 'manual_adjustment',
          quantity: 2,
        );
      },
    );

    final result = await harness.service.reconcile(_request);

    expect(result.attempts, 2);
    expect(await _onHand(database, 'product-1'), 13);
  });

  test('1005 balances paginate and download-only remains convergence pending',
      () async {
    final rows = List.generate(
      1005,
      (index) => _balanceRow('product-$index', onHand: index),
    );
    final harness = _Harness(database, rows: rows);

    final download = await harness.downloadService.download(
      const OperationalBootstrapDownloadRequest(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-x',
        appDeviceId: 'device-a',
        bundle: 'product_operational',
        dataset: 'product_stock_balances',
        limit: 1000,
      ),
    );
    final pendingCheckpoint = await OperationalBootstrapCheckpointLocalDao(
      database,
    ).getRecord(_requestScope);
    expect(download.rowsReceived, 1005);
    expect(pendingCheckpoint!.convergenceStatus, 'pending');
    expect(await database.select(database.localProductStockBalances).get(),
        hasLength(1005));

    final result = await harness.service.reconcile(_request);
    expect(result.converged, isTrue);
    expect(await _onHand(database, 'product-1004'), 1004);
    expect(
      (await OperationalBootstrapCheckpointLocalDao(database)
              .getRecord(_requestScope))!
          .convergenceStatus,
      'complete',
    );
  });

  test(
      'interrupted balance download keeps operative value and pending convergence',
      () async {
    await _insertBalance(database, 'product-0', operative: 77);
    final balanceDao = ProductStockBalanceLocalDao(database);
    final seenDao = OperationalBootstrapSeenRecordLocalDao(database);
    final checkpointDao = OperationalBootstrapCheckpointLocalDao(database);
    final issueDao = ReconciliationIssueLocalDao(database);
    var call = 0;
    final download = OperationalBootstrapDownloadService(
      database: database,
      remoteDataSource: OperationalBootstrapRemoteDataSource.withInvoker(
        (parameters) async {
          if (call++ == 0) {
            return bootstrapRpcResponse(
              snapshotId: 'interrupted-snapshot',
              datasetRequested: 'product_stock_balances',
              datasets: {
                'product_stock_balances': bootstrapDatasetPage(
                  dataset: 'product_stock_balances',
                  rows: [_balanceRow('product-0', onHand: 10)],
                  hasMore: true,
                  nextPageToken: 'tail-token',
                ),
              },
            );
          }
          throw const OperationalBootstrapException(
            kind: OperationalBootstrapFailureKind.networkTransient,
            message: 'simulated app interruption',
          );
        },
      ),
      checkpointDao: checkpointDao,
      seenRecordDao: seenDao,
      reconciliationIssueDao: issueDao,
      pageApplier: OperationalBootstrapPageApplierRouter(
        routes: {
          'product_operational/product_stock_balances':
              InventoryBalanceSnapshotApplier(balanceDao: balanceDao),
        },
      ),
      authorizationContextDao: AuthorizedOperationalContextLocalDao(database),
      maxTransientRetries: 0,
    );

    await expectLater(
      download.download(
        const OperationalBootstrapDownloadRequest(
          profileId: 'profile-a',
          businessId: 'business-a',
          branchId: 'branch-x',
          appDeviceId: 'device-a',
          bundle: 'product_operational',
          dataset: 'product_stock_balances',
          limit: 1000,
        ),
      ),
      throwsA(isA<OperationalBootstrapException>()),
    );

    final checkpoint = await checkpointDao.getRecord(_requestScope);
    expect(checkpoint!.convergenceStatus, 'pending');
    expect(checkpoint.status, OperationalBootstrapCheckpointStatus.failed);
    expect(await _onHand(database, 'product-0'), 77);
    expect(
      (await _balance(database, 'product-0'))['remote_quantity_on_hand'],
      10,
    );
  });
}

const _request = InventoryBalanceReconciliationRequest(
  profileId: 'profile-a',
  businessId: 'business-a',
  branchId: 'branch-x',
  appDeviceId: 'device-a',
  pageLimit: 1000,
);

const _requestScope = OperationalBootstrapScope(
  profileId: 'profile-a',
  businessId: 'business-a',
  branchId: 'branch-x',
  appDeviceId: 'device-a',
  bundle: 'product_operational',
  dataset: 'product_stock_balances',
);

typedef _StatusFor = String Function(int call, String movementId);

class _Harness {
  _Harness(
    AppDatabase database, {
    required List<Map<String, Object?>> rows,
    _StatusFor? statusFor,
    int maxAttempts = 3,
    InventoryReconciliationBeforeFinalization? beforeFinalization,
  }) {
    final balanceDao = ProductStockBalanceLocalDao(database);
    final seenDao = OperationalBootstrapSeenRecordLocalDao(database);
    final checkpointDao = OperationalBootstrapCheckpointLocalDao(database);
    final issueDao = ReconciliationIssueLocalDao(database);
    final applier = InventoryBalanceSnapshotApplier(balanceDao: balanceDao);
    final router = OperationalBootstrapPageApplierRouter(
      routes: <String, OperationalBootstrapPageApplier>{
        'product_operational/product_stock_balances': applier,
      },
    );
    var bootstrapSnapshot = 0;
    downloadService = OperationalBootstrapDownloadService(
      database: database,
      remoteDataSource: OperationalBootstrapRemoteDataSource.withInvoker(
        (parameters) async {
          final token = parameters['p_page_token'];
          if (token == null) bootstrapSnapshot += 1;
          final pageRows = token == null
              ? rows.take(1000).toList()
              : rows.skip(1000).toList();
          final hasMore = token == null && rows.length > 1000;
          return bootstrapRpcResponse(
            snapshotId: 'snapshot-$bootstrapSnapshot',
            datasetRequested: 'product_stock_balances',
            datasets: {
              'product_stock_balances': bootstrapDatasetPage(
                dataset: 'product_stock_balances',
                rows: pageRows,
                hasMore: hasMore,
                nextPageToken: hasMore ? 'balance-tail' : null,
              ),
            },
          );
        },
      ),
      checkpointDao: checkpointDao,
      seenRecordDao: seenDao,
      reconciliationIssueDao: issueDao,
      pageApplier: router,
      authorizationContextDao: AuthorizedOperationalContextLocalDao(database),
      maxTransientRetries: 0,
    );
    var ackCall = 0;
    final ackDatasource =
        InventoryMovementAcknowledgementRemoteDataSource.withInvoker(
      (parameters) async {
        final operations = parameters['p_operations']! as List;
        final ids = operations
            .map((item) => (item as Map)['movement_id'].toString())
            .toList();
        requestedMovementIds.addAll(ids);
        final currentCall = ackCall++;
        return _ackResponse(
          ids,
          statusFor: (id) => statusFor?.call(currentCall, id) ?? 'not_found',
        );
      },
    );
    service = InventoryBalanceReconciliationService(
      database: database,
      acknowledgementDataSource: ackDatasource,
      movementDao: InventoryBalanceReconciliationLocalDao(database),
      balanceDao: balanceDao,
      downloadService: downloadService,
      seenRecordDao: seenDao,
      checkpointDao: checkpointDao,
      issueDao: issueDao,
      maxAttempts: maxAttempts,
      beforeFinalization: beforeFinalization,
    );
  }

  final Set<String> requestedMovementIds = {};
  late final OperationalBootstrapDownloadService downloadService;
  late final InventoryBalanceReconciliationService service;
}

Map<String, Object?> _ackResponse(
  List<String> movementIds, {
  String Function(String id)? statusFor,
}) {
  return {
    'business_id': 'business-a',
    'branch_id': 'branch-x',
    'app_device_id': 'device-a',
    'authorization_validated_at': '2026-08-15T10:00:00Z',
    'checked_at': '2026-08-15T10:00:01Z',
    'acknowledgements': movementIds.map((id) {
      final status = statusFor?.call(id) ?? 'not_found';
      return {
        'movement_id': id,
        'status': status,
        if (status == 'applied') 'remote_movement_id': id,
        if (status == 'applied') 'remote_idempotency_key': 'remote-$id',
        if (status == 'rejected') 'remote_evidence_status': 'conflict',
        'checked_at': '2026-08-15T10:00:01Z',
      };
    }).toList(),
  };
}

Map<String, Object?> _balanceRow(
  String productId, {
  required int onHand,
  int reserved = 0,
  double? averageCost,
  bool tombstone = false,
}) {
  return {
    'id': 'remote-$productId',
    'business_id': 'business-a',
    'branch_id': 'branch-x',
    'product_id': productId,
    'quantity_on_hand': onHand,
    'quantity_reserved': reserved,
    'quantity_available': onHand - reserved,
    'average_cost': averageCost,
    'updated_at': '2026-08-15T09:00:00Z',
    'deleted_at': tombstone ? '2026-08-15T09:00:00Z' : null,
    '_bootstrap_record_state': tombstone ? 'tombstone' : 'present',
  };
}

Future<void> _insertMovement(
  AppDatabase database, {
  required String id,
  required String productId,
  required String sourceType,
  required int quantity,
  String businessId = 'business-a',
  String branchId = 'branch-x',
  String? sourceId,
  String? sourceItemId,
  double? unitCost,
  bool serverApplied = false,
}) {
  final metadataKey = sourceType == 'sale'
      ? 'sale_item_id'
      : sourceType == 'purchase'
          ? 'purchase_item_id'
          : null;
  return database.into(database.localInventoryMovements).insert(
        LocalInventoryMovementsCompanion.insert(
          id: id,
          businessId: businessId,
          branchId: Value(branchId),
          productId: productId,
          movementType: sourceType,
          quantityChange: quantity,
          unitCost: Value(unitCost),
          sourceType: Value(sourceType),
          sourceId: Value(sourceId),
          idempotencyKey: 'key-$id',
          syncStatus: Value(serverApplied ? 1 : 0),
          localStatus: Value(serverApplied ? 'synced' : 'dirty'),
          occurredAt: DateTime.utc(2026, 8, 15, 8),
          metadataJson: Value(
            metadataKey == null || sourceItemId == null
                ? null
                : jsonEncode({metadataKey: sourceItemId}),
          ),
        ),
      );
}

Future<void> _insertBalance(
  AppDatabase database,
  String productId, {
  String? id,
  int operative = 0,
}) {
  return database.into(database.localProductStockBalances).insert(
        LocalProductStockBalancesCompanion.insert(
          id: id ?? 'local-$productId',
          businessId: 'business-a',
          branchId: 'branch-x',
          productId: productId,
          quantityOnHand: Value(operative),
          quantityAvailable: Value(operative),
        ),
      );
}

Future<void> _insertMovementOutbox(
  AppDatabase database,
  String movementId,
) async {
  final batchId = 'batch-$movementId';
  await database.into(database.localSyncBatches).insert(
        LocalSyncBatchesCompanion.insert(
          id: batchId,
          clientBatchId: 'client-$batchId',
          businessId: 'business-a',
          branchId: const Value('branch-x'),
          domain: 'inventory',
          status: const Value('partial'),
          mutationCount: const Value(1),
        ),
      );
  await database.into(database.localSyncMutations).insert(
        LocalSyncMutationsCompanion.insert(
          id: 'mutation-$movementId',
          localSyncBatchId: Value(batchId),
          clientBatchId: Value('client-$batchId'),
          clientMutationId: 'client-mutation-$movementId',
          clientSequence: 1,
          businessId: 'business-a',
          branchId: const Value('branch-x'),
          entityTable: 'inventory_movements',
          entityId: movementId,
          operation: 'insert',
          payloadJson: '{}',
          idempotencyKey: 'key-$movementId',
          status: const Value('applied'),
        ),
      );
}

Future<Map<String, dynamic>> _balance(
  AppDatabase database,
  String productId,
) async {
  return (await ProductStockBalanceLocalDao(database).getProductBalance(
    businessId: 'business-a',
    branchId: 'branch-x',
    productId: productId,
  ))!;
}

Future<int> _onHand(AppDatabase database, String productId) async {
  return (_balance(database, productId)).then(
    (row) => (row['quantity_on_hand'] as num).toInt(),
  );
}

Future<double?> _averageCost(AppDatabase database, String productId) async {
  return (_balance(database, productId)).then(
    (row) => (row['average_cost'] as num?)?.toDouble(),
  );
}

Future<List<Map<String, dynamic>>> _issueRows(AppDatabase database) {
  return ReconciliationIssueLocalDao(database).getIssues(
    profileId: 'profile-a',
    businessId: 'business-a',
    branchId: 'branch-x',
    domain: 'inventory_balance',
  );
}
