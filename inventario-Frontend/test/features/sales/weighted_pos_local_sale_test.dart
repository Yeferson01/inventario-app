import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/models/product_sale_mode.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_models.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_service.dart';
import 'package:inventario_frontend/features/sales/application/pos_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';
import 'package:inventario_frontend/features/cash/data/datasources/cash_session_local_dao.dart';
import 'package:inventario_frontend/features/sync/application/local_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sync/application/pos_sync_upload_service.dart';
import 'package:inventario_frontend/features/sync/application/pos_cash_session_failure_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/application/pos_inventory_failure_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/local_sync_outbox_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/pos_sync_remote_datasource.dart';

void main() {
  test('735 g uses W2A and W2B with one atomic local ledger', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);

    final sale = await fixture.sellWeight(735);
    expect(sale.totalCents, 1764000);
    expect(sale.total, 17640);
    final item = await fixture.item(sale.lines.single.itemId);
    expect(item['sale_mode_snapshot'], 'weight');
    expect(item['quantity'], 735);
    expect(item['price_basis_quantity_snapshot'], 500);
    expect(item['price_cents_snapshot'], 1200000);
    expect(item['line_total_cents'], 1764000);
    expect(item['cogs_cents'], 128908);
    expect(item['unit_cost_snapshot'], null);
    final balance = await fixture.weightBalance();
    expect(balance['quantity_on_hand'], 12265);
    expect(balance['quantity_available'], 12265);
    expect(balance['cost_basis_cents'], 2151092);
    final movement = await fixture.row(
        'local_inventory_movements', sale.lines.single.inventoryMovementId);
    expect(movement['quantity_change'], -735);
    expect(movement['cost_effect_cents'], -128908);
    expect(movement['source_id'], sale.saleId);
    final payment = await fixture.database.customSelect(
      'select amount, metadata_json from sale_payments where sale_id = ?',
      variables: [Variable<String>(sale.saleId)],
    ).getSingle();
    expect(payment.read<double>('amount'), 17640);
    expect(jsonDecode(payment.read<String>('metadata_json'))['amount_cents'],
        1764000);
    final persistedSale = await fixture.row('sales', sale.saleId);
    expect(persistedSale['cash_session_id'], 'cash-session');
    expect(
        jsonDecode(persistedSale['metadata_json'] as String)[
            'monetary_contract_version'],
        'exact_weight_sale_v1');

    await fixture.enqueue();
    final payload = await fixture.itemPayload(sale.lines.single.itemId);
    expect(payload['quantity'], 735);
    expect(payload['price_basis_quantity_snapshot'], 500);
    expect(payload['price_cents_snapshot'], 1200000);
    expect(payload['line_total_cents'], 1764000);
    expect(payload['cogs_cents'], 128908);
    expect(payload['cogs_source'], 'local_projection_not_authoritative');
    await fixture.enqueue();
    expect(await fixture.count('local_inventory_movements'), 1);
    expect(await fixture.count('local_sync_mutations'), 3);
  });

  test('3 g at COP 12.001 per 500 g is exactly 7201 cents', () async {
    final fixture = await _Fixture.create(priceCents: 1200100);
    addTearDown(fixture.close);
    final sale = await fixture.sellWeight(3);
    expect(sale.totalCents, 7201);
    expect(sale.total, 72.01);
    expect((await fixture.item(sale.lines.single.itemId))['line_total_cents'],
        7201);
  });

  test('full depletion consumes every remaining cost cent', () async {
    final fixture = await _Fixture.create(quantity: 735, costBasis: 228001);
    addTearDown(fixture.close);
    final sale = await fixture.sellWeight(735);
    expect(
        (await fixture.item(sale.lines.single.itemId))['cogs_cents'], 228001);
    final balance = await fixture.weightBalance();
    expect(balance['quantity_on_hand'], 0);
    expect(balance['cost_basis_cents'], 0);
  });

  for (final cost in <int?>[0, null]) {
    test('cost basis $cost remains ${cost == null ? 'unknown' : 'zero'}',
        () async {
      final fixture = await _Fixture.create(costBasis: cost);
      addTearDown(fixture.close);
      final sale = await fixture.sellWeight(735);
      expect(
          (await fixture.item(sale.lines.single.itemId))['cogs_cents'], cost);
      expect((await fixture.weightBalance())['cost_basis_cents'], cost);
      expect(sale.totalCents, 1764000);
    });
  }

  test('insufficient available grams rolls back sale and movement', () async {
    final fixture = await _Fixture.create(available: 500);
    addTearDown(fixture.close);
    await expectLater(fixture.sellWeight(735), throwsStateError);
    expect(await fixture.count('sales'), 0);
    expect(await fixture.count('local_inventory_movements'), 0);
    expect((await fixture.weightBalance())['quantity_on_hand'], 13000);
  });

  test('two lines for the same product cannot oversell within one sale',
      () async {
    final fixture = await _Fixture.create(quantity: 1000);
    addTearDown(fixture.close);
    await expectLater(
      fixture.sell([
        const PosLocalSaleItemInput(
          productId: 'weight-product',
          quantity: 735,
          saleMode: ProductSaleMode.weight,
        ),
        const PosLocalSaleItemInput(
          productId: 'weight-product',
          quantity: 735,
          saleMode: ProductSaleMode.weight,
        ),
      ]),
      throwsA(anyOf(isA<RangeError>(), isA<StateError>())),
    );
    expect(await fixture.count('sales'), 0);
    expect(await fixture.count('sale_items'), 0);
    expect(await fixture.count('local_inventory_movements'), 0);
    expect((await fixture.weightBalance())['quantity_on_hand'], 1000);
  });

  test('product mode and basis mismatch fail closed', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await expectLater(
      fixture.sell([
        const PosLocalSaleItemInput(
          productId: 'unit-product',
          quantity: 1,
          saleMode: ProductSaleMode.weight,
        )
      ]),
      throwsStateError,
    );
    await expectLater(
      fixture.sellWeight(735, basis: 1000),
      throwsStateError,
    );
    expect(await fixture.count('sales'), 0);
  });

  test('WEIGHT price projection mismatch does not create a sale', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.database.customStatement(
      'update products set sale_price = 9000 where id = ?',
      ['weight-product'],
    );
    await expectLater(fixture.sellWeight(735), throwsStateError);
    expect(await fixture.count('sales'), 0);
  });

  test('mixed UNIT and WEIGHT lines sum exact cents', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final sale = await fixture.sell([
      const PosLocalSaleItemInput(productId: 'unit-product', quantity: 2),
      const PosLocalSaleItemInput(
        productId: 'weight-product',
        quantity: 735,
        saleMode: ProductSaleMode.weight,
      ),
    ]);
    expect(sale.totalCents, 1964000);
    expect(sale.total, 19640);
    expect((await fixture.weightBalance())['quantity_on_hand'], 12265);
    expect(
        (await fixture.row('local_product_stock_balances',
            'unit-balance'))['quantity_on_hand'],
        8);
    expect(await fixture.count('sale_items'), 2);
    expect(await fixture.count('sale_payments'), 1);
    await fixture.enqueue();
    expect(await fixture.count('local_sync_mutations'), 4);
    final ids = await fixture.database
        .customSelect('select client_mutation_id from local_sync_mutations')
        .get();
    expect(ids.map((row) => row.read<String>('client_mutation_id')).toSet(),
        hasLength(4));
  });

  test('historical quote and retry survive a later price change', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final first = await fixture.sellWeight(735);
    await fixture.enqueue();
    final original = await fixture.itemPayload(first.lines.single.itemId);
    await fixture.database.customStatement(
      'update products set sale_price = 12001, sale_price_cents = 1200100 '
      'where id = ?',
      ['weight-product'],
    );
    final second = await fixture.sellWeight(3);
    await fixture.enqueue();
    expect(await fixture.itemPayload(first.lines.single.itemId), original);
    expect((await fixture.item(first.lines.single.itemId))['line_total_cents'],
        1764000);
    expect((await fixture.item(second.lines.single.itemId))['line_total_cents'],
        7201);
    expect(
        (await fixture
            .itemPayload(second.lines.single.itemId))['price_cents_snapshot'],
        1200100);
  });

  test('outbox rejects corrupted basis, total and mode without enqueue',
      () async {
    for (final corruption in <String>[
      'price_basis_quantity_snapshot = 1000',
      'line_total_cents = 1',
      'price_cents_snapshot = null',
      'quantity = 0',
      "sale_mode_snapshot = 'unit'",
    ]) {
      final fixture = await _Fixture.create();
      try {
        final sale = await fixture.sellWeight(735);
        await fixture.database.customStatement(
          'update sale_items set $corruption where id = ?',
          [sale.lines.single.itemId],
        );
        await expectLater(fixture.enqueue(), throwsStateError);
        expect(await fixture.count('local_sync_batches'), 0);
      } finally {
        await fixture.close();
      }
    }
  });

  test('concurrent sale batches use entity-scoped mutation IDs', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await Future.wait([fixture.sellWeight(735), fixture.sellWeight(735)]);
    await fixture.enqueue();
    final ids = await fixture.database
        .customSelect('select client_mutation_id from local_sync_mutations')
        .get();
    expect(ids, hasLength(6));
    expect(ids.map((row) => row.read<String>('client_mutation_id')).toSet(),
        hasLength(6));
  });

  test('W5A batch never reaches the legacy remote POS applier', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.sellWeight(735);
    await fixture.enqueue();
    final remote = _NoRemoteApply();
    final result = await PosSyncUploadService(
      outboxService:
          LocalSyncOutboxService(LocalSyncOutboxDao(fixture.database)),
      remoteDataSource: remote,
      posLocalSaleDao: PosLocalSaleDao(fixture.database),
      cashSessionLocalDao: _UnusedCashSessionDao(),
      cashSessionFailureReconciliationService: _UnusedCashFailureService(),
      inventoryFailureReconciliationService: _UnusedInventoryFailureService(),
    ).uploadPendingPosBatches(businessId: 'business', branchId: 'branch');
    expect(result.batchesFailed, 1);
    expect(remote.called, isFalse);
    expect(await fixture.count('local_sync_mutations'), 3);
  });
}

class _NoRemoteApply extends Fake implements PosSyncRemoteDataSource {
  bool called = false;

  @override
  Future<bool> allPosMutationEntitiesAlreadyExist({
    required List<Map<String, dynamic>> localMutations,
  }) async {
    called = true;
    throw StateError('W5A must not call Hosted.');
  }
}

class _UnusedCashSessionDao extends Fake implements CashSessionLocalDao {}

class _UnusedCashFailureService extends Fake
    implements PosCashSessionFailureReconciliationService {}

class _UnusedInventoryFailureService extends Fake
    implements PosInventoryFailureReconciliationService {}

class _Fixture {
  _Fixture(this.database);

  static Future<_Fixture> create({
    int quantity = 13000,
    int? costBasis = 2280000,
    int? available,
    int priceCents = 1200000,
  }) async {
    final db = AppDatabase.executor(NativeDatabase.memory());
    final fixture = _Fixture(db);
    await db.customStatement('insert into businesses (id, name) values (?, ?)',
        ['business', 'Business']);
    await db.customStatement(
        'insert into profiles (id, business_id) values (?, ?)',
        ['profile', 'business']);
    await db.customStatement(
        'insert into branches (id, business_id, name) values (?, ?, ?)',
        ['branch', 'business', 'Branch']);
    await db.customStatement(
      'insert into products (id, business_id, name, sale_mode, sale_price, '
      'sale_price_cents) values (?, ?, ?, ?, ?, ?)',
      [
        'weight-product',
        'business',
        'Carne',
        'weight',
        priceCents / 100,
        priceCents
      ],
    );
    await db.customStatement(
      'insert into products (id, business_id, name, sale_price) '
      'values (?, ?, ?, ?)',
      ['unit-product', 'business', 'UNIT', 1000],
    );
    await db.customStatement(
      'insert into local_product_stock_balances '
      '(id, business_id, branch_id, product_id, quantity_on_hand, '
      'quantity_available, cost_basis_cents) values (?, ?, ?, ?, ?, ?, ?)',
      [
        'weight-balance',
        'business',
        'branch',
        'weight-product',
        quantity,
        available ?? quantity,
        costBasis
      ],
    );
    await db.customStatement(
      'insert into local_product_stock_balances '
      '(id, business_id, branch_id, product_id, quantity_on_hand, '
      'quantity_available, average_cost) values (?, ?, ?, ?, ?, ?, ?)',
      ['unit-balance', 'business', 'branch', 'unit-product', 10, 10, 600],
    );
    return fixture;
  }

  final AppDatabase database;

  Future<PosLocalSaleResult> sellWeight(int grams, {int? basis}) => sell([
        PosLocalSaleItemInput(
          productId: 'weight-product',
          quantity: grams,
          saleMode: ProductSaleMode.weight,
          priceBasisQuantity: basis,
        ),
      ]);

  Future<PosLocalSaleResult> sell(List<PosLocalSaleItemInput> items) =>
      PosLocalSaleService(dao: PosLocalSaleDao(database)).createLocalSale(
        CreatePosLocalSaleInput(
          businessId: 'business',
          branchId: 'branch',
          profileId: 'profile',
          cashRegisterId: 'cash-register',
          cashSessionId: 'cash-session',
          deviceInstallationId: 'installation',
          items: items,
        ),
      );

  Future<PosSyncOutboxResult> enqueue() => PosSyncOutboxService(
        dao: PosLocalSaleDao(database),
        outboxService: LocalSyncOutboxService(LocalSyncOutboxDao(database)),
      ).enqueuePendingPosSales(
        businessId: 'business',
        branchId: 'branch',
        profileId: 'profile',
        deviceInstallationId: 'installation',
      );

  Future<Map<String, dynamic>> row(String table, String id) async =>
      (await database.customSelect('select * from $table where id = ?',
              variables: [Variable<String>(id)]).getSingle())
          .data;

  Future<Map<String, dynamic>> item(String id) => row('sale_items', id);
  Future<Map<String, dynamic>> weightBalance() =>
      row('local_product_stock_balances', 'weight-balance');

  Future<Map<String, dynamic>> itemPayload(String id) async {
    final row = await database.customSelect(
      "select payload_json from local_sync_mutations where entity_table = 'sale_items' and entity_id = ?",
      variables: [Variable<String>(id)],
    ).getSingle();
    return jsonDecode(row.read<String>('payload_json')) as Map<String, dynamic>;
  }

  Future<int> count(String table) async => (await database
          .customSelect('select count(*) as count from $table')
          .getSingle())
      .read<int>('count');

  Future<void> close() => database.close();
}
