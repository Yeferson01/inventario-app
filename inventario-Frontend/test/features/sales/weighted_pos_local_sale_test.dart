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

  test('repeated WEIGHT enqueue keeps one complete POS batch and its IDs',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.sellWeight(735);
    final first = await fixture.enqueue();
    expect(first.batchesCreated, 1);

    Future<List<Map<String, dynamic>>> mutations() async =>
        (await fixture.database.customSelect('''
          select m.entity_table, m.local_sync_batch_id, m.client_batch_id,
                 m.idempotency_key, b.metadata_json
          from local_sync_mutations m
          join local_sync_batches b on b.id = m.local_sync_batch_id
          where b.domain = 'pos' order by m.entity_table
        ''').get()).map((row) => row.data).toList();

    final before = await mutations();
    expect(before, hasLength(3));
    final batchId = before.first['local_sync_batch_id'];
    expect(
        before.every((row) => row['local_sync_batch_id'] == batchId), isTrue);
    final metadata = jsonDecode(before.first['metadata_json'] as String);
    expect(metadata['item_count'], 1);
    expect(metadata['payment_count'], 1);

    final second = await fixture.enqueue();
    expect(second.batchesCreated, 0);
    expect(second.mutationsEnqueued, 0);
    expect(second.results.single['status'], 'reused');
    expect(await mutations(), before);
    expect(await fixture.count('local_sync_batches'), 1);
    expect(await fixture.count('local_sync_mutations'), 3);
  });

  test('corrupt existing POS batch is not silently rebuilt', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.sellWeight(735);
    await fixture.enqueue();
    await fixture.database.customStatement('''
      update local_sync_batches
      set metadata_json = json_set(metadata_json, '\$.item_count', 2)
      where domain = 'pos'
    ''');

    await expectLater(
      fixture.enqueue(),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        'pos_batch_structure_conflict',
      )),
    );
    expect(await fixture.count('local_sync_batches'), 1);
    expect(await fixture.count('local_sync_mutations'), 3);
  });

  test(
      'WEIGHT payment persists supplied exact cents, not a double-derived source',
      () async {
    final fixture = await _Fixture.create(priceCents: 1200100);
    addTearDown(fixture.close);
    final sale = await fixture.sell(
      const [
        PosLocalSaleItemInput(
          productId: 'weight-product',
          quantity: 3,
          saleMode: ProductSaleMode.weight,
        ),
      ],
      payments: const [
        PosLocalPaymentInput(method: 'cash', amount: 72.01, amountCents: 7201),
      ],
    );
    final payment = await fixture.database.customSelect(
      'select metadata_json from sale_payments where sale_id = ?',
      variables: [Variable<String>(sale.saleId)],
    ).getSingle();
    expect(jsonDecode(payment.read<String>('metadata_json'))['amount_cents'],
        7201);
  });

  test('inconsistent exact payment shadow aborts without a sale', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await expectLater(
      fixture.sell(
        const [
          PosLocalSaleItemInput(
            productId: 'weight-product',
            quantity: 500,
            saleMode: ProductSaleMode.weight,
          ),
        ],
        payments: const [
          PosLocalPaymentInput(
              method: 'cash', amount: 12000, amountCents: 1199900),
        ],
      ),
      throwsArgumentError,
    );
    expect(await fixture.count('sales'), 0);
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

  test(
      'W5B identical authoritative ACK is idempotent and does not reapply stock',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);

    final sale = await fixture.sellWeight(735);
    final dao = PosLocalSaleDao(fixture.database);

    final stockBefore = await fixture.weightBalance();
    expect(stockBefore['quantity_on_hand'], 12265);
    expect(stockBefore['cost_basis_cents'], 2151092);

    final ack = <String, dynamic>{
      'sale_id': sale.saleId,
      'sale_item_id': sale.lines.single.itemId,
      'inventory_movement_id': 'remote-movement-1',
      'mutation_status': 'applied',
      'stock_quantity_grams': 12265,
      'cost_basis_cents': 2151092,
      'cogs_cents': 128908,
      'cost_effect_cents': -128908,
    };

    await dao.applyWeightedSaleAck(
      businessId: 'business',
      branchId: 'branch',
      saleId: sale.saleId,
      entries: [ack],
    );

    await dao.applyWeightedSaleAck(
      businessId: 'business',
      branchId: 'branch',
      saleId: sale.saleId,
      entries: [ack],
    );

    final item = await fixture.item(sale.lines.single.itemId);
    expect(item['cogs_cents'], 128908);

    final movement = await fixture.row(
      'local_inventory_movements',
      sale.lines.single.inventoryMovementId,
    );
    expect(movement['cost_effect_cents'], -128908);

    final stockAfter = await fixture.weightBalance();
    expect(stockAfter['quantity_on_hand'], 12265);
    expect(stockAfter['quantity_available'], 12265);
    expect(stockAfter['cost_basis_cents'], 2151092);

    expect(await fixture.count('local_inventory_movements'), 1);
  });

  test(
      'W5B conflicting authoritative ACK is rejected without changing projection',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);

    final sale = await fixture.sellWeight(735);
    final dao = PosLocalSaleDao(fixture.database);

    final ack = <String, dynamic>{
      'sale_id': sale.saleId,
      'sale_item_id': sale.lines.single.itemId,
      'inventory_movement_id': 'remote-movement-1',
      'mutation_status': 'applied',
      'stock_quantity_grams': 12265,
      'cost_basis_cents': 2151092,
      'cogs_cents': 128908,
      'cost_effect_cents': -128908,
    };

    await dao.applyWeightedSaleAck(
      businessId: 'business',
      branchId: 'branch',
      saleId: sale.saleId,
      entries: [ack],
    );

    final conflictingAck = <String, dynamic>{
      ...ack,
      'inventory_movement_id': 'remote-movement-conflict',
    };

    await expectLater(
      dao.applyWeightedSaleAck(
        businessId: 'business',
        branchId: 'branch',
        saleId: sale.saleId,
        entries: [conflictingAck],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'weighted_sale_ack_conflict',
        ),
      ),
    );

    final item = await fixture.item(sale.lines.single.itemId);
    expect(item['cogs_cents'], 128908);

    final movement = await fixture.row(
      'local_inventory_movements',
      sale.lines.single.inventoryMovementId,
    );
    expect(movement['cost_effect_cents'], -128908);

    final stock = await fixture.weightBalance();
    expect(stock['quantity_on_hand'], 12265);
    expect(stock['cost_basis_cents'], 2151092);

    expect(await fixture.count('local_inventory_movements'), 1);
  });

  test('W5B identical ACK rejects divergent local cost projection', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final sale = await fixture.sellWeight(735);
    final dao = PosLocalSaleDao(fixture.database);
    final ack = <String, dynamic>{
      'sale_id': sale.saleId,
      'sale_item_id': sale.lines.single.itemId,
      'inventory_movement_id': 'remote-movement-1',
      'mutation_status': 'applied',
      'stock_quantity_grams': 12265,
      'cost_basis_cents': 2151092,
      'cogs_cents': 128908,
      'cost_effect_cents': -128908,
    };

    await dao.applyWeightedSaleAck(
      businessId: 'business',
      branchId: 'branch',
      saleId: sale.saleId,
      entries: [ack],
    );
    await fixture.database.customStatement(
      'update sale_items set cogs_cents = ? where id = ?',
      [128907, sale.lines.single.itemId],
    );

    await expectLater(
      dao.applyWeightedSaleAck(
        businessId: 'business',
        branchId: 'branch',
        saleId: sale.saleId,
        entries: [ack],
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'weighted_sale_ack_conflict',
        ),
      ),
    );
    expect(
        (await fixture.item(sale.lines.single.itemId))['cogs_cents'], 128907);
    expect(
      (await fixture.row(
        'local_inventory_movements',
        sale.lines.single.inventoryMovementId,
      ))['cost_effect_cents'],
      -128908,
    );
  });

  test('stale WEIGHT projects authoritative cost once without changing stock',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final sale = await fixture.sellWeight(735);
    await fixture.enqueue();
    final result = await fixture.staleWeightResult(sale, cogsCents: 120000);
    final before = await fixture.weightBalance();

    final first = await fixture.projectStale(sale.saleId, [result]);
    final second = await fixture.projectStale(sale.saleId, [result]);

    expect(first.alreadyProjected, isFalse);
    expect(second.alreadyProjected, isTrue);
    final item = await fixture.item(sale.lines.single.itemId);
    expect(item['cogs_cents'], 120000);
    expect(
        jsonDecode(item['metadata_json'] as String)['w5b_stale_remote_result']
            ['inventory_movement_id'],
        'remote-stale-movement');
    final movement = await fixture.row(
      'local_inventory_movements',
      sale.lines.single.inventoryMovementId,
    );
    expect(movement['cost_effect_cents'], -120000);
    expect(
        jsonDecode(movement['metadata_json'] as String)[
            'w5b_stale_remote_inventory_movement_id'],
        'remote-stale-movement');
    expect((await fixture.weightBalance())['quantity_on_hand'],
        before['quantity_on_hand']);
    final mutations = await fixture.database
        .customSelect(
          'select status, error_code from local_sync_mutations',
        )
        .get();
    expect(mutations, hasLength(3));
    expect(mutations.every((row) => row.read<String>('status') == 'skipped'),
        isTrue);
    expect(
      mutations.every((row) =>
          row.read<String>('error_code') ==
          'superseded_by_sale_reconciliation'),
      isTrue,
    );
    expect(await fixture.count('local_inventory_movements'), 1);
  });

  test('stale WEIGHT contradictory retry fails without changing projection',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final sale = await fixture.sellWeight(735);
    await fixture.enqueue();
    final result = await fixture.staleWeightResult(sale, cogsCents: 120000);
    await fixture.projectStale(sale.saleId, [result]);

    await expectLater(
      fixture.projectStale(sale.saleId, [
        IntentionalStaleWeightedSaleProjection(
          saleId: result.saleId,
          saleItemId: result.saleItemId,
          productId: result.productId,
          quantityGrams: result.quantityGrams,
          inventoryMovementId: 'different-remote-movement',
          stockQuantityGrams: result.stockQuantityGrams,
          costBasisCents: result.costBasisCents,
          cogsCents: result.cogsCents,
          costEffectCents: result.costEffectCents,
          originalSyncMutationId: result.originalSyncMutationId,
          originalMutationStatus: result.originalMutationStatus,
          originalMutationErrorCode: result.originalMutationErrorCode,
        ),
      ]),
      throwsA(isA<StateError>().having(
        (error) => error.message,
        'message',
        'weighted_stale_sale_ack_conflict',
      )),
    );
    expect((await fixture.item(result.saleItemId))['cogs_cents'], 120000);
    expect((await fixture.weightBalance())['quantity_on_hand'], 12265);
  });

  test('stale WEIGHT rejects wrong original mutation and rolls back locally',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final sale = await fixture.sellWeight(735);
    await fixture.enqueue();
    final result = await fixture.staleWeightResult(sale, cogsCents: 120000);

    await expectLater(
      fixture.projectStale(sale.saleId, [
        IntentionalStaleWeightedSaleProjection(
          saleId: result.saleId,
          saleItemId: result.saleItemId,
          productId: result.productId,
          quantityGrams: result.quantityGrams,
          inventoryMovementId: result.inventoryMovementId,
          stockQuantityGrams: result.stockQuantityGrams,
          costBasisCents: result.costBasisCents,
          cogsCents: result.cogsCents,
          costEffectCents: result.costEffectCents,
          originalSyncMutationId: 'wrong-mutation',
          originalMutationStatus: result.originalMutationStatus,
          originalMutationErrorCode: result.originalMutationErrorCode,
        ),
      ]),
      throwsStateError,
    );
    expect((await fixture.row('sales', sale.saleId))['local_status'], 'dirty');
    expect((await fixture.item(result.saleItemId))['cogs_cents'], 128908);
    expect((await fixture.weightBalance())['quantity_on_hand'], 12265);
  });

  test('stale WEIGHT requires one authoritative result per WEIGHT item',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final sale = await fixture.sellWeight(735);
    await fixture.enqueue();
    await expectLater(
        fixture.projectStale(sale.saleId, const []), throwsStateError);
    expect((await fixture.row('sales', sale.saleId))['local_status'], 'dirty');
  });

  for (final cost in <int?>[null, 0]) {
    test('stale WEIGHT preserves authoritative ${cost ?? 'unknown'} cost',
        () async {
      final fixture = await _Fixture.create(costBasis: cost);
      addTearDown(fixture.close);
      final sale = await fixture.sellWeight(735);
      await fixture.enqueue();
      final result = await fixture.staleWeightResult(sale, cogsCents: cost);
      await fixture.projectStale(sale.saleId, [result]);
      expect((await fixture.item(result.saleItemId))['cogs_cents'], cost);
      expect(
          (await fixture.row('local_inventory_movements',
              sale.lines.single.inventoryMovementId))['cost_effect_cents'],
          cost == null ? null : -cost);
      expect((await fixture.weightBalance())['cost_basis_cents'], cost);
    });
  }

  test('stale mixed sale leaves UNIT cost and movement unchanged', () async {
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
    await fixture.enqueue();
    final weightResult =
        await fixture.staleWeightResult(sale, cogsCents: 120000);
    final unitLine = sale.lines
        .singleWhere((line) => line.itemId != weightResult.saleItemId);
    final unitItemBefore = await fixture.item(unitLine.itemId);
    final unitMovementBefore = await fixture.row(
        'local_inventory_movements', unitLine.inventoryMovementId);

    await fixture.projectStale(sale.saleId, [weightResult]);

    expect((await fixture.item(unitLine.itemId))['cogs_cents'],
        unitItemBefore['cogs_cents']);
    expect(
        (await fixture.row('local_inventory_movements',
            unitLine.inventoryMovementId))['cost_effect_cents'],
        unitMovementBefore['cost_effect_cents']);
    expect((await fixture.weightBalance())['quantity_on_hand'], 12265);
    expect(
        (await fixture.row('local_product_stock_balances',
            'unit-balance'))['quantity_on_hand'],
        8);
  });

  test('stale UNIT-only remains compatible with empty WEIGHT results',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    final sale = await fixture.sell([
      const PosLocalSaleItemInput(productId: 'unit-product', quantity: 1),
    ]);
    await fixture.enqueue();
    await fixture.projectStale(sale.saleId, const []);
    expect((await fixture.row('sales', sale.saleId))['local_status'], 'synced');
    expect(
        (await fixture.row('local_product_stock_balances',
            'unit-balance'))['quantity_on_hand'],
        9);
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

  Future<PosLocalSaleResult> sell(List<PosLocalSaleItemInput> items,
          {List<PosLocalPaymentInput> payments = const []}) =>
      PosLocalSaleService(dao: PosLocalSaleDao(database)).createLocalSale(
        CreatePosLocalSaleInput(
          businessId: 'business',
          branchId: 'branch',
          profileId: 'profile',
          cashRegisterId: 'cash-register',
          cashSessionId: 'cash-session',
          deviceInstallationId: 'installation',
          items: items,
          payments: payments,
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

  Future<IntentionalStaleWeightedSaleProjection> staleWeightResult(
    PosLocalSaleResult sale, {
    required int? cogsCents,
  }) async {
    final line = sale.lines
        .singleWhere((line) => line.itemId != '' && line.quantity == 735);
    final mutation = await database.customSelect(
      "select id from local_sync_mutations where entity_table = 'sale_items' "
      'and entity_id = ?',
      variables: [Variable<String>(line.itemId)],
    ).getSingle();
    return IntentionalStaleWeightedSaleProjection(
      saleId: sale.saleId,
      saleItemId: line.itemId,
      productId: 'weight-product',
      quantityGrams: 735,
      inventoryMovementId: 'remote-stale-movement',
      stockQuantityGrams: 12265,
      costBasisCents: cogsCents == null ? null : 2000000,
      cogsCents: cogsCents,
      costEffectCents: cogsCents == null ? null : -cogsCents,
      originalSyncMutationId: mutation.read<String>('id'),
      originalMutationStatus: 'skipped',
      originalMutationErrorCode: 'superseded_by_sale_reconciliation',
    );
  }

  Future<IntentionalStaleSaleLocalProjectionResult> projectStale(
    String saleId,
    List<IntentionalStaleWeightedSaleProjection> results,
  ) =>
      PosLocalSaleDao(database).projectIntentionalStaleSaleReconciliation(
        profileId: 'profile',
        businessId: 'business',
        branchId: 'branch',
        saleId: saleId,
        destinationCashSessionId: 'destination-session',
        reconciliationId: 'reconciliation-id',
        cashTreatment: 'not_included_in_destination_opening',
        reason: 'Sale occurred',
        weightedSaleResults: results,
      );

  Future<int> count(String table) async => (await database
          .customSelect('select count(*) as count from $table')
          .getSingle())
      .read<int>('count');

  Future<void> close() => database.close();
}
