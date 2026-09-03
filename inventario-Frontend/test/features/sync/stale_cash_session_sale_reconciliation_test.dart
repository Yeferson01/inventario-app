import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/sync/application/pos_cash_session_failure_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/pos_sync_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/datasources/reconciliation_issue_local_dao.dart';

void main() {
  test('rejected stale-session Sale opens one blocker and is preserved',
      () async {
    final database = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(database.close);
    await _seed(database);
    final service = PosCashSessionFailureReconciliationService(
      issueDao: ReconciliationIssueLocalDao(database),
    );
    const failure = PosCashSessionApplyFailure(
      syncConflictId: 'conflict-a',
      serverBatchId: 'batch-a',
      serverMutationId: 'mutation-a',
      saleId: 'sale-a',
      cashSessionId: 'session-a',
      cashRegisterId: 'register-a',
      branchId: 'branch-a',
      reason: 'closed',
      message: 'Sale cash session is unavailable.',
    );

    await service.recordFailures(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
      failures: const [failure],
    );
    await service.recordFailures(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
      failures: const [failure],
    );

    final sale = await database
        .customSelect(
          "select * from sales where id = 'sale-a'",
        )
        .getSingleOrNull();
    final issues =
        await ReconciliationIssueLocalDao(database).getOpenBlockingIssues(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
    );

    expect(sale, isNotNull);
    expect(sale!.data['local_status'], 'dirty');
    expect(issues, hasLength(1));
    expect(issues.single['domain'], 'cash_pos');
    expect(issues.single['entity_type'], 'sales');
    expect(issues.single['entity_id'], 'sale-a');
    expect(issues.single['issue_type'], 'sale_cash_session_rejected');
    expect(issues.single['severity'], 'blocking');
    expect(
        issues.single['metadata_json'], contains('"remote_reason":"closed"'));
  });
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
  await database.customStatement('''
    insert into cash_sessions (
      id, business_id, branch_id, cash_register_id, opened_by_profile_id,
      opened_at, opening_cash_amount, status, local_status, sync_status
    ) values (
      'session-a', 'business-a', 'branch-a', 'register-a', 'profile-a',
      CURRENT_TIMESTAMP, 50, 'open', 'synced', 0
    )
  ''');
  await database.customStatement('''
    insert into sales (
      id, business_id, user_id, branch_id, cash_register_id, cash_session_id,
      total, payment_method, status, local_status, sync_status
    ) values (
      'sale-a', 'business-a', 'profile-a', 'branch-a', 'register-a',
      'session-a', 10, 'cash', 'completed', 'dirty', 1
    )
  ''');
}
