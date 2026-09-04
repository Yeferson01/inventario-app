import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/sync/application/category_snapshot_applier.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_download_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_download_service.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_page_applier.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_page_applier_router.dart';
import 'package:inventario_frontend/features/sync/application/product_barcode_snapshot_applier.dart';
import 'package:inventario_frontend/features/sync/application/product_operational_reconciliation_support.dart';
import 'package:inventario_frontend/features/sync/application/product_snapshot_applier.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/catalog_entity_sync_state_resolver.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/product_operational_reconciliation_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/reconciliation_issue_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';
import 'package:inventario_frontend/features/sync/data/models/operational_bootstrap_models.dart';

import 'support/operational_bootstrap_test_data.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.executor(NativeDatabase.memory());
    await _insertBusiness(database, 'business-a');
    await _insertBusiness(database, 'business-b');
  });

  tearDown(() => database.close());

  test('clean product accepts remote update and creates no outbox', () async {
    await _insertProduct(database, id: 'product-1', name: 'Viejo');
    final harness = _Harness(database, [
      _productResponse([
        productOperationalProductRow(
          id: 'product-1',
          name: 'Nuevo',
          masterProductId: 'master-1',
          minimumStock: 7,
        ),
      ]),
    ]);

    final result = await harness.service.download(_productsRequest);
    final product = await _product(database, 'product-1');

    expect(result.completed, isTrue);
    expect(product.name, 'Nuevo');
    expect(product.masterProductId, 'master-1');
    expect(product.minimumStock, 7);
    expect(product.syncStatus, SyncStatus.synced);
    expect(await database.select(database.localSyncBatches).get(), isEmpty);
    expect(await database.select(database.localSyncMutations).get(), isEmpty);
    expect(await _issues(database), isEmpty);
  });

  test('remote null and zero minimum stock normalize to local zero', () async {
    await _insertProduct(
      database,
      id: 'product-null',
      name: 'Local null',
      minimumStock: 9,
    );
    await _insertProduct(
      database,
      id: 'product-zero',
      name: 'Local zero',
      minimumStock: 9,
    );
    final nullMinimumStock = productOperationalProductRow(
      id: 'product-null',
      name: 'Remote null',
    )..['minimum_stock'] = null;
    final harness = _Harness(database, [
      _productResponse([
        nullMinimumStock,
        productOperationalProductRow(
          id: 'product-zero',
          name: 'Remote zero',
          minimumStock: 0,
        ),
      ]),
    ]);

    await harness.service.download(_productsRequest);

    expect((await _product(database, 'product-null')).minimumStock, 0);
    expect((await _product(database, 'product-zero')).minimumStock, 0);
  });

  test('pending product preserves local payload, outbox and dedupes issue',
      () async {
    await _insertProduct(
      database,
      id: 'product-1',
      name: 'Local',
      syncStatus: SyncStatus.pendingInsert,
    );
    await _insertOutbox(
      database,
      entityTable: 'products',
      entityId: 'product-1',
      batchStatus: 'pending',
      mutationStatus: 'pending',
    );
    final response = _productResponse([
      productOperationalProductRow(id: 'product-1', name: 'Remoto'),
    ]);
    final harness = _Harness(database, [response, response]);

    await harness.service.download(_productsRequest);
    await harness.service.download(_productsRequest);

    expect((await _product(database, 'product-1')).name, 'Local');
    expect(
        await database.select(database.localSyncBatches).get(), hasLength(1));
    expect(
      await database.select(database.localSyncMutations).get(),
      hasLength(1),
    );
    final issues = await _issues(database);
    expect(issues, hasLength(1));
    expect(issues.single['issue_type'], 'dirty_vs_remote');
    expect(issues.single['severity'], 'warning');
  });

  test('applied/completed outbox overrides legacy dirty flag', () async {
    await _insertProduct(
      database,
      id: 'product-1',
      name: 'Legacy dirty',
      syncStatus: SyncStatus.pendingInsert,
    );
    await _insertOutbox(
      database,
      entityTable: 'products',
      entityId: 'product-1',
      batchStatus: 'completed',
      mutationStatus: 'applied',
      uploadedAt: DateTime.utc(2026, 8, 14),
    );
    final harness = _Harness(database, [
      _productResponse([
        productOperationalProductRow(id: 'product-1', name: 'Remoto'),
      ]),
    ]);

    await harness.service.download(_productsRequest);

    final product = await _product(database, 'product-1');
    expect(product.name, 'Remoto');
    expect(product.syncStatus, SyncStatus.synced);
    expect(await _issues(database), isEmpty);
  });

  test('terminal historical evidence does not overwrite a later dirty edit',
      () async {
    await _insertProduct(
      database,
      id: 'product-1',
      name: 'Edited after upload',
      syncStatus: SyncStatus.pendingUpdate,
      updatedAt: DateTime.utc(2026, 8, 14, 11),
    );
    await _insertOutbox(
      database,
      entityTable: 'products',
      entityId: 'product-1',
      batchStatus: 'completed',
      mutationStatus: 'applied',
      uploadedAt: DateTime.utc(2026, 8, 14, 10),
    );
    final harness = _Harness(database, [
      _productResponse([
        productOperationalProductRow(id: 'product-1', name: 'Remote old'),
      ]),
    ]);

    await harness.service.download(_productsRequest);

    expect((await _product(database, 'product-1')).name, 'Edited after upload');
    final issue = (await _issues(database)).single;
    expect(issue['issue_type'], 'dirty_without_outbox');
    expect(issue['severity'], 'blocking');
  });

  test('ambiguous transport and dirty without outbox are preserved', () async {
    await _insertProduct(
      database,
      id: 'ambiguous',
      name: 'Ambiguous local',
      syncStatus: SyncStatus.pendingUpdate,
    );
    await _insertOutbox(
      database,
      entityTable: 'products',
      entityId: 'ambiguous',
      batchStatus: 'partial',
      mutationStatus: 'error',
    );
    await _insertProduct(
      database,
      id: 'orphan-dirty',
      name: 'Orphan local',
      syncStatus: SyncStatus.pendingUpdate,
    );
    final harness = _Harness(database, [
      _productResponse([
        productOperationalProductRow(id: 'ambiguous', name: 'Remote A'),
        productOperationalProductRow(id: 'orphan-dirty', name: 'Remote B'),
      ]),
    ]);

    await harness.service.download(_productsRequest);

    expect((await _product(database, 'ambiguous')).name, 'Ambiguous local');
    expect((await _product(database, 'orphan-dirty')).name, 'Orphan local');
    final issues = await _issues(database);
    expect(issues.map((row) => row['issue_type']),
        containsAll(['dirty_vs_remote', 'dirty_without_outbox']));
    expect(
      issues
          .singleWhere((row) => row['entity_id'] == 'orphan-dirty')['severity'],
      'blocking',
    );
  });

  test('clean tombstone applies while dirty tombstone blocks', () async {
    await _insertProduct(database, id: 'clean', name: 'Clean');
    await _insertProduct(
      database,
      id: 'dirty',
      name: 'Dirty',
      syncStatus: SyncStatus.pendingDelete,
    );
    await _insertOutbox(
      database,
      entityTable: 'products',
      entityId: 'dirty',
      batchStatus: 'pending',
      mutationStatus: 'pending',
    );
    final harness = _Harness(database, [
      _productResponse([
        productOperationalProductRow(
          id: 'clean',
          name: 'Clean',
          state: 'tombstone',
          status: 'inactive',
          deletedAt: '2026-08-14T08:00:00Z',
        ),
        productOperationalProductRow(
          id: 'dirty',
          name: 'Dirty',
          state: 'tombstone',
          status: 'inactive',
          deletedAt: '2026-08-14T08:00:00Z',
        ),
      ]),
    ]);

    await harness.service.download(_productsRequest);

    expect((await _product(database, 'clean')).deletedAt, isNotNull);
    expect((await _product(database, 'dirty')).deletedAt, isNull);
    final dirtyIssue = (await _issues(database)).single;
    expect(dirtyIssue['issue_type'], 'dirty_vs_tombstone');
    expect(dirtyIssue['severity'], 'blocking');
  });

  test('sweep runs only after final page and preserves dirty absent rows',
      () async {
    await _insertProduct(database, id: 'seen', name: 'Seen');
    await _insertProduct(database, id: 'clean-absent', name: 'Clean absent');
    await _insertProduct(
      database,
      id: 'dirty-absent',
      name: 'Dirty absent',
      syncStatus: SyncStatus.pendingInsert,
    );
    await _insertOutbox(
      database,
      entityTable: 'products',
      entityId: 'dirty-absent',
      batchStatus: 'pending',
      mutationStatus: 'pending',
    );
    var secondPageObserved = false;
    final harness = _Harness.withInvoker(database, (parameters, call) async {
      if (call == 0) {
        return _productResponse(
          [productOperationalProductRow(id: 'seen', name: 'Seen')],
          hasMore: true,
          nextToken: 'page-2',
        );
      }
      expect((await _product(database, 'clean-absent')).deletedAt, isNull);
      secondPageObserved = true;
      return _productResponse(const []);
    });

    await harness.service.download(_productsRequest);

    expect(secondPageObserved, isTrue);
    final cleanAbsent = await _product(database, 'clean-absent');
    expect(cleanAbsent.deletedAt?.toUtc(), DateTime.utc(2026, 8, 15, 9));
    expect(cleanAbsent.status, 'inactive');
    expect((await _product(database, 'dirty-absent')).deletedAt, isNull);
    expect(
      (await _issues(database)).single['issue_type'],
      'dirty_absent_from_remote',
    );
  });

  test('1000 + 5 products apply once and sweep waits for page two', () async {
    await _insertProduct(database, id: 'stale', name: 'Stale');
    final firstRows = List.generate(
      1000,
      (index) => productOperationalProductRow(
        id: 'product-$index',
        name: 'Product $index',
      ),
    );
    final tailRows = List.generate(
      5,
      (index) => productOperationalProductRow(
        id: 'product-${1000 + index}',
        name: 'Product ${1000 + index}',
      ),
    );
    final harness = _Harness.withInvoker(database, (parameters, call) async {
      if (call == 0) {
        return _productResponse(
          firstRows,
          hasMore: true,
          nextToken: 'tail-token',
        );
      }
      expect((await _product(database, 'stale')).deletedAt, isNull);
      return _productResponse(tailRows);
    });

    final result = await harness.service.download(_productsRequest);

    expect(result.pagesApplied, 2);
    expect(result.rowsReceived, 1005);
    expect(await database.select(database.products).get(), hasLength(1006));
    expect((await _product(database, 'stale')).deletedAt, isNotNull);
    expect(await _seenCount(database), 1005);
  });

  test('sweep preserves identities created or remotely recognized after window',
      () async {
    await _insertProduct(
      database,
      id: 'created-later',
      name: 'Created later',
      createdAt: DateTime.utc(2026, 8, 15, 9, 30),
    );
    await _insertProduct(
      database,
      id: 'recognized-later',
      name: 'Recognized later',
      syncStatus: SyncStatus.pendingInsert,
    );
    await _insertOutbox(
      database,
      entityTable: 'products',
      entityId: 'recognized-later',
      batchStatus: 'completed',
      mutationStatus: 'applied',
      uploadedAt: DateTime.utc(2026, 8, 15, 9, 30),
    );
    final harness = _Harness(database, [_productResponse(const [])]);

    await harness.service.download(_productsRequest);

    expect((await _product(database, 'created-later')).deletedAt, isNull);
    expect((await _product(database, 'recognized-later')).deletedAt, isNull);
    expect(await _issues(database), isEmpty);
  });

  test('categories reconcile in business scope without inventing outbox',
      () async {
    await _insertCategory(database, id: 'category-1', name: 'Vieja');
    final harness = _Harness(database, [
      _datasetResponse(
        dataset: 'categories',
        rows: [
          productOperationalCategoryRow(id: 'category-1', name: 'Nueva'),
          productOperationalCategoryRow(id: 'category-2', name: 'Otra'),
        ],
      ),
    ]);

    await harness.service.download(_requestFor('categories'));

    final categories = await database.select(database.categories).get();
    expect(categories.map((item) => item.name), containsAll(['Nueva', 'Otra']));
    expect(categories.every((item) => item.syncStatus == SyncStatus.synced),
        isTrue);
    expect(await database.select(database.localSyncMutations).get(), isEmpty);
  });

  test('barcode maps to existing product and rejects an invalid relation',
      () async {
    await _insertProduct(
      database,
      id: 'product-1',
      name: 'Dirty product',
      syncStatus: SyncStatus.pendingUpdate,
    );
    final success = _Harness(database, [
      _datasetResponse(
        dataset: 'product_barcodes',
        rows: [productOperationalBarcodeRow(id: 'barcode-1')],
      ),
    ]);
    await success.service.download(_requestFor('product_barcodes'));

    final barcode =
        (await database.select(database.localProductBarcodes).get()).single;
    expect(barcode.productId, 'product-1');
    expect(barcode.businessId, 'business-a');
    expect(barcode.syncStatus, 'synced');
    expect(barcode.localStatus, 'clean');
    expect((await _product(database, 'product-1')).name, 'Dirty product');

    final invalid = _Harness(database, [
      _datasetResponse(
        snapshotId: 'snapshot-invalid-barcode',
        dataset: 'product_barcodes',
        rows: [
          productOperationalBarcodeRow(
            id: 'barcode-invalid',
            productId: 'missing-product',
          ),
        ],
      ),
    ]);
    await expectLater(
      invalid.service.download(_requestFor('product_barcodes')),
      throwsA(_kind(OperationalBootstrapFailureKind.localPersistence)),
    );
    expect(
      (await database.select(database.localProductBarcodes).get())
          .where((item) => item.id == 'barcode-invalid'),
      isEmpty,
    );
  });

  test('dirty barcode payload and outbox are preserved against remote',
      () async {
    await _insertProduct(database, id: 'product-1', name: 'Product');
    await database.into(database.localProductBarcodes).insert(
          LocalProductBarcodesCompanion.insert(
            id: 'barcode-dirty',
            scope: 'business',
            businessId: const Value('business-a'),
            productId: const Value('product-1'),
            barcode: 'LOCAL',
            barcodeNormalized: 'LOCAL',
            syncStatus: const Value('pending_upload'),
            localStatus: const Value('dirty'),
            createdAt: Value(DateTime.utc(2026, 8, 1)),
          ),
        );
    await _insertOutbox(
      database,
      entityTable: 'product_barcodes',
      entityId: 'barcode-dirty',
      batchStatus: 'uploading',
      mutationStatus: 'pending',
    );
    final harness = _Harness(database, [
      _datasetResponse(
        dataset: 'product_barcodes',
        rows: [
          productOperationalBarcodeRow(
            id: 'barcode-dirty',
            barcode: 'REMOTE',
            barcodeNormalized: 'REMOTE',
          ),
        ],
      ),
    ]);

    await harness.service.download(_requestFor('product_barcodes'));

    final barcode =
        (await database.select(database.localProductBarcodes).get()).single;
    expect(barcode.barcode, 'LOCAL');
    expect(barcode.localStatus, 'dirty');
    expect((await _issues(database)).single['issue_type'], 'dirty_vs_remote');
    expect(
        await database.select(database.localSyncMutations).get(), hasLength(1));
  });

  test('global barcode explicit rows apply but absence sweep is not inferred',
      () async {
    await database.into(database.localProductBarcodes).insert(
          LocalProductBarcodesCompanion.insert(
            id: 'global-existing',
            scope: 'global',
            masterProductId: const Value('master-old'),
            barcode: '7700000000099',
            barcodeNormalized: '7700000000099',
            createdAt: Value(DateTime.utc(2026, 8, 1)),
          ),
        );
    final harness = _Harness(database, [
      _datasetResponse(
        dataset: 'product_barcodes',
        rows: [
          productOperationalBarcodeRow(
            id: 'global-new',
            scope: 'global',
            businessId: null,
            productId: null,
            masterProductId: 'master-new',
          ),
        ],
      ),
    ]);

    await harness.service.download(_requestFor('product_barcodes'));

    final barcodes = await database.select(database.localProductBarcodes).get();
    expect(barcodes.map((item) => item.id),
        containsAll(['global-existing', 'global-new']));
    expect(
      barcodes.singleWhere((item) => item.id == 'global-existing').deletedAt,
      isNull,
    );
  });

  test('snapshot for A does not touch B and product remains shared by branches',
      () async {
    await _insertCategory(
      database,
      id: 'category-b',
      businessId: 'business-b',
      name: 'B',
    );
    await _insertProduct(
      database,
      id: 'product-b',
      businessId: 'business-b',
      categoryId: 'category-b',
      name: 'Product B',
    );
    final branchX = _Harness(database, [
      _productResponse([
        productOperationalProductRow(id: 'shared', name: 'Shared X'),
      ]),
    ]);
    await branchX.service.download(_productsRequest);

    final branchY = _Harness(database, [
      _productResponse(
        [productOperationalProductRow(id: 'shared', name: 'Shared Y')],
        snapshotId: 'snapshot-y',
        branchId: 'branch-y',
      ),
    ]);
    await branchY.service.download(
      const OperationalBootstrapDownloadRequest(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-y',
        appDeviceId: 'device-a',
        bundle: 'product_operational',
        dataset: 'products',
        limit: 1000,
      ),
    );

    expect(await database.select(database.products).get(), hasLength(2));
    expect((await _product(database, 'shared')).name, 'Shared Y');
    expect((await _product(database, 'product-b')).deletedAt, isNull);
  });

  test('checkpoint failure rolls back entity, seen journal and sweep',
      () async {
    await _insertProduct(database, id: 'stale', name: 'Stale');
    final harness = _Harness(
      database,
      [
        _productResponse([
          productOperationalProductRow(id: 'new-product', name: 'New'),
        ]),
      ],
      checkpointDao: _FailingCheckpointDao(database),
    );

    await expectLater(
      harness.service.download(_productsRequest),
      throwsA(_kind(OperationalBootstrapFailureKind.localPersistence)),
    );

    expect(
      (await database.select(database.products).get())
          .where((item) => item.id == 'new-product'),
      isEmpty,
    );
    expect((await _product(database, 'stale')).deletedAt, isNull);
    expect(await _seenCount(database), 0);
  });

  test('router rejects balance dataset because R1.3f does not apply balances',
      () async {
    final harness = _Harness(database, [
      _datasetResponse(dataset: 'product_stock_balances', rows: const []),
    ]);

    await expectLater(
      harness.service.download(_requestFor('product_stock_balances')),
      throwsA(_kind(OperationalBootstrapFailureKind.malformedResponse)),
    );
    expect(
      await database.select(database.localProductStockBalances).get(),
      isEmpty,
    );
  });
}

const _productsRequest = OperationalBootstrapDownloadRequest(
  profileId: 'profile-a',
  businessId: 'business-a',
  branchId: 'branch-x',
  appDeviceId: 'device-a',
  bundle: 'product_operational',
  dataset: 'products',
  limit: 1000,
);

OperationalBootstrapDownloadRequest _requestFor(String dataset) {
  return OperationalBootstrapDownloadRequest(
    profileId: 'profile-a',
    businessId: 'business-a',
    branchId: 'branch-x',
    appDeviceId: 'device-a',
    bundle: 'product_operational',
    dataset: dataset,
    limit: 1000,
  );
}

Map<String, Object?> _productResponse(
  List<Map<String, Object?>> rows, {
  bool hasMore = false,
  String? nextToken,
  String snapshotId = 'snapshot-1',
  String branchId = 'branch-x',
}) {
  return _datasetResponse(
    dataset: 'products',
    rows: rows,
    hasMore: hasMore,
    nextToken: nextToken,
    snapshotId: snapshotId,
    branchId: branchId,
  );
}

Map<String, Object?> _datasetResponse({
  required String dataset,
  required List<Map<String, Object?>> rows,
  bool hasMore = false,
  String? nextToken,
  String snapshotId = 'snapshot-1',
  String branchId = 'branch-x',
}) {
  return bootstrapRpcResponse(
    snapshotId: snapshotId,
    branchId: branchId,
    datasetRequested: dataset,
    datasets: {
      dataset: bootstrapDatasetPage(
        dataset: dataset,
        rows: rows,
        hasMore: hasMore,
        nextPageToken: nextToken,
      ),
    },
  );
}

Future<void> _insertBusiness(AppDatabase database, String id) {
  return database.into(database.businesses).insert(
        BusinessesCompanion.insert(id: id, name: 'Business $id'),
      );
}

Future<void> _insertCategory(
  AppDatabase database, {
  required String id,
  String businessId = 'business-a',
  required String name,
  SyncStatus syncStatus = SyncStatus.synced,
}) {
  return database.into(database.categories).insert(
        CategoriesCompanion.insert(
          id: id,
          businessId: Value(businessId),
          name: name,
          createdAt: Value(DateTime.utc(2026, 8, 1)),
          updatedAt: Value(DateTime.utc(2026, 8, 1)),
          syncStatus: Value(syncStatus),
        ),
      );
}

Future<void> _insertProduct(
  AppDatabase database, {
  required String id,
  String businessId = 'business-a',
  String? categoryId,
  required String name,
  int minimumStock = 0,
  SyncStatus syncStatus = SyncStatus.synced,
  DateTime? createdAt,
  DateTime? updatedAt,
}) {
  return database.into(database.products).insert(
        ProductsCompanion.insert(
          id: id,
          businessId: Value(businessId),
          categoryId: Value(categoryId),
          name: name,
          salePrice: 10,
          minimumStock: Value(minimumStock),
          createdAt: Value(createdAt ?? DateTime.utc(2026, 8, 1)),
          updatedAt: Value(updatedAt ?? DateTime.utc(2026, 8, 1)),
          syncStatus: Value(syncStatus),
        ),
      );
}

Future<Product> _product(AppDatabase database, String id) {
  return (database.select(database.products)..where((row) => row.id.equals(id)))
      .getSingle();
}

Future<void> _insertOutbox(
  AppDatabase database, {
  required String entityTable,
  required String entityId,
  required String batchStatus,
  required String mutationStatus,
  DateTime? uploadedAt,
}) async {
  final batchId = 'batch-$entityId';
  await database.into(database.localSyncBatches).insert(
        LocalSyncBatchesCompanion.insert(
          id: batchId,
          clientBatchId: 'client-$batchId',
          businessId: 'business-a',
          domain: 'catalog',
          status: Value(batchStatus),
          mutationCount: const Value(1),
          uploadedAt: Value(uploadedAt),
        ),
      );
  await database.into(database.localSyncMutations).insert(
        LocalSyncMutationsCompanion.insert(
          id: 'mutation-$entityId',
          localSyncBatchId: Value(batchId),
          clientBatchId: Value('client-$batchId'),
          clientMutationId: 'client-mutation-$entityId',
          clientSequence: 1,
          businessId: 'business-a',
          entityTable: entityTable,
          entityId: entityId,
          operation: 'upsert',
          payloadJson: '{}',
          idempotencyKey: 'idempotency-$entityId',
          status: Value(mutationStatus),
          uploadedAt: Value(uploadedAt),
        ),
      );
}

Future<List<Map<String, dynamic>>> _issues(AppDatabase database) {
  return ReconciliationIssueLocalDao(database).getIssues(
    profileId: 'profile-a',
    businessId: 'business-a',
    branchId: 'branch-x',
    domain: 'catalog',
  );
}

Future<int> _seenCount(AppDatabase database) async {
  final row = await database.customSelect(
    'select count(*) as count from local_operational_bootstrap_seen_records',
    readsFrom: {database.localOperationalBootstrapSeenRecords},
  ).getSingle();
  return row.read<int>('count');
}

Matcher _kind(OperationalBootstrapFailureKind kind) {
  return isA<OperationalBootstrapException>().having(
    (error) => error.kind,
    'kind',
    kind,
  );
}

typedef _Invoker = Future<Object?> Function(
  Map<String, Object?> parameters,
  int call,
);

class _Harness {
  _Harness(
    AppDatabase database,
    List<Object> outcomes, {
    OperationalBootstrapCheckpointLocalDao? checkpointDao,
  }) : this.withInvoker(
          database,
          (parameters, call) async {
            final outcome = outcomes[call];
            if (outcome is Exception) {
              throw outcome;
            }
            return outcome;
          },
          checkpointDao: checkpointDao,
        );

  _Harness.withInvoker(
    AppDatabase database,
    _Invoker invoke, {
    OperationalBootstrapCheckpointLocalDao? checkpointDao,
  }) {
    var calls = 0;
    final seenDao = OperationalBootstrapSeenRecordLocalDao(database);
    final issueDao = ReconciliationIssueLocalDao(database);
    final localDao = ProductOperationalReconciliationLocalDao(database);
    final support = ProductOperationalReconciliationSupport(
      stateResolver: CatalogEntitySyncStateResolver(database),
      issueDao: issueDao,
      seenRecordDao: seenDao,
    );
    final router = OperationalBootstrapPageApplierRouter(
      routes: <String, OperationalBootstrapPageApplier>{
        'product_operational/categories': CategorySnapshotApplier(
          localDao: localDao,
          support: support,
        ),
        'product_operational/products': ProductSnapshotApplier(
          localDao: localDao,
          support: support,
        ),
        'product_operational/product_barcodes': ProductBarcodeSnapshotApplier(
          localDao: localDao,
          support: support,
        ),
      },
    );
    service = OperationalBootstrapDownloadService(
      database: database,
      remoteDataSource: OperationalBootstrapRemoteDataSource.withInvoker(
        (parameters) => invoke(parameters, calls++),
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
  }

  late final OperationalBootstrapDownloadService service;
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
