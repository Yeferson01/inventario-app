import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/models/product_sale_mode.dart';
import 'package:inventario_frontend/features/cash/data/datasources/cash_session_local_dao.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_models.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_service.dart';
import 'package:inventario_frontend/features/sales/application/pos_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';
import 'package:inventario_frontend/features/sync/application/local_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sync/application/pos_cash_session_failure_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/application/pos_inventory_failure_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/application/pos_sync_upload_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/local_sync_outbox_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/pos_sync_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/models/catalog_upload_models.dart';

void main() {
  test('empty legacy WEIGHT orphan is superseded before the valid batch',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.database.customStatement('''
      insert into local_sync_batches
        (id, client_batch_id, business_id, branch_id, app_device_id,
         profile_id, domain, direction, status, mutation_count, metadata_json,
         created_at)
      values (?, ?, ?, ?, ?, ?, 'pos', 'upload', 'error', 3, ?, ?)
    ''', [
      'legacy-empty',
      'legacy-client',
      'business',
      'branch',
      'app-device',
      'profile',
      '{"sale_id":"legacy-sale","item_count":1,"payment_count":1,'
          '"monetary_contract_version":"exact_weight_sale_v1"}',
      1577836800,
    ]);
    await fixture.sellWeight(735);
    await fixture.enqueue();

    final remote = _WeightedRemote();
    final result = await fixture
        .uploader(
          remote: remote,
          refresher: ({
            required String profileId,
            required String businessId,
            required String branchId,
            required String appDeviceId,
          }) async =>
              true,
        )
        .uploadPendingPosBatches(businessId: 'business', branchId: 'branch');

    expect(result.batchesChecked, 2);
    expect(result.batchesUploaded, 1);
    expect(result.batchesCompleted, 1);
    expect(result.batchesFailed, 0);
    expect(remote.uploadCalls, 1);
    final orphan = await fixture.database.customSelect('''
      select status, last_error from local_sync_batches where id = ?
    ''', variables: [const Variable<String>('legacy-empty')]).getSingle();
    expect(orphan.read<String>('status'), 'superseded');
    expect(orphan.read<String>('last_error'), 'legacy_empty_pos_batch_orphan');
    expect(await fixture.count('local_sync_mutations'), 3);
  });

  test('partial malformed WEIGHT batch remains rejected without auto-repair',
      () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.close);
    await fixture.sellWeight(735);
    await fixture.enqueue();
    await fixture.database.customStatement('''
      delete from local_sync_mutations where entity_table <> 'sales'
    ''');
    final remote = _WeightedRemote();
    final result = await fixture
        .uploader(
          remote: remote,
          refresher: ({
            required String profileId,
            required String businessId,
            required String branchId,
            required String appDeviceId,
          }) async =>
              true,
        )
        .uploadPendingPosBatches(businessId: 'business', branchId: 'branch');
    expect(result.batchesFailed, 1);
    expect(remote.uploadCalls, 0);
    expect(await fixture.count('local_sync_mutations'), 1);
    final batch = await fixture.database.customSelect('''
      select status, last_error from local_sync_batches where domain = 'pos'
    ''').getSingle();
    expect(batch.read<String>('status'), 'error');
    expect(batch.read<String>('last_error'),
        contains('weighted_sale_payload_invalid'));
  });

  test(
    'weighted batch is completed only after successful local convergence',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);

      await fixture.sellWeight(735);
      await fixture.enqueue();

      final remote = _WeightedRemote();
      var refreshCalls = 0;

      final result = await fixture
          .uploader(
            remote: remote,
            refresher: ({
              required String profileId,
              required String businessId,
              required String branchId,
              required String appDeviceId,
            }) async {
              refreshCalls++;
              return true;
            },
          )
          .uploadPendingPosBatches(
            businessId: 'business',
            branchId: 'branch',
          );

      expect(remote.capabilityChecks, 1);
      expect(remote.uploadCalls, 1);
      expect(refreshCalls, 1);

      expect(result.batchesChecked, 1);
      expect(result.batchesUploaded, 1);
      expect(result.batchesCompleted, 1);
      expect(result.batchesPartial, 0);
      expect(result.batchesFailed, 0);
      expect(result.mutationsUploaded, 3);
    },
  );

  test(
    'failed weighted convergence does not count completed and can retry',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);

      final sale = await fixture.sellWeight(735);
      await fixture.enqueue();

      final remote = _WeightedRemote();
      var refreshCalls = 0;

      final uploader = fixture.uploader(
        remote: remote,
        refresher: ({
          required String profileId,
          required String businessId,
          required String branchId,
          required String appDeviceId,
        }) async {
          refreshCalls++;
          return refreshCalls > 1;
        },
      );

      final first = await uploader.uploadPendingPosBatches(
        businessId: 'business',
        branchId: 'branch',
      );

      expect(first.batchesChecked, 1);
      expect(first.batchesUploaded, 1);
      expect(first.batchesCompleted, 0);
      expect(first.batchesPartial, 0);
      expect(first.batchesFailed, 1);

      final retryPreparation = await fixture.enqueue();
      expect(retryPreparation.batchesCreated, 0);
      expect(retryPreparation.mutationsEnqueued, 0);
      final retryBatch = await fixture.database.customSelect('''
        select b.id, b.client_batch_id, count(m.id) as mutation_count
        from local_sync_batches b
        join local_sync_mutations m on m.local_sync_batch_id = b.id
        where b.domain = 'pos'
        group by b.id, b.client_batch_id
      ''').getSingle();
      expect(retryBatch.read<int>('mutation_count'), 3);

      // Remote succeeded before local convergence failed. The authoritative
      // ACK was already projected, but it must not make this run "completed".
      final itemAfterFailure = await fixture.item(sale.lines.single.itemId);
      expect(itemAfterFailure['cogs_cents'], 128908);

      final second = await uploader.uploadPendingPosBatches(
        businessId: 'business',
        branchId: 'branch',
      );

      expect(second.batchesChecked, 1);
      expect(second.batchesUploaded, 1);
      expect(second.batchesCompleted, 1);
      expect(second.batchesPartial, 0);
      expect(second.batchesFailed, 0);

      expect(remote.uploadCalls, 2);
      expect(refreshCalls, 2);
      final finalBatch = await fixture.database.customSelect('''
        select id, client_batch_id from local_sync_batches where domain = 'pos'
      ''').getSingle();
      expect(finalBatch.read<String>('id'), retryBatch.read<String>('id'));
      expect(finalBatch.read<String>('client_batch_id'),
          retryBatch.read<String>('client_batch_id'));

      // Reapplying the identical ACK must not create another local movement.
      expect(await fixture.count('local_inventory_movements'), 1);

      final itemAfterRetry = await fixture.item(sale.lines.single.itemId);
      expect(itemAfterRetry['cogs_cents'], 128908);
    },
  );

  test(
    'weighted batch stays local when remote capability is unavailable',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.close);

      await fixture.sellWeight(735);
      await fixture.enqueue();

      final remote = _WeightedRemote(supportsWeighted: false);
      var refreshCalls = 0;

      final result = await fixture
          .uploader(
            remote: remote,
            refresher: ({
              required String profileId,
              required String businessId,
              required String branchId,
              required String appDeviceId,
            }) async {
              refreshCalls++;
              return true;
            },
          )
          .uploadPendingPosBatches(
            businessId: 'business',
            branchId: 'branch',
          );

      expect(remote.capabilityChecks, 1);
      expect(remote.uploadCalls, 0);
      expect(refreshCalls, 0);

      expect(result.batchesChecked, 1);
      expect(result.batchesUploaded, 0);
      expect(result.batchesCompleted, 0);
      expect(result.batchesPartial, 0);
      expect(result.batchesFailed, 1);

      // Nothing was removed from the outbox.
      expect(await fixture.count('local_sync_mutations'), 3);
    },
  );
}

class _WeightedRemote extends Fake implements PosSyncRemoteDataSource {
  _WeightedRemote({
    this.supportsWeighted = true,
  });

  final bool supportsWeighted;

  int capabilityChecks = 0;
  int uploadCalls = 0;

  @override
  Future<bool> supportsWeightedSaleSync() async {
    capabilityChecks++;
    return supportsWeighted;
  }

  @override
  Future<CatalogUploadBatchResult> uploadAndProcessPosBatch({
    required Map<String, dynamic> localBatch,
    required List<Map<String, dynamic>> localMutations,
  }) async {
    uploadCalls++;

    final sale = localMutations.singleWhere(
      (mutation) => mutation['entity_table'] == 'sales',
    );
    final item = localMutations.singleWhere(
      (mutation) => mutation['entity_table'] == 'sale_items',
    );

    final saleId = sale['entity_id'].toString();
    final itemId = item['entity_id'].toString();

    return CatalogUploadBatchResult(
      localBatchId: localBatch['id'].toString(),
      serverBatchId: 'server-batch',
      status: 'completed',
      mutationCount: localMutations.length,
      appliedCount: localMutations.length,
      skippedCount: 0,
      conflictCount: 0,
      errorCount: 0,
      raw: {
        'weighted_sale_ack': [
          {
            'sale_id': saleId,
            'sale_item_id': itemId,
            'inventory_movement_id': 'remote-movement-$itemId',
            'mutation_status': 'applied',
            'stock_quantity_grams': 12265,
            'cost_basis_cents': 2151092,
            'cogs_cents': 128908,
            'cost_effect_cents': -128908,
          },
        ],
      },
    );
  }

  @override
  Future<List<Never>> getCashSessionApplyFailures({
    required String serverBatchId,
  }) async {
    return const [];
  }

  @override
  Future<List<Never>> getInventoryApplyFailures({
    required String serverBatchId,
  }) async {
    return const [];
  }
}

class _CleanCashSessionDao extends Fake implements CashSessionLocalDao {
  @override
  Future<List<Map<String, dynamic>>> getPendingDirtyCashRegisters({
    required String businessId,
    required String branchId,
    int limit = 10,
  }) async {
    return const [];
  }

  @override
  Future<List<Map<String, dynamic>>> getPendingDirtyCashSessions({
    required String businessId,
    required String branchId,
    int limit = 10,
  }) async {
    return const [];
  }
}

class _UnusedCashFailureService extends Fake
    implements PosCashSessionFailureReconciliationService {}

class _UnusedInventoryFailureService extends Fake
    implements PosInventoryFailureReconciliationService {}

class _Fixture {
  _Fixture(this.database);

  final AppDatabase database;

  static Future<_Fixture> create() async {
    final db = AppDatabase.executor(NativeDatabase.memory());
    final fixture = _Fixture(db);

    await db.customStatement(
      'insert into businesses (id, name) values (?, ?)',
      ['business', 'Business'],
    );

    await db.customStatement(
      'insert into profiles (id, business_id) values (?, ?)',
      ['profile', 'business'],
    );

    await db.customStatement(
      'insert into branches (id, business_id, name) values (?, ?, ?)',
      ['branch', 'business', 'Branch'],
    );

    await db.customStatement(
      'insert into products '
      '(id, business_id, name, sale_mode, sale_price, sale_price_cents) '
      'values (?, ?, ?, ?, ?, ?)',
      [
        'weight-product',
        'business',
        'Carne',
        'weight',
        12000,
        1200000,
      ],
    );

    await db.customStatement(
      'insert into local_product_stock_balances '
      '(id, business_id, branch_id, product_id, quantity_on_hand, '
      'quantity_available, cost_basis_cents) '
      'values (?, ?, ?, ?, ?, ?, ?)',
      [
        'weight-balance',
        'business',
        'branch',
        'weight-product',
        13000,
        13000,
        2280000,
      ],
    );

    return fixture;
  }

  Future<PosLocalSaleResult> sellWeight(int grams) {
    return PosLocalSaleService(
      dao: PosLocalSaleDao(database),
    ).createLocalSale(
      CreatePosLocalSaleInput(
        businessId: 'business',
        branchId: 'branch',
        profileId: 'profile',
        cashRegisterId: 'cash-register',
        cashSessionId: 'cash-session',
        deviceInstallationId: 'installation',
        items: [
          PosLocalSaleItemInput(
            productId: 'weight-product',
            quantity: grams,
            saleMode: ProductSaleMode.weight,
          ),
        ],
      ),
    );
  }

  Future<PosSyncOutboxResult> enqueue() {
    return PosSyncOutboxService(
      dao: PosLocalSaleDao(database),
      outboxService: LocalSyncOutboxService(
        LocalSyncOutboxDao(database),
      ),
    ).enqueuePendingPosSales(
      businessId: 'business',
      branchId: 'branch',
      profileId: 'profile',
      appDeviceId: 'app-device',
      deviceInstallationId: 'installation',
    );
  }

  PosSyncUploadService uploader({
    required PosSyncRemoteDataSource remote,
    required WeightedSaleInventoryRefresher refresher,
  }) {
    return PosSyncUploadService(
      outboxService: LocalSyncOutboxService(
        LocalSyncOutboxDao(database),
      ),
      remoteDataSource: remote,
      posLocalSaleDao: PosLocalSaleDao(database),
      cashSessionLocalDao: _CleanCashSessionDao(),
      cashSessionFailureReconciliationService: _UnusedCashFailureService(),
      inventoryFailureReconciliationService: _UnusedInventoryFailureService(),
      weightedSaleInventoryRefresher: refresher,
    );
  }

  Future<Map<String, dynamic>> item(String id) async {
    return (await database.customSelect(
      'select * from sale_items where id = ?',
      variables: [Variable<String>(id)],
    ).getSingle())
        .data;
  }

  Future<int> count(String table) async {
    return (await database
            .customSelect('select count(*) as count from $table')
            .getSingle())
        .read<int>('count');
  }

  Future<void> close() => database.close();
}
