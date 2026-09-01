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

  test('6 remote S1 is materialized and reused without local S2', () async {
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

  test('7 unavailable remote state creates no local session', () async {
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

  test('8 remote POS inventory rejection opens scoped blocking issue',
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
