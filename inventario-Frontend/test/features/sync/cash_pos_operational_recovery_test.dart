import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_models.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_service.dart';
import 'package:inventario_frontend/features/cash/data/datasources/cash_session_local_dao.dart';
import 'package:inventario_frontend/features/sync/application/cash_pos_recovery_service.dart';
import 'package:inventario_frontend/features/sync/application/cash_pos_snapshot_applier.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_download_service.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_download_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_page_applier_router.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/cash_pos_reconciliation_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/reconciliation_issue_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/cash_pos_recovery_models.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';
import 'package:inventario_frontend/features/sync/data/models/operational_bootstrap_models.dart';
import 'support/operational_bootstrap_test_data.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.executor(NativeDatabase.memory());
    await _seedContext(database);
  });

  tearDown(() => database.close());

  test('1 empty Drift materializes canonical remote register', () async {
    final harness = _Harness(database, [_cashResponse()]);

    final result = await harness.recovery.recover(_request);
    final register = await _row(database, 'cash_registers', 'register-x');

    expect(result.cashContextReady, isTrue);
    expect(register!['id'], 'register-x');
    expect(register['business_id'], 'business-a');
    expect(register['branch_id'], 'branch-x');
    expect(register['local_status'], 'synced');
    expect(register['sync_status'], SyncStatus.synced.index);
  });

  test('2 canonical register lookup is business and branch scoped', () async {
    await _insertRegister(database, id: 'register-x');
    final dao = CashSessionLocalDao(database);

    expect(
      await dao.getCashRegisterById(
        id: 'register-x',
        businessId: 'business-a',
        branchId: 'branch-x',
      ),
      isNotNull,
    );
    expect(
      await dao.getCashRegisterById(
        id: 'register-x',
        businessId: 'business-a',
        branchId: 'branch-y',
      ),
      isNull,
    );
    expect(
      await dao.getCashRegisterById(
        id: 'register-x',
        businessId: 'business-b',
        branchId: 'branch-x',
      ),
      isNull,
    );
  });

  test('3 unresolved or missing canonical register creates no fallback Y',
      () async {
    final service = CashSessionLocalService(dao: CashSessionLocalDao(database));

    await expectLater(
      service.openCashSession(_openInput(cashRegisterId: '')),
      throwsA(isA<CashRecoveryRequiredException>()),
    );
    expect(await _count(database, 'cash_registers'), 0);

    await expectLater(
      service.openCashSession(_openInput(cashRegisterId: 'register-x')),
      throwsA(isA<CashRecoveryRequiredException>()),
    );
    expect(await _count(database, 'cash_registers'), 0);
  });

  test('3b profile parent enables canonical opening without creating Y',
      () async {
    await database.delete(database.profiles).go();
    await _insertRegister(database, id: 'register-x');
    final service = CashSessionLocalService(dao: CashSessionLocalDao(database));

    await expectLater(
      service.openCashSession(_openInput(cashRegisterId: 'register-x')),
      throwsA(
        isA<SqliteException>().having(
          (error) => error.extendedResultCode,
          'extendedResultCode',
          787,
        ),
      ),
    );
    expect(await _count(database, 'businesses'), 2);
    expect(await _count(database, 'branches'), 3);
    expect(await _count(database, 'cash_registers'), 1);
    expect(await _count(database, 'profiles'), 0);
    expect(await _count(database, 'cash_sessions'), 0);

    await database.into(database.profiles).insert(
          ProfilesCompanion.insert(id: 'profile-a'),
        );
    final result = await service.openCashSession(
      _openInput(cashRegisterId: 'register-x'),
    );

    expect(result.cashRegister.id, 'register-x');
    expect(result.cashRegister.created, isFalse);
    expect(result.cashSession.cashRegisterId, 'register-x');
    expect(result.cashSession.openedByProfileId, 'profile-a');
    expect(await _count(database, 'cash_registers'), 1);
    expect(await _count(database, 'cash_sessions'), 1);
  });

  test('4 remote open session is materialized with remote identity', () async {
    final harness = _Harness(database, [_cashResponse()]);
    await harness.recovery.recover(_request);

    final session = await _row(database, 'cash_sessions', 'session-s');
    expect(session!['cash_register_id'], 'register-x');
    expect(session['business_id'], 'business-a');
    expect(session['branch_id'], 'branch-x');
    expect(session['local_status'], 'synced');
  });

  test('5 recovered open session is reused without changing opening data',
      () async {
    final harness = _Harness(database, [_cashResponse()]);
    await harness.recovery.recover(_request);
    final before = await _row(database, 'cash_sessions', 'session-s');
    final service = CashSessionLocalService(dao: CashSessionLocalDao(database));

    final result = await service.openCashSession(
      _openInput(cashRegisterId: 'register-x', openingCashAmount: 999),
    );
    final after = await _row(database, 'cash_sessions', 'session-s');

    expect(result.reusedOpenSession, isTrue);
    expect(result.cashSession.id, 'session-s');
    expect(after!['opening_cash_amount'], before!['opening_cash_amount']);
    expect(after['opened_at'], before['opened_at']);
    expect(await _count(database, 'cash_sessions'), 1);
  });

  test('6 remote sale, item and payment preserve all remote IDs', () async {
    final harness = _Harness(database, [_cashResponse()]);
    final result = await harness.recovery.recover(_request);

    expect(result.recoveredSalesCount, 1);
    expect(await _row(database, 'sales', 'sale-r'), isNotNull);
    expect(await _row(database, 'sale_items', 'item-r'), isNotNull);
    expect(await _row(database, 'sale_payments', 'payment-r'), isNotNull);
  });

  test('7 applying cash_pos creates no outbox batches or mutations', () async {
    final harness = _Harness(database, [_cashResponse()]);
    await harness.recovery.recover(_request);

    expect(await _count(database, 'local_sync_batches'), 0);
    expect(await _count(database, 'local_sync_mutations'), 0);
  });

  test('8 applied completed legacy-dirty cash session normalizes', () async {
    await _insertRegister(database, id: 'register-x');
    await _insertSession(
      database,
      id: 'session-s',
      opening: 1,
      localStatus: 'dirty',
      syncStatus: SyncStatus.pendingInsert,
    );
    await _insertOutbox(
      database,
      domain: 'cash',
      entityTable: 'cash_sessions',
      entityId: 'session-s',
      batchStatus: 'completed',
      mutationStatus: 'applied',
    );
    final harness = _Harness(database, [_cashResponse()]);

    await harness.recovery.recover(_request);
    final session = await _row(database, 'cash_sessions', 'session-s');

    expect(session!['opening_cash_amount'], 20);
    expect(session['local_status'], 'synced');
    expect(session['sync_status'], SyncStatus.synced.index);
  });

  test('9 remote A plus local dirty B preserves B and records blocker',
      () async {
    await _insertRegister(database, id: 'register-x');
    await _insertSession(
      database,
      id: 'session-b',
      localStatus: 'dirty',
      syncStatus: SyncStatus.pendingInsert,
    );
    await _insertOutbox(
      database,
      domain: 'cash',
      entityTable: 'cash_sessions',
      entityId: 'session-b',
    );
    final harness = _Harness(database, [_cashResponse()]);

    final result = await harness.recovery.recover(_request);

    expect(result.cashContextReady, isFalse);
    expect(await _row(database, 'cash_sessions', 'session-b'), isNotNull);
    expect(await _row(database, 'cash_sessions', 'session-s'), isNull);
    expect(
      (await _issues(database)).map((row) => row['issue_type']),
      contains('cash_open_session_conflict'),
    );
  });

  test('10 remote A plus local dirty A preserves pending opening fields',
      () async {
    await _insertRegister(database, id: 'register-x');
    await _insertSession(
      database,
      id: 'session-s',
      opening: 77,
      localStatus: 'dirty',
      syncStatus: SyncStatus.pendingUpdate,
    );
    await _insertOutbox(
      database,
      domain: 'cash',
      entityTable: 'cash_sessions',
      entityId: 'session-s',
    );
    final before = await _row(database, 'cash_sessions', 'session-s');
    final harness = _Harness(database, [_cashResponse()]);

    await harness.recovery.recover(_request);
    final after = await _row(database, 'cash_sessions', 'session-s');

    expect(after!['opening_cash_amount'], 77);
    expect(after['opened_at'], before!['opened_at']);
    expect(after['local_status'], 'dirty');
  });

  test('11 remote none preserves local dirty open session without conflict',
      () async {
    await _insertRegister(database, id: 'register-x');
    await _insertSession(
      database,
      id: 'session-b',
      localStatus: 'dirty',
      syncStatus: SyncStatus.pendingInsert,
    );
    await _insertOutbox(
      database,
      domain: 'cash',
      entityTable: 'cash_sessions',
      entityId: 'session-b',
    );
    final harness = _Harness(database, [
      _cashResponse(
          sessionRows: const [],
          saleRows: const [],
          itemRows: const [],
          paymentRows: const []),
    ]);

    await harness.recovery.recover(_request);

    expect(await _row(database, 'cash_sessions', 'session-b'), isNotNull);
    expect(
      (await _issues(database)).where(
        (row) => row['issue_type'] == 'cash_open_session_conflict',
      ),
      isEmpty,
    );
  });

  test('closed remote session is no longer considered open after recovery',
      () async {
    await _insertRegister(database, id: 'register-x');
    await _insertSession(database, id: 'session-s');
    final harness = _Harness(database, [
      _cashResponse(
        sessionRows: const [],
        saleRows: const [],
        itemRows: const [],
        paymentRows: const [],
      ),
    ]);

    await harness.recovery.recover(_request);

    final openSession =
        await CashSessionLocalDao(database).getOpenCashSessionForBranch(
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    final recovered = await _row(database, 'cash_sessions', 'session-s');

    expect(openSession, isNull);
    expect(recovered!['status'], isNot('open'));
    expect(recovered['deleted_at'], isNotNull);
  });

  test('12 remote tombstone soft-invalidates clean register', () async {
    await _insertRegister(database, id: 'register-x');
    final harness = _Harness(database, [
      _cashResponse(
        registerRows: [_registerRow(state: 'tombstone', deletedAt: _updated)],
        sessionRows: const [],
        saleRows: const [],
        itemRows: const [],
        paymentRows: const [],
      ),
    ]);

    await harness.download.download(_downloadRequest);

    expect(
        (await _row(database, 'cash_registers', 'register-x'))!['deleted_at'],
        isNotNull);
  });

  test('13 remote tombstone preserves dirty register and blocks', () async {
    await _insertRegister(
      database,
      id: 'register-x',
      localStatus: 'dirty',
      syncStatus: SyncStatus.pendingDelete,
    );
    await _insertOutbox(
      database,
      domain: 'cash',
      entityTable: 'cash_registers',
      entityId: 'register-x',
    );
    final harness = _Harness(database, [
      _cashResponse(
        registerRows: [_registerRow(state: 'tombstone', deletedAt: _updated)],
        sessionRows: const [],
        saleRows: const [],
        itemRows: const [],
        paymentRows: const [],
      ),
    ]);

    await harness.download.download(_downloadRequest);

    expect(
        (await _row(database, 'cash_registers', 'register-x'))!['deleted_at'],
        isNull);
    expect(
        (await _issues(database)).single['issue_type'], 'dirty_vs_tombstone');
  });

  test('14 canonical X plus dirty legacy Y records canonical conflict',
      () async {
    await _insertRegister(
      database,
      id: 'register-y',
      localStatus: 'dirty',
      syncStatus: SyncStatus.pendingInsert,
    );
    await _insertSession(
      database,
      id: 'session-b',
      cashRegisterId: 'register-y',
      localStatus: 'dirty',
      syncStatus: SyncStatus.pendingInsert,
    );
    await _insertOutbox(
      database,
      domain: 'cash',
      entityTable: 'cash_registers',
      entityId: 'register-y',
    );
    final harness = _Harness(database, [_cashResponse()]);

    final result = await harness.recovery.recover(_request);

    expect(result.cashContextReady, isFalse);
    expect(await _row(database, 'cash_registers', 'register-x'), isNotNull);
    expect(await _row(database, 'cash_registers', 'register-y'), isNotNull);
    expect(await _row(database, 'cash_sessions', 'session-b'), isNotNull);
    expect(
      (await _issues(database)).map((row) => row['issue_type']),
      contains('canonical_entity_conflict'),
    );
  });

  test('14a orphan opening placeholders converge to canonical without blocker',
      () async {
    await _insertRegister(
      database,
      id: 'register-y',
      localStatus: 'dirty',
      syncStatus: SyncStatus.pendingInsert,
      idempotencyKey:
          'installation-a:cash_registers:business-a:branch-x:VendeMas',
      metadataJson:
          '{"source":"cash_session_local_dao","flow":"open_cash_session"}',
    );
    await _insertRegister(
      database,
      id: 'register-z',
      localStatus: 'dirty',
      syncStatus: SyncStatus.pendingInsert,
      idempotencyKey: 'installation-a:cash_registers:business-a:branch-x:MAIN',
      metadataJson:
          '{"source":"cash_session_local_dao","flow":"open_cash_session"}',
    );
    await _insertRegister(
      database,
      id: 'register-retired',
      localStatus: 'synced',
      syncStatus: SyncStatus.synced,
      idempotencyKey: 'installation-a:cash_registers:business-a:branch-x:OLD',
      metadataJson:
          '{"source":"cash_session_local_dao","flow":"open_cash_session"}',
    );
    await (database.update(database.cashRegisters)
          ..where((row) => row.id.equals('register-retired')))
        .write(
      CashRegistersCompanion(
        status: const Value('inactive'),
        deletedAt: Value(DateTime.utc(2026, 8, 15)),
      ),
    );
    for (final legacyId in ['register-y', 'register-z']) {
      await ReconciliationIssueLocalDao(database).openOrUpdateIssue(
        ReconciliationIssueDraft(
          profileId: 'profile-a',
          businessId: 'business-a',
          branchId: 'branch-x',
          domain: 'cash_pos',
          entityType: 'cash_registers',
          entityId: legacyId,
          issueType: 'canonical_entity_conflict',
          severity: 'blocking',
          message: 'Legacy register conflicts with canonical register-x.',
        ),
      );
    }
    final harness = _Harness(database, [_cashResponse()]);

    final result = await harness.recovery.recover(_request);

    expect(result.cashContextReady, isTrue);
    expect(await _row(database, 'cash_registers', 'register-x'), isNotNull);
    for (final legacyId in ['register-y', 'register-z']) {
      final legacy = await _row(database, 'cash_registers', legacyId);
      expect(legacy!['status'], 'inactive');
      expect(legacy['local_status'], 'synced');
      expect(legacy['sync_status'], SyncStatus.synced.index);
      expect(legacy['deleted_at'], isNotNull);
    }
    final alreadyRetired =
        await _row(database, 'cash_registers', 'register-retired');
    expect(alreadyRetired!['status'], 'inactive');
    expect(alreadyRetired['deleted_at'], isNotNull);
    expect(await _count(database, 'local_sync_mutations'), 0);
    expect(
      (await _issues(database)).where(
        (row) =>
            row['issue_type'] == 'canonical_entity_conflict' &&
            row['status'] == 'open',
      ),
      isEmpty,
    );
  });

  test('14b genuine orphan register is not auto-merged', () async {
    await _insertRegister(
      database,
      id: 'register-y',
      localStatus: 'dirty',
      syncStatus: SyncStatus.pendingInsert,
      idempotencyKey:
          'installation-a:cash_registers:business-a:branch-x:SECOND',
      metadataJson: '{"source":"cash_register_administration"}',
    );
    final harness = _Harness(database, [_cashResponse()]);

    final result = await harness.recovery.recover(_request);
    final legacy = await _row(database, 'cash_registers', 'register-y');

    expect(result.cashContextReady, isFalse);
    expect(legacy!['status'], 'active');
    expect(legacy['deleted_at'], isNull);
    expect(
      (await _issues(database)).map((row) => row['issue_type']),
      contains('canonical_entity_conflict'),
    );
  });

  test('15 recovered remote plus pending local sale totals are additive',
      () async {
    final harness = _Harness(database, [_cashResponse()]);
    await harness.recovery.recover(_request);
    await _insertPendingSale(database,
        id: 'sale-l', total: 50, paymentId: 'payment-l');

    final summary = await CashSessionLocalDao(database)
        .getLatestCashSessionSummaryForBranch(
      businessId: 'business-a',
      branchId: 'branch-x',
    );

    expect(summary['sales_total'], 150);
    expect(summary['total_payments'], 150);
    expect(summary['calculated_expected_cash_amount'], 170);
  });

  test('15a included stale sale cash is offset in local expected amount',
      () async {
    await _seedAuthoritativeReconciledSale(
      database,
      cashTreatment: 'already_included_in_destination_opening',
    );
    final dao = CashSessionLocalDao(database);

    final summary = await dao.getLatestCashSessionSummaryForBranch(
      businessId: 'business-a',
      branchId: 'branch-x',
    );

    expect(summary['cash_payments'], 100);
    expect(summary['cash_adjustments'], -100);
    expect(summary['calculated_expected_cash_amount'], 20);
    expect(
      await dao.calculateExpectedCashAmountForSession(
        cashSessionId: 'session-s',
      ),
      20,
    );
  });

  test('16 acknowledged same sale refresh does not double count', () async {
    await _insertRegister(database, id: 'register-x');
    await _insertSession(database, id: 'session-s');
    await _insertPendingSale(database,
        id: 'sale-r', total: 100, paymentId: 'payment-r');
    await _insertOutbox(
      database,
      domain: 'pos',
      entityTable: 'sales',
      entityId: 'sale-r',
      batchStatus: 'completed',
      mutationStatus: 'applied',
    );
    final harness = _Harness(database, [_cashResponse()]);
    await harness.recovery.recover(_request);

    final summary = await CashSessionLocalDao(database)
        .getLatestCashSessionSummaryForBranch(
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    expect(await _count(database, 'sales'), 1);
    expect(await _count(database, 'sale_payments'), 1);
    expect(summary['sales_total'], 100);
    expect(summary['total_payments'], 100);
  });

  test('17 recovery does not modify another branch', () async {
    await _insertRegister(database,
        id: 'register-y', branchId: 'branch-y', name: 'Y');
    final harness = _Harness(database, [_cashResponse()]);
    await harness.recovery.recover(_request);

    expect(
        (await _row(database, 'cash_registers', 'register-y'))!['deleted_at'],
        isNull);
  });

  test('18 recovery does not modify another business', () async {
    await _insertRegister(
      database,
      id: 'register-b',
      businessId: 'business-b',
      branchId: 'branch-b',
      name: 'B',
    );
    final harness = _Harness(database, [_cashResponse()]);
    await harness.recovery.recover(_request);

    expect(
        (await _row(database, 'cash_registers', 'register-b'))!['deleted_at'],
        isNull);
  });

  test('19 checkpoint failure rolls back entities, seen journal and checkpoint',
      () async {
    final harness = _Harness(
      database,
      [_cashResponse()],
      checkpointDao: _FailingCheckpointDao(database),
    );

    await expectLater(
      harness.download.download(_downloadRequest),
      throwsA(isA<OperationalBootstrapException>()),
    );
    expect(await _count(database, 'cash_registers'), 0);
    expect(
        await _count(database, 'local_operational_bootstrap_seen_records'), 0);
    expect(
        await _count(database, 'local_operational_bootstrap_checkpoints'), 0);
  });

  test('20 repeated snapshot application remains idempotent', () async {
    final response = _cashResponse();
    final harness = _Harness(database, [response, response]);
    await harness.recovery.recover(_request);
    await harness.recovery.recover(_request, restart: true);

    expect(await _count(database, 'cash_registers'), 1);
    expect(await _count(database, 'cash_sessions'), 1);
    expect(await _count(database, 'sales'), 1);
    expect(await _count(database, 'sale_items'), 1);
    expect(await _count(database, 'sale_payments'), 1);
    expect(await _count(database, 'local_sync_batches'), 0);
  });

  test('21 incomplete page leaves recovery non-ready until resumed', () async {
    final first = _cashResponse(
      registerRows: [_registerRow()],
      sessionRows: const [],
      saleRows: const [],
      itemRows: const [],
      paymentRows: const [],
      registerHasMore: true,
      registerToken: 'next-register',
    );
    final continuation = bootstrapRpcResponse(
      snapshotId: 'cash-snapshot',
      bundle: 'cash_pos',
      datasetRequested: 'cash_registers',
      datasets: {
        'cash_registers': bootstrapDatasetPage(
          dataset: 'cash_registers',
          rows: const [],
        ),
      },
    );
    final harness = _Harness(database, [
      first,
      const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.networkTransient,
        message: 'app killed',
      ),
      continuation,
    ]);

    await expectLater(
      harness.recovery.recover(_request),
      throwsA(isA<OperationalBootstrapException>()),
    );
    final checkpoint = await OperationalBootstrapCheckpointLocalDao(database)
        .getRecord(_downloadRequest.scopeFor('cash_registers'));
    expect(checkpoint!.isComplete, isFalse);

    final resumed = await harness.recovery.recover(_request);
    expect(resumed.completed, isTrue);
  });

  test('22 dependency failure is blocking and does not disable foreign keys',
      () async {
    final harness = _Harness(database, [
      _cashResponse(
        itemRows: [_itemRow(productId: 'missing-product')],
      ),
    ]);

    final result = await harness.recovery.recover(_request);

    expect(result.cashContextReady, isFalse);
    expect(await _row(database, 'sale_items', 'item-r'), isNull);
    expect(
      (await _issues(database)).map((row) => row['issue_type']),
      contains('dependency_missing'),
    );
    final foreignKeys =
        await database.customSelect('pragma foreign_keys').getSingle();
    expect(foreignKeys.data.values.single, 1);
  });

  test('23 two legacy clean open sessions are preserved and blocked', () async {
    await database.customStatement(
      'drop index ux_cash_sessions_one_open_per_register',
    );
    await _insertRegister(database, id: 'register-x');
    await _insertSession(database, id: 'session-a');
    await _insertSession(database, id: 'session-b');
    final harness = _Harness(database, [
      _cashResponse(
        sessionRows: const [],
        saleRows: const [],
        itemRows: const [],
        paymentRows: const [],
      ),
    ]);

    final result = await harness.recovery.recover(_request);

    expect(result.cashContextReady, isFalse);
    expect((await _row(database, 'cash_sessions', 'session-a'))!['deleted_at'],
        isNull);
    expect((await _row(database, 'cash_sessions', 'session-b'))!['deleted_at'],
        isNull);
    expect(
      (await _issues(database)).map((row) => row['issue_type']),
      contains('multiple_clean_open_sessions'),
    );
  });

  test('24 parent dataset finishes pagination before child application',
      () async {
    final initial = bootstrapRpcResponse(
      snapshotId: 'cash-snapshot',
      bundle: 'cash_pos',
      datasetRequested: null,
      datasets: {
        'session_sale_items': bootstrapDatasetPage(
          dataset: 'session_sale_items',
          rows: [_itemRow(saleId: 'sale-later')],
        ),
        'session_sales': bootstrapDatasetPage(
          dataset: 'session_sales',
          rows: [_saleRow(id: 'sale-first')],
          hasMore: true,
          nextPageToken: 'sales-next',
        ),
        'session_sale_payments': bootstrapDatasetPage(
          dataset: 'session_sale_payments',
        ),
        'open_cash_sessions': bootstrapDatasetPage(
          dataset: 'open_cash_sessions',
          rows: [_sessionRow()],
        ),
        'cash_registers': bootstrapDatasetPage(
          dataset: 'cash_registers',
          rows: [_registerRow()],
        ),
      },
    );
    final continuation = bootstrapRpcResponse(
      snapshotId: 'cash-snapshot',
      bundle: 'cash_pos',
      datasetRequested: 'session_sales',
      datasets: {
        'session_sales': bootstrapDatasetPage(
          dataset: 'session_sales',
          rows: [_saleRow(id: 'sale-later')],
        ),
      },
    );
    final harness = _Harness(database, [initial, continuation]);

    await harness.download.download(_downloadRequest);

    expect(await _row(database, 'sales', 'sale-later'), isNotNull);
    expect(await _row(database, 'sale_items', 'item-r'), isNotNull);
    expect(await _issues(database), isEmpty);
  });

  test('25 session from another opener preserves provenance and remains usable',
      () async {
    final harness = _Harness(database, [
      _cashResponse(sessionRows: [_sessionRow(openedBy: 'profile-other')]),
    ]);
    await harness.recovery.recover(_request);

    final stored = await _row(database, 'cash_sessions', 'session-s');
    final result = await CashSessionLocalService(
      dao: CashSessionLocalDao(database),
    ).openCashSession(_openInput(cashRegisterId: 'register-x'));

    expect(stored!['opened_by_profile_id'], isNull);
    expect(stored['metadata_json'], contains('profile-other'));
    expect(result.cashSession.openedByProfileId, isNull);
    expect(result.reusedOpenSession, isTrue);
  });

  test('26 authoritative superseded mutation is remotely recognized', () async {
    await _seedAuthoritativeReconciledSale(database);
    final local = await _row(database, 'sales', 'sale-r');

    final classification =
        await CashPosReconciliationLocalDao(database).classify(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
      domain: 'pos',
      entityTable: 'sales',
      entityId: 'sale-r',
      local: local!,
      remoteCashSessionId: 'session-s',
    );

    expect(classification.state, CashPosEntityState.remotelyApplied);
    expect(classification.recognizedAt, isNotNull);
  });

  test('27 generic skipped mutation remains transport ambiguous', () async {
    await _insertRegister(database, id: 'register-x');
    await _insertSession(database, id: 'session-s');
    await _insertPendingSale(
      database,
      id: 'sale-r',
      total: 100,
      paymentId: 'payment-r',
    );
    await database.customStatement('''
      update sales
      set local_status = 'synced', sync_status = 0
      where id = 'sale-r'
    ''');
    await _insertOutbox(
      database,
      domain: 'pos',
      entityTable: 'sales',
      entityId: 'sale-r',
      batchStatus: 'partial',
      mutationStatus: 'skipped',
    );
    final local = await _row(database, 'sales', 'sale-r');

    final classification =
        await CashPosReconciliationLocalDao(database).classify(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
      domain: 'pos',
      entityTable: 'sales',
      entityId: 'sale-r',
      local: local!,
      remoteCashSessionId: 'session-s',
    );

    expect(classification.state, CashPosEntityState.transportAmbiguous);
  });

  test(
      '28 reconciled sale aggregate converges all POS checkpoints without stock changes',
      () async {
    await _seedAuthoritativeReconciledSale(database);
    final stockBefore = (await _row(
      database,
      'local_product_stock_balances',
      'balance-r',
    ))!['quantity_on_hand'];
    final issues = ReconciliationIssueLocalDao(database);
    for (final target in const {
      'sales': 'sale-r',
      'sale_items': 'item-r',
      'sale_payments': 'payment-r',
    }.entries) {
      await issues.openOrUpdateIssue(
        ReconciliationIssueDraft(
          profileId: 'profile-a',
          businessId: 'business-a',
          branchId: 'branch-x',
          domain: 'cash_pos',
          entityType: target.key,
          entityId: target.value,
          issueType: 'dirty_vs_remote',
          severity: 'warning',
          message: 'False transport ambiguity.',
        ),
      );
    }
    final harness = _Harness(database, [_cashResponse()]);

    final result = await harness.recovery.recover(_request);
    final checkpoints = await database.customSelect('''
      select dataset, status, convergence_status
      from local_operational_bootstrap_checkpoints
      where bundle = 'cash_pos'
        and dataset in (
          'session_sales', 'session_sale_items', 'session_sale_payments'
        )
      order by dataset
    ''').get();
    final stockAfter = (await _row(
      database,
      'local_product_stock_balances',
      'balance-r',
    ))!['quantity_on_hand'];
    final batch = await _row(database, 'local_sync_batches', 'batch-sale-r');

    expect(result.completed, isTrue);
    expect(result.cashContextReady, isTrue);
    expect(checkpoints, hasLength(3));
    expect(
      checkpoints.every(
        (row) =>
            row.data['status'] == 'complete' &&
            row.data['convergence_status'] == 'complete',
      ),
      isTrue,
    );
    expect(
      (await _issues(database)).where(
        (issue) =>
            issue['issue_type'] == 'dirty_vs_remote' &&
            issue['status'] == 'open',
      ),
      isEmpty,
    );
    expect(stockAfter, stockBefore);
    expect(stockAfter, 25);
    expect(batch!['status'], 'partial');
  });

  test('29 pre-marker authoritative audit tuple remains remotely recognized',
      () async {
    await _seedAuthoritativeReconciledSale(
      database,
      includeExplicitMarker: false,
    );
    final local = await _row(database, 'sales', 'sale-r');

    final classification =
        await CashPosReconciliationLocalDao(database).classify(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
      domain: 'pos',
      entityTable: 'sales',
      entityId: 'sale-r',
      local: local!,
      remoteCashSessionId: 'session-s',
    );

    expect(classification.state, CashPosEntityState.remotelyApplied);
  });
}

const _created = '2026-08-14T08:00:00Z';
const _updated = '2026-08-15T08:00:00Z';

const _request = CashPosRecoveryRequest(
  profileId: 'profile-a',
  businessId: 'business-a',
  branchId: 'branch-x',
  appDeviceId: 'device-a',
  canonicalCashRegisterId: 'register-x',
);

const _downloadRequest = OperationalBootstrapDownloadRequest(
  profileId: 'profile-a',
  businessId: 'business-a',
  branchId: 'branch-x',
  appDeviceId: 'device-a',
  bundle: 'cash_pos',
  limit: 1000,
);

OpenCashSessionInput _openInput({
  required String cashRegisterId,
  double openingCashAmount = 0,
}) =>
    OpenCashSessionInput(
      businessId: 'business-a',
      branchId: 'branch-x',
      profileId: 'profile-a',
      cashRegisterId: cashRegisterId,
      openingCashAmount: openingCashAmount,
    );

Map<String, Object?> _cashResponse({
  List<Map<String, Object?>>? registerRows,
  List<Map<String, Object?>>? sessionRows,
  List<Map<String, Object?>>? saleRows,
  List<Map<String, Object?>>? itemRows,
  List<Map<String, Object?>>? paymentRows,
  bool registerHasMore = false,
  String? registerToken,
}) {
  return bootstrapRpcResponse(
    snapshotId: 'cash-snapshot',
    bundle: 'cash_pos',
    datasetRequested: null,
    datasets: {
      // Deliberately child-first: the router must restore dependency order.
      'session_sale_payments': bootstrapDatasetPage(
        dataset: 'session_sale_payments',
        rows: paymentRows ?? [_paymentRow()],
      ),
      'session_sale_items': bootstrapDatasetPage(
        dataset: 'session_sale_items',
        rows: itemRows ?? [_itemRow()],
      ),
      'session_sales': bootstrapDatasetPage(
        dataset: 'session_sales',
        rows: saleRows ?? [_saleRow()],
      ),
      'open_cash_sessions': bootstrapDatasetPage(
        dataset: 'open_cash_sessions',
        rows: sessionRows ?? [_sessionRow()],
      ),
      'cash_registers': bootstrapDatasetPage(
        dataset: 'cash_registers',
        rows: registerRows ?? [_registerRow()],
        hasMore: registerHasMore,
        nextPageToken: registerToken,
      ),
    },
  );
}

Map<String, Object?> _registerRow({
  String state = 'present',
  String? deletedAt,
}) =>
    {
      'id': 'register-x',
      'business_id': 'business-a',
      'branch_id': 'branch-x',
      'name': 'Caja Principal',
      'status': state == 'tombstone' ? 'inactive' : 'active',
      'version': 1,
      'created_at': _created,
      'updated_at': _updated,
      'deleted_at': deletedAt,
      '_bootstrap_record_state': state,
    };

Map<String, Object?> _sessionRow({String openedBy = 'profile-a'}) => {
      'id': 'session-s',
      'business_id': 'business-a',
      'branch_id': 'branch-x',
      'cash_register_id': 'register-x',
      'opened_by': openedBy,
      'opened_by_profile_id': openedBy,
      'closed_by': null,
      'closed_by_profile_id': null,
      'opening_amount': 20,
      'opening_cash_amount': 20,
      'expected_closing_amount': null,
      'actual_closing_amount': null,
      'difference_amount': null,
      'status': 'open',
      'opened_at': _created,
      'closed_at': null,
      'version': 1,
      'created_at': _created,
      'updated_at': _updated,
      'deleted_at': null,
      '_bootstrap_record_state': 'present',
    };

Map<String, Object?> _saleRow({String id = 'sale-r'}) => {
      'id': id,
      'business_id': 'business-a',
      'branch_id': 'branch-x',
      'cash_session_id': 'session-s',
      'user_id': 'profile-a',
      'customer_id': null,
      'subtotal': 100,
      'discount_total': 0,
      'tax_total': 0,
      'total': 100,
      'payment_method': 'cash',
      'idempotency_key': '$id-key',
      'metadata': const {},
      'status': 'completed',
      'created_at': _created,
      'updated_at': _updated,
      'deleted_at': null,
      '_bootstrap_record_state': 'present',
    };

Map<String, Object?> _itemRow({
  String productId = 'product-1',
  String saleId = 'sale-r',
}) =>
    {
      'id': 'item-r',
      'business_id': 'business-a',
      'sale_id': saleId,
      'product_id': productId,
      'product_name_snapshot': 'Product 1',
      'barcode_snapshot': '7701',
      'quantity': 1,
      'unit_price': 100,
      'discount_amount': 0,
      'tax_amount': 0,
      'subtotal': 100,
      'total': 100,
      'metadata': const {},
      'created_at': _created,
      'updated_at': _updated,
      'deleted_at': null,
      '_bootstrap_record_state': 'present',
    };

Map<String, Object?> _paymentRow() => {
      'id': 'payment-r',
      'business_id': 'business-a',
      'sale_id': 'sale-r',
      'payment_method': 'cash',
      'amount': 100,
      'currency': 'COP',
      'status': 'completed',
      'reference': null,
      'metadata': const {},
      'created_at': _created,
      'updated_at': _updated,
      'deleted_at': null,
      '_bootstrap_record_state': 'present',
    };

Future<void> _seedContext(AppDatabase db) async {
  for (final id in ['business-a', 'business-b']) {
    await db.into(db.businesses).insert(
          BusinessesCompanion.insert(id: id, name: id),
        );
  }
  await db.into(db.profiles).insert(
        ProfilesCompanion.insert(
          id: 'profile-a',
          businessId: const Value('business-a'),
        ),
      );
  for (final entry in const {
    'branch-x': 'business-a',
    'branch-y': 'business-a',
    'branch-b': 'business-b',
  }.entries) {
    await db.into(db.branches).insert(
          BranchesCompanion.insert(
            id: entry.key,
            businessId: entry.value,
            name: entry.key,
          ),
        );
  }
  await db.into(db.products).insert(
        ProductsCompanion.insert(
          id: 'product-1',
          businessId: const Value('business-a'),
          name: 'Product 1',
          salePrice: 100,
        ),
      );
}

Future<void> _insertRegister(
  AppDatabase db, {
  required String id,
  String businessId = 'business-a',
  String branchId = 'branch-x',
  String name = 'Caja Principal',
  String localStatus = 'synced',
  SyncStatus syncStatus = SyncStatus.synced,
  String? idempotencyKey,
  String? metadataJson,
}) {
  return db.into(db.cashRegisters).insert(
        CashRegistersCompanion.insert(
          id: id,
          businessId: Value(businessId),
          branchId: Value(branchId),
          name: Value(name),
          code: const Value('MAIN'),
          idempotencyKey: Value(idempotencyKey),
          localStatus: Value(localStatus),
          syncStatus: Value(syncStatus),
          metadataJson: Value(metadataJson),
          createdAt: Value(DateTime.utc(2026, 8, 14)),
          updatedAt: Value(DateTime.utc(2026, 8, 14)),
        ),
      );
}

Future<void> _insertSession(
  AppDatabase db, {
  required String id,
  String cashRegisterId = 'register-x',
  double opening = 20,
  String localStatus = 'synced',
  SyncStatus syncStatus = SyncStatus.synced,
}) {
  return db.into(db.cashSessions).insert(
        CashSessionsCompanion.insert(
          id: id,
          businessId: const Value('business-a'),
          branchId: const Value('branch-x'),
          cashRegisterId: Value(cashRegisterId),
          openedByProfileId: const Value('profile-a'),
          openedAt: Value(DateTime.utc(2026, 8, 14)),
          openingCashAmount: Value(opening),
          localStatus: Value(localStatus),
          syncStatus: Value(syncStatus),
          createdAt: Value(DateTime.utc(2026, 8, 14)),
          updatedAt: Value(DateTime.utc(2026, 8, 14)),
        ),
      );
}

Future<void> _seedAuthoritativeReconciledSale(
  AppDatabase db, {
  bool includeExplicitMarker = true,
  String? cashTreatment,
}) async {
  const reconciliationId = '11111111-1111-4111-8111-111111111111';
  final resolvedAt = DateTime.utc(2026, 9, 2, 19, 18);
  final audit = jsonEncode({
    'business_id': 'business-a',
    'branch_id': 'branch-x',
    'sale_id': 'sale-r',
    'sale_reconciliation_id': reconciliationId,
    'local_resolution': 'intentional_stale_sale_reconciled',
    if (cashTreatment != null) 'cash_treatment': cashTreatment,
    if (includeExplicitMarker) 'superseded_by_sale_reconciliation': true,
    'destination_cash_session_id': 'session-s',
    'resolved_at': resolvedAt.toIso8601String(),
  });
  await _insertRegister(db, id: 'register-x');
  await _insertSession(db, id: 'session-s');
  await db.into(db.sales).insert(
        SalesCompanion.insert(
          id: 'sale-r',
          businessId: const Value('business-a'),
          userId: const Value('profile-a'),
          branchId: const Value('branch-x'),
          cashRegisterId: const Value('register-x'),
          cashSessionId: const Value('session-s'),
          subtotal: const Value(100),
          total: 100,
          paymentMethod: const Value('cash'),
          localStatus: const Value('synced'),
          metadataJson: Value(audit),
          syncStatus: const Value(SyncStatus.synced),
        ),
      );
  await db.into(db.saleItems).insert(
        SaleItemsCompanion.insert(
          id: 'item-r',
          saleId: const Value('sale-r'),
          productId: const Value('product-1'),
          productNameSnapshot: const Value('Product 1'),
          quantity: 1,
          unitPrice: 100,
          subtotal: 100,
          lineTotal: const Value(100),
          metadataJson: Value(audit),
          syncStatus: const Value(SyncStatus.synced),
        ),
      );
  await db.into(db.salePayments).insert(
        SalePaymentsCompanion.insert(
          id: 'payment-r',
          businessId: 'business-a',
          branchId: const Value('branch-x'),
          saleId: 'sale-r',
          paymentMethod: 'cash',
          amount: 100,
          localStatus: const Value('synced'),
          metadataJson: Value(audit),
          syncStatus: const Value(SyncStatus.synced),
        ),
      );
  await db.into(db.localProductStockBalances).insert(
        LocalProductStockBalancesCompanion.insert(
          id: 'balance-r',
          businessId: 'business-a',
          branchId: 'branch-x',
          productId: 'product-1',
          quantityOnHand: const Value(25),
          quantityAvailable: const Value(25),
          remoteQuantityOnHand: const Value(25),
          remoteQuantityAvailable: const Value(25),
        ),
      );
  for (final target in const {
    'sales': 'sale-r',
    'sale_items': 'item-r',
    'sale_payments': 'payment-r',
  }.entries) {
    await _insertOutbox(
      db,
      domain: 'pos',
      entityTable: target.key,
      entityId: target.value,
      batchStatus: 'partial',
      mutationStatus: 'skipped',
    );
    await db.customStatement(
      '''
      update local_sync_mutations
      set resolved_at = ?,
          error_code = 'superseded_by_sale_reconciliation',
          metadata_json = ?
      where id = ?
      ''',
      [resolvedAt.toIso8601String(), audit, 'mutation-${target.value}'],
    );
  }
}

Future<void> _insertPendingSale(
  AppDatabase db, {
  required String id,
  required double total,
  required String paymentId,
}) async {
  await db.into(db.sales).insert(
        SalesCompanion.insert(
          id: id,
          businessId: const Value('business-a'),
          userId: const Value('profile-a'),
          branchId: const Value('branch-x'),
          cashRegisterId: const Value('register-x'),
          cashSessionId: const Value('session-s'),
          subtotal: Value(total),
          total: total,
          paymentMethod: const Value('cash'),
          localStatus: const Value('dirty'),
          syncStatus: const Value(SyncStatus.pendingInsert),
        ),
      );
  await db.into(db.salePayments).insert(
        SalePaymentsCompanion.insert(
          id: paymentId,
          businessId: 'business-a',
          branchId: const Value('branch-x'),
          saleId: id,
          paymentMethod: 'cash',
          amount: total,
          localStatus: const Value('dirty'),
          syncStatus: const Value(SyncStatus.pendingInsert),
        ),
      );
}

Future<void> _insertOutbox(
  AppDatabase db, {
  required String domain,
  required String entityTable,
  required String entityId,
  String batchStatus = 'pending',
  String mutationStatus = 'pending',
}) async {
  final uploadedAt =
      batchStatus == 'completed' ? DateTime.utc(2026, 8, 15, 7) : null;
  final batchId = 'batch-$entityId';
  await db.into(db.localSyncBatches).insert(
        LocalSyncBatchesCompanion.insert(
          id: batchId,
          clientBatchId: 'client-$batchId',
          businessId: 'business-a',
          branchId: const Value('branch-x'),
          domain: domain,
          status: Value(batchStatus),
          mutationCount: const Value(1),
          uploadedAt: Value(uploadedAt),
        ),
      );
  await db.into(db.localSyncMutations).insert(
        LocalSyncMutationsCompanion.insert(
          id: 'mutation-$entityId',
          localSyncBatchId: Value(batchId),
          clientBatchId: Value('client-$batchId'),
          clientMutationId: 'client-mutation-$entityId',
          clientSequence: 1,
          businessId: 'business-a',
          branchId: const Value('branch-x'),
          entityTable: entityTable,
          entityId: entityId,
          operation: 'upsert',
          payloadJson: '{}',
          idempotencyKey: 'key-$entityId',
          status: Value(mutationStatus),
          uploadedAt: Value(uploadedAt),
        ),
      );
}

Future<Map<String, dynamic>?> _row(
  AppDatabase db,
  String table,
  String id,
) async {
  final row = await db.customSelect(
    'select * from $table where id = ? limit 1',
    variables: [Variable<String>(id)],
  ).getSingleOrNull();
  return row?.data;
}

Future<int> _count(AppDatabase db, String table) async {
  final row =
      await db.customSelect('select count(*) as count from $table').getSingle();
  return (row.data['count'] as num).toInt();
}

Future<List<Map<String, dynamic>>> _issues(AppDatabase db) {
  return ReconciliationIssueLocalDao(db).getIssues(
    profileId: 'profile-a',
    businessId: 'business-a',
    branchId: 'branch-x',
    domain: 'cash_pos',
  );
}

class _Harness {
  _Harness(
    AppDatabase database,
    List<Object> outcomes, {
    OperationalBootstrapCheckpointLocalDao? checkpointDao,
  }) {
    var call = 0;
    final seenDao = OperationalBootstrapSeenRecordLocalDao(database);
    final issueDao = ReconciliationIssueLocalDao(database);
    final localDao = CashPosReconciliationLocalDao(database);
    final applier = CashPosSnapshotApplier(
      localDao: localDao,
      seenRecordDao: seenDao,
      issueDao: issueDao,
    );
    final router = OperationalBootstrapPageApplierRouter(
      routes: {
        for (final dataset in CashPosSnapshotApplier.datasets)
          'cash_pos/$dataset': applier,
      },
      dependencyOrder: const {'cash_pos': CashPosSnapshotApplier.datasets},
    );
    download = OperationalBootstrapDownloadService(
      database: database,
      remoteDataSource: OperationalBootstrapRemoteDataSource.withInvoker(
        (_) async {
          final outcome = outcomes[call++];
          if (outcome is Exception) throw outcome;
          return outcome;
        },
      ),
      checkpointDao:
          checkpointDao ?? OperationalBootstrapCheckpointLocalDao(database),
      seenRecordDao: seenDao,
      reconciliationIssueDao: issueDao,
      pageApplier: router,
      authorizationContextDao: AuthorizedOperationalContextLocalDao(database),
      maxTransientRetries: 0,
      retryDelay: (_) async {},
    );
    recovery = CashPosRecoveryService(
      downloadService: download,
      reconciliationDao: localDao,
      cashSessionDao: CashSessionLocalDao(database),
      issueDao: issueDao,
    );
  }

  late final OperationalBootstrapDownloadService download;
  late final CashPosRecoveryService recovery;
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
