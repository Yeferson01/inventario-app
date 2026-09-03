import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.executor(NativeDatabase.memory());
    await _seedContext(database);
  });

  tearDown(() => database.close());

  test('pending stale Sale parses its ISO String created_at', () async {
    const timestamp = '2026-09-01T14:15:16.123456Z';
    await _seedRawPendingSale(
      database,
      saleId: 'sale-iso',
      issueId: 'issue-iso',
      createdAt: timestamp,
    );

    final pending = await PosLocalSaleDao(
      database,
    ).loadPendingStaleCashSessionSales(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
    );

    expect(pending, hasLength(1));
    expect(pending.single.createdAt, DateTime.parse(timestamp));
  });

  test('pending stale Sale accepts a DateTime written through Drift', () async {
    final timestamp = DateTime.utc(2026, 9, 1, 14, 16, 17);
    await database.into(database.sales).insert(
          SalesCompanion.insert(
            id: 'sale-datetime',
            businessId: const Value('business-a'),
            branchId: const Value('branch-a'),
            cashRegisterId: const Value('register-a'),
            cashSessionId: const Value('session-s1'),
            total: 20,
            localStatus: const Value('dirty'),
            syncStatus: const Value(SyncStatus.pendingInsert),
            createdAt: Value(timestamp),
          ),
        );
    await _seedChildrenAndIssue(
      database,
      saleId: 'sale-datetime',
      issueId: 'issue-datetime',
      total: 20,
    );

    final pending = await PosLocalSaleDao(
      database,
    ).loadPendingStaleCashSessionSales(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
    );

    expect(pending, hasLength(1));
    expect(pending.single.createdAt, timestamp);
  });
}

Future<void> _seedContext(AppDatabase database) async {
  await database.customStatement('''
    insert into businesses (id, name) values ('business-a', 'Business A');
    insert into branches (id, business_id, name)
    values ('branch-a', 'business-a', 'Principal');
  ''');
}

Future<void> _seedRawPendingSale(
  AppDatabase database, {
  required String saleId,
  required String issueId,
  required String createdAt,
}) async {
  await database.customStatement(
    '''
    insert into sales (
      id, business_id, branch_id, cash_register_id, cash_session_id,
      total, local_status, sync_status, created_at
    ) values (?, 'business-a', 'branch-a', 'register-a', 'session-s1',
      10, 'dirty', 1, ?)
    ''',
    [saleId, createdAt],
  );
  await _seedChildrenAndIssue(
    database,
    saleId: saleId,
    issueId: issueId,
    total: 10,
  );
}

Future<void> _seedChildrenAndIssue(
  AppDatabase database, {
  required String saleId,
  required String issueId,
  required double total,
}) async {
  await database.customStatement(
    '''
    insert into sale_items (
      id, sale_id, product_name_snapshot, quantity, unit_price, subtotal,
      line_total
    ) values (?, ?, 'Producto A', 1, ?, ?, ?)
    ''',
    ['item-$saleId', saleId, total, total, total],
  );
  await database.customStatement(
    '''
    insert into sale_payments (
      id, business_id, branch_id, sale_id, payment_method, amount,
      status, local_status, sync_status
    ) values (?, 'business-a', 'branch-a', ?, 'cash', ?,
      'completed', 'dirty', 1)
    ''',
    ['payment-$saleId', saleId, total],
  );
  await database.customStatement(
    '''
    insert into local_reconciliation_issues (
      id, profile_id, business_id, branch_id, domain, entity_type, entity_id,
      issue_type, severity, status, message, metadata_json
    ) values (?, 'profile-a', 'business-a', 'branch-a', 'cash_pos', 'sales', ?,
      'sale_cash_session_rejected', 'blocking', 'open', 'Rejected closed',
      '{"remote_reason":"closed","cash_session_id":"session-s1","cash_register_id":"register-a"}')
    ''',
    [issueId, saleId],
  );
}
