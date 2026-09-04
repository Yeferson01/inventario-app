import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_models.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_service.dart';
import 'package:inventario_frontend/features/cash/data/datasources/cash_session_local_dao.dart';
import 'package:inventario_frontend/features/cash/data/datasources/cash_session_remote_datasource.dart';
import 'package:inventario_frontend/features/cash/data/models/cash_session_remote_models.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';
import 'package:inventario_frontend/features/sync/application/pos_inventory_failure_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/pos_sync_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/datasources/reconciliation_issue_local_dao.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.executor(NativeDatabase.memory());
    await _seed(database);
  });

  tearDown(() => database.close());

  test('1 remote closed old session is projected before new session opens',
      () async {
    await _insertSession(database, 'session-old');
    final service = _service(
      database,
      rpc: _rpcOpen('session-next', reused: false),
      rows: [_tableClosed('session-old')],
    );

    final result = await service.openCashSession(_input);

    expect(result.cashSession.id, 'session-next');
    expect(result.reusedOpenSession, isFalse);
    expect((await _session(database, 'session-old'))?['status'], 'closed');
    expect(await _openIds(database), ['session-next']);
  });

  test('2 existing remote next session is reused after old converges',
      () async {
    await _insertSession(database, 'session-old');
    final service = _service(
      database,
      rpc: _rpcOpen('session-next', reused: true),
      rows: [_tableClosed('session-old')],
    );

    final result = await service.openCashSession(_input);

    expect(result.reusedOpenSession, isTrue);
    expect((await _session(database, 'session-old'))?['closed_at'], isNotNull);
    expect(await _openIds(database), ['session-next']);
  });

  test('3 retry after remote success reuses same session and converges',
      () async {
    await _insertSession(database, 'session-old');
    var rpcCalls = 0;
    var lookupCalls = 0;
    final service = CashSessionLocalService(
      dao: CashSessionLocalDao(database),
      remoteDataSource: CashSessionRemoteDataSource.withInvoker(
        (functionName, parameters) async {
          rpcCalls++;
          return _rpcOpen('session-next', reused: rpcCalls > 1);
        },
        rowsLoader: ({
          required businessId,
          required branchId,
          required cashRegisterId,
          required cashSessionIds,
        }) async {
          lookupCalls++;
          if (lookupCalls == 1) throw TimeoutException('projection lookup');
          return [_tableClosed('session-old')];
        },
      ),
    );

    await expectLater(
      service.openCashSession(_input),
      throwsA(isA<CashRemoteStateUnavailableException>()),
    );
    expect(await _openIds(database), ['session-old']);

    final retry = await service.openCashSession(_input);

    expect(retry.cashSession.id, 'session-next');
    expect(retry.reusedOpenSession, isTrue);
    expect(rpcCalls, 2);
    expect(await _openIds(database), ['session-next']);
  });

  test('4 currently open remote session is reused without creating next',
      () async {
    await _insertSession(database, 'session-old');
    var lookups = 0;
    final service = CashSessionLocalService(
      dao: CashSessionLocalDao(database),
      remoteDataSource: CashSessionRemoteDataSource.withInvoker(
        (functionName, parameters) async =>
            _rpcOpen('session-old', reused: true),
        rowsLoader: ({
          required businessId,
          required branchId,
          required cashRegisterId,
          required cashSessionIds,
        }) async {
          lookups++;
          return const [];
        },
      ),
    );

    final result = await service.openCashSession(_input);

    expect(result.cashSession.id, 'session-old');
    expect(result.reusedOpenSession, isTrue);
    expect(lookups, 0);
    expect(await _openIds(database), ['session-old']);
  });

  test('5 two local opens converge to the sole remote canonical session',
      () async {
    await database.customStatement(
      'drop index ux_cash_sessions_one_open_per_register',
    );
    await _insertSession(database, 'session-old');
    await _insertSession(database, 'session-canonical');
    final service = _service(
      database,
      rpc: _rpcOpen('session-canonical', reused: true),
      rows: [_tableClosed('session-old')],
    );

    await service.openCashSession(_input);

    expect((await _session(database, 'session-old'))?['status'], 'closed');
    expect(await _openIds(database), ['session-canonical']);
  });

  test('6 concurrent opens are single-flight per register', () async {
    final rpc = Completer<Object?>();
    var rpcCalls = 0;
    final service = CashSessionLocalService(
      dao: CashSessionLocalDao(database),
      remoteDataSource: CashSessionRemoteDataSource.withInvoker(
        (functionName, parameters) {
          rpcCalls++;
          return rpc.future;
        },
        rowsLoader: ({
          required businessId,
          required branchId,
          required cashRegisterId,
          required cashSessionIds,
        }) async =>
            const [],
      ),
    );

    final first = service.openCashSession(_input);
    final second = service.openCashSession(_input);
    rpc.complete(_rpcOpen('session-next', reused: false));
    final results = await Future.wait([first, second]);

    expect(rpcCalls, 1);
    expect(results.map((result) => result.cashSession.id).toSet(), {
      'session-next',
    });
    expect(await _openIds(database), ['session-next']);
  });

  test('7 runtime projection receives the canonical session after convergence',
      () async {
    await _insertSession(database, 'session-old');
    String? projectedSessionId;
    final service = CashSessionLocalService(
      dao: CashSessionLocalDao(database),
      remoteDataSource: _remote(
        rpc: _rpcOpen('session-next', reused: true),
        rows: [_tableClosed('session-old')],
      ),
      runtimeProjector: (input, session) async {
        expect(input.businessId, 'business-a');
        expect(input.branchId, 'branch-a');
        expect(input.cashRegisterId, 'register-a');
        projectedSessionId = session.id;
      },
    );

    await service.openCashSession(_input);

    expect(projectedSessionId, 'session-next');
    expect(await _openIds(database), ['session-next']);
  });

  test('8 remote S1 is materialized and reused without local S2', () async {
    final service = CashSessionLocalService(
      dao: CashSessionLocalDao(database),
      remoteDataSource: CashSessionRemoteDataSource.withInvoker(
        (functionName, parameters) async => _openSnapshot,
      ),
    );

    final result = await service.openCashSession(_input);

    expect(result.cashSession.id, 'session-s1');
    expect(result.reusedOpenSession, isTrue);
    expect(await _count(database, 'cash_sessions'), 1);
  });

  test('9 unavailable remote state creates no local session', () async {
    final service = CashSessionLocalService(
      dao: CashSessionLocalDao(database),
      remoteDataSource: CashSessionRemoteDataSource.withInvoker(
        (functionName, parameters) async => throw TimeoutException('offline'),
      ),
    );

    await expectLater(
      service.openCashSession(_input),
      throwsA(isA<CashRemoteStateUnavailableException>()),
    );
    expect(await _count(database, 'cash_sessions'), 0);
  });

  test('10 remote POS inventory rejection opens scoped blocking issue',
      () async {
    await database.customStatement('''
      insert into products (id, business_id, name, sale_price)
      values ('product-a', 'business-a', 'Product A', 1000)
    ''');
    await database.customStatement('''
      insert into local_inventory_movements (
        id, business_id, branch_id, product_id, movement_type,
        quantity_change, source_type, source_id, idempotency_key,
        local_status, occurred_at
      ) values (
        'movement-a', 'business-a', 'branch-a', 'product-a', 'sale',
        -1, 'sale', 'sale-a', 'install-a:movement-a',
        'synced', CURRENT_TIMESTAMP
      )
    ''');
    final issueDao = ReconciliationIssueLocalDao(database);
    final service = PosInventoryFailureReconciliationService(
      saleDao: PosLocalSaleDao(database),
      issueDao: issueDao,
    );

    final recorded = await service.recordFailures(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
      failures: const [
        PosInventoryApplyFailure(
          serverBatchId: 'batch-a',
          saleId: 'sale-a',
          message: 'Insufficient stock for product product-a',
        ),
      ],
    );
    final issues = await issueDao.getOpenBlockingIssues(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
    );

    expect(recorded, 1);
    expect(issues, hasLength(1));
    expect(issues.single['issue_type'], 'inventory_movement_rejected');
    expect(issues.single['entity_id'], 'movement-a');
    expect(issues.single['metadata_json'], contains('product-a'));
  });
}

const _input = OpenCashSessionInput(
  businessId: 'business-a',
  branchId: 'branch-a',
  profileId: 'profile-a',
  cashRegisterId: 'register-a',
  openingCashAmount: 999,
  appDeviceId: 'device-b',
  deviceInstallationId: 'install-b',
);

final _openSnapshot = <String, Object?>{
  'cash_session_id': 'session-s1',
  'business_id': 'business-a',
  'branch_id': 'branch-a',
  'cash_register_id': 'register-a',
  'opened_by_profile_id': 'profile-a',
  'closed_by_profile_id': null,
  'opened_at': '2026-08-30T12:00:00Z',
  'closed_at': null,
  'opening_cash_amount': 50,
  'expected_cash_amount': null,
  'closing_cash_amount': null,
  'difference_amount': null,
  'status': 'open',
  'version': 1,
  'notes': null,
  'created_at': '2026-08-30T12:00:00Z',
  'updated_at': '2026-08-30T12:00:00Z',
  'reused_open_session': true,
};

CashSessionLocalService _service(
  AppDatabase database, {
  required Map<String, Object?> rpc,
  required List<Map<String, Object?>> rows,
}) {
  return CashSessionLocalService(
    dao: CashSessionLocalDao(database),
    remoteDataSource: _remote(rpc: rpc, rows: rows),
  );
}

CashSessionRemoteDataSource _remote({
  required Map<String, Object?> rpc,
  required List<Map<String, Object?>> rows,
}) {
  return CashSessionRemoteDataSource.withInvoker(
    (functionName, parameters) async => rpc,
    rowsLoader: ({
      required businessId,
      required branchId,
      required cashRegisterId,
      required cashSessionIds,
    }) async =>
        rows
            .where((row) => cashSessionIds.contains(row['id']))
            .toList(growable: false),
  );
}

Map<String, Object?> _rpcOpen(String id, {required bool reused}) => {
      ..._openSnapshot,
      'cash_session_id': id,
      'reused_open_session': reused,
    };

Map<String, Object?> _tableClosed(String id) => {
      'id': id,
      'business_id': 'business-a',
      'branch_id': 'branch-a',
      'cash_register_id': 'register-a',
      'opened_by': 'profile-a',
      'closed_by': 'profile-a',
      'opened_at': '2026-08-30T10:00:00Z',
      'closed_at': '2026-08-30T11:00:00Z',
      'opening_amount': 50,
      'expected_closing_amount': 50,
      'actual_closing_amount': 50,
      'difference_amount': 0,
      'status': 'closed',
      'version': 2,
      'notes': null,
      'created_at': '2026-08-30T10:00:00Z',
      'updated_at': '2026-08-30T11:00:00Z',
      'deleted_at': null,
    };

Future<void> _insertSession(AppDatabase database, String id) async {
  await database.customStatement('''
    insert into cash_sessions (
      id, business_id, branch_id, cash_register_id, opened_by_profile_id,
      opened_at, opening_cash_amount, status, local_status, sync_status,
      version, created_at, updated_at
    ) values (
      ?, 'business-a', 'branch-a', 'register-a', 'profile-a',
      '2026-08-30T10:00:00Z', 50, 'open', 'synced', 0,
      1, '2026-08-30T10:00:00Z', '2026-08-30T10:00:00Z'
    )
  ''', [id]);
}

Future<Map<String, dynamic>?> _session(
  AppDatabase database,
  String id,
) {
  return CashSessionLocalDao(database).getCashSessionById(id: id);
}

Future<List<String>> _openIds(AppDatabase database) async {
  final rows =
      await CashSessionLocalDao(database).getOpenCashSessionsForRegister(
    businessId: 'business-a',
    branchId: 'branch-a',
    cashRegisterId: 'register-a',
  );
  return rows.map((row) => row['id'].toString()).toList(growable: false);
}

Future<void> _seed(AppDatabase database) async {
  await database.customStatement('''
    insert into businesses (id, name) values ('business-a', 'Business A')
  ''');
  await database.customStatement('''
    insert into branches (id, business_id, name)
    values ('branch-a', 'business-a', 'Principal')
  ''');
  await database.customStatement('''
    insert into profiles (id, full_name) values ('profile-a', 'Profile A')
  ''');
  await database.customStatement('''
    insert into cash_registers (
      id, business_id, branch_id, name, code, status, local_status
    ) values (
      'register-a', 'business-a', 'branch-a', 'Principal', 'MAIN',
      'active', 'synced'
    )
  ''');
}

Future<int> _count(AppDatabase database, String table) async {
  final row = await database
      .customSelect('select count(*) as count from $table')
      .getSingle();
  return (row.data['count'] as num).toInt();
}
