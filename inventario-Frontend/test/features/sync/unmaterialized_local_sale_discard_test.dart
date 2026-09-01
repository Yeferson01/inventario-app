import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/sales/application/pos_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';
import 'package:inventario_frontend/features/sync/application/local_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sync/application/unmaterialized_local_sale_discard_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/local_sync_outbox_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/pos_sync_remote_datasource.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.executor(NativeDatabase.memory());
    await _seedRejectedSale(database);
  });
  tearDown(() => database.close());

  test('remote evidence exists aborts without touching local state', () async {
    await database.customStatement(
      "delete from local_reconciliation_issues where id = 'issue-sale'",
    );
    final service = _service(database, const _Evidence(saleRows: 1));

    await expectLater(
      service.discard(_input()),
      throwsA(
        isA<UnmaterializedSaleDiscardException>().having(
          (error) => error.kind,
          'kind',
          UnmaterializedSaleDiscardFailureKind.remoteMaterializationFound,
        ),
      ),
    );

    expect(await _saleDeletedAt(database), isNull);
    expect(await _balance(database), 25);
  });

  test('remote unavailable aborts without touching local state', () async {
    final service = UnmaterializedLocalSaleDiscardService(
      localDao: PosLocalSaleDao(database),
      remoteVerifier: ({
        required businessId,
        required branchId,
        required saleId,
      }) async =>
          throw StateError('network unavailable'),
    );

    await expectLater(
      service.discard(_input()),
      throwsA(
        isA<UnmaterializedSaleDiscardException>().having(
          (error) => error.kind,
          'kind',
          UnmaterializedSaleDiscardFailureKind.remoteUnavailable,
        ),
      ),
    );

    expect(await _saleDeletedAt(database), isNull);
    expect(await _balance(database), 25);
  });

  test('valid discard tombstones the aggregate and restores exact stock',
      () async {
    final result =
        await _service(database, const _Evidence()).discard(_input());

    expect(result.localResult.alreadyDiscarded, isFalse);
    expect(result.localResult.restoredQuantityByProduct, {'product-a': 1});
    expect(await _balance(database), 26);
    for (final table in const [
      'sales',
      'sale_items',
      'sale_payments',
      'local_inventory_movements',
    ]) {
      final row = await database
          .customSelect('select * from $table limit 1')
          .getSingle();
      expect(row.data['deleted_at'], isNotNull, reason: table);
    }
    final mutations = await database
        .customSelect('select * from local_sync_mutations order by id')
        .get();
    expect(mutations, hasLength(3));
    expect(mutations.every((row) => row.data['status'] == 'conflict'), isTrue);
    expect(mutations.every((row) => row.data['resolved_at'] != null), isTrue);
    final batch = await database
        .customSelect("select * from local_sync_batches where id = 'batch-a'")
        .getSingle();
    expect(batch.data['status'], 'partial');
    expect(
      batch.data['metadata_json'],
      contains('unmaterialized_sale_discarded'),
    );
    final openIssues = await database
        .customSelect(
          "select * from local_reconciliation_issues where status = 'open'",
        )
        .get();
    expect(openIssues, isEmpty);
    expect(await _saleIssueStatus(database), 'resolved');
  });

  test('valid discard succeeds without a local cash-session blocker', () async {
    await database.customStatement(
      "delete from local_reconciliation_issues where id = 'issue-sale'",
    );

    final result =
        await _service(database, const _Evidence()).discard(_input());

    expect(result.localResult.alreadyDiscarded, isFalse);
    expect(await _balance(database), 26);
    expect(await _saleIssueStatus(database), isNull);
    final sale = await database
        .customSelect(
          "select metadata_json from sales where id = 'sale-a'",
        )
        .getSingle();
    expect(
      sale.data['metadata_json'],
      contains('"local_blocker_state_before_discard":"missing"'),
    );
  });

  test('discard retry is idempotent and does not restore stock twice',
      () async {
    final service = _service(database, const _Evidence());

    await service.discard(_input());
    final retry = await service.discard(_input());

    expect(retry.localResult.alreadyDiscarded, isTrue);
    expect(await _balance(database), 26);
  });

  test('discarded sale is not enqueued again', () async {
    await _service(database, const _Evidence()).discard(_input());
    final service = PosSyncOutboxService(
      dao: PosLocalSaleDao(database),
      outboxService: LocalSyncOutboxService(LocalSyncOutboxDao(database)),
    );

    final result = await service.enqueuePendingPosSales(
      businessId: 'business-a',
      branchId: 'branch-a',
      profileId: 'profile-a',
      appDeviceId: 'device-a',
      deviceInstallationId: 'installation-a',
    );

    expect(result.salesChecked, 0);
    expect(result.salesEnqueued, 0);
    final mutations = await database
        .customSelect('select count(*) as count from local_sync_mutations')
        .getSingle();
    expect(mutations.data['count'], 3);
  });
}

class _Evidence {
  const _Evidence({this.saleRows = 0});

  final int saleRows;
}

UnmaterializedLocalSaleDiscardService _service(
  AppDatabase database,
  _Evidence source,
) {
  return UnmaterializedLocalSaleDiscardService(
    localDao: PosLocalSaleDao(database),
    remoteVerifier: ({
      required businessId,
      required branchId,
      required saleId,
    }) async {
      return UnmaterializedSaleRemoteEvidence(
        businessId: businessId,
        branchId: branchId,
        saleId: saleId,
        saleRows: source.saleRows,
        saleItemRows: 0,
        salePaymentRows: 0,
        inventoryMovementRows: 0,
        expectedConflictFound: true,
        conflictReasons: const {'closed'},
      );
    },
  );
}

DiscardUnmaterializedLocalSaleInput _input() {
  return const DiscardUnmaterializedLocalSaleInput(
    profileId: 'profile-a',
    businessId: 'business-a',
    branchId: 'branch-a',
    saleId: 'sale-a',
    confirmedSaleDidNotOccur: true,
    reason: 'Confirmed test sale did not occur.',
  );
}

Future<Object?> _saleDeletedAt(AppDatabase database) async {
  final row = await database
      .customSelect("select deleted_at from sales where id = 'sale-a'")
      .getSingle();
  return row.data['deleted_at'];
}

Future<int> _balance(AppDatabase database) async {
  final row = await database
      .customSelect(
        "select quantity_on_hand from local_product_stock_balances where product_id = 'product-a'",
      )
      .getSingle();
  return (row.data['quantity_on_hand'] as num).toInt();
}

Future<String?> _saleIssueStatus(AppDatabase database) async {
  final row = await database
      .customSelect(
        "select status from local_reconciliation_issues where id = 'issue-sale'",
      )
      .getSingleOrNull();
  return row?.data['status']?.toString();
}

Future<void> _seedRejectedSale(AppDatabase database) async {
  await database.customStatement('''
    insert into businesses (id, name) values ('business-a', 'Business A');
    insert into branches (id, business_id, name)
      values ('branch-a', 'business-a', 'Principal');
    insert into profiles (id, full_name) values ('profile-a', 'Profile A');
    insert into products (id, business_id, name, sale_price)
      values ('product-a', 'business-a', 'Product A', 10);
    insert into cash_registers (
      id, business_id, branch_id, name, code, status, local_status
    ) values (
      'register-a', 'business-a', 'branch-a', 'Principal', 'MAIN',
      'active', 'synced'
    );
    insert into cash_sessions (
      id, business_id, branch_id, cash_register_id, opened_at,
      opening_cash_amount, status, local_status, sync_status
    ) values (
      'session-a', 'business-a', 'branch-a', 'register-a', CURRENT_TIMESTAMP,
      50, 'closed', 'synced', 0
    );
    insert into local_product_stock_balances (
      id, business_id, branch_id, product_id, quantity_on_hand,
      quantity_available, remote_quantity_on_hand, remote_quantity_available
    ) values (
      'balance-a', 'business-a', 'branch-a', 'product-a', 25, 25, 26, 26
    );
    insert into sales (
      id, business_id, user_id, branch_id, cash_register_id, cash_session_id,
      total, payment_method, status, local_status, sync_status
    ) values (
      'sale-a', 'business-a', 'profile-a', 'branch-a', 'register-a',
      'session-a', 10, 'cash', 'completed', 'dirty', 1
    );
    insert into sale_items (
      id, sale_id, product_id, quantity, unit_price, subtotal, line_total,
      sync_status
    ) values ('item-a', 'sale-a', 'product-a', 1, 10, 10, 10, 1);
    insert into sale_payments (
      id, business_id, branch_id, sale_id, payment_method, amount,
      status, local_status, sync_status
    ) values (
      'payment-a', 'business-a', 'branch-a', 'sale-a', 'cash', 10,
      'completed', 'dirty', 1
    );
    insert into local_inventory_movements (
      id, business_id, branch_id, product_id, movement_type, quantity_change,
      source_type, source_id, idempotency_key, sync_status, local_status,
      occurred_at, metadata_json
    ) values (
      'movement-a', 'business-a', 'branch-a', 'product-a', 'sale', -1,
      'sale', 'sale-a', 'movement-a-key', 1, 'dirty', CURRENT_TIMESTAMP,
      '{"sale_item_id":"item-a"}'
    );
    insert into local_sync_batches (
      id, client_batch_id, business_id, branch_id, profile_id, domain,
      status, mutation_count
    ) values (
      'batch-a', 'client-batch-a', 'business-a', 'branch-a', 'profile-a',
      'pos', 'partial', 3
    );
    insert into local_sync_mutations (
      id, local_sync_batch_id, client_batch_id, client_mutation_id,
      client_sequence, business_id, branch_id, profile_id, entity_table,
      entity_id, operation, payload_json, idempotency_key, status, error_code
    ) values
      ('mutation-sale', 'batch-a', 'client-batch-a', 'client-sale', 1,
       'business-a', 'branch-a', 'profile-a', 'sales', 'sale-a', 'insert',
       '{}', 'sale-key', 'conflict', 'remote_pos_batch_partial'),
      ('mutation-item', 'batch-a', 'client-batch-a', 'client-item', 2,
       'business-a', 'branch-a', 'profile-a', 'sale_items', 'item-a', 'insert',
       '{}', 'item-key', 'conflict', 'remote_pos_batch_partial'),
      ('mutation-payment', 'batch-a', 'client-batch-a', 'client-payment', 3,
       'business-a', 'branch-a', 'profile-a', 'sale_payments', 'payment-a',
       'insert', '{}', 'payment-key', 'conflict', 'remote_pos_batch_partial');
    insert into local_reconciliation_issues (
      id, profile_id, business_id, branch_id, domain, entity_type, entity_id,
      issue_type, severity, status, message
    ) values
      ('issue-sale', 'profile-a', 'business-a', 'branch-a', 'cash_pos',
       'sales', 'sale-a', 'sale_cash_session_rejected', 'blocking', 'open',
       'Rejected stale session'),
      ('issue-movement', 'profile-a', 'business-a', 'branch-a',
       'inventory_balance', 'inventory_movements', 'movement-a',
       'terminal_incompatible_inventory_movement', 'blocking', 'open',
       'Rejected movement');
  ''');
}
