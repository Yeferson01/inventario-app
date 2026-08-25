import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/purchase_local_dao.dart';
import 'package:inventario_frontend/features/sync/application/catalog_sync_upload_service.dart';
import 'package:inventario_frontend/features/sync/application/local_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sync/application/purchase_product_dependency_resolver.dart';
import 'package:inventario_frontend/features/sync/application/purchases_sync_upload_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/catalog_sync_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/datasources/local_sync_outbox_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/purchase_product_dependency_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/purchases_sync_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/models/catalog_upload_models.dart';
import 'package:inventario_frontend/features/sync/data/models/local_sync_outbox_models.dart';

void main() {
  late AppDatabase database;
  late LocalSyncOutboxDao outboxDao;
  late LocalSyncOutboxService outboxService;
  late PurchaseProductDependencyResolver resolver;

  setUp(() async {
    database = AppDatabase.executor(NativeDatabase.memory());
    outboxDao = LocalSyncOutboxDao(database);
    outboxService = LocalSyncOutboxService(outboxDao);
    resolver = PurchaseProductDependencyResolver(
      PurchaseProductDependencyLocalDao(database),
    );
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(
            id: 'business-a',
            name: 'Business A',
          ),
        );
  });

  tearDown(() => database.close());

  test('pending local Product defers direct purchase upload and retry proceeds',
      () async {
    await _insertProduct(
      database,
      id: 'product-pending',
      syncStatus: SyncStatus.pendingInsert,
    );
    final catalog = await _enqueueCatalog(
      outboxService,
      productIds: const ['product-pending'],
    );
    await _enqueuePurchase(
      outboxService,
      productIds: const ['product-pending'],
    );
    final remote = _FakePurchasesRemoteDataSource();

    final first = await _uploader(
      database,
      outboxService,
      resolver,
      remote,
    ).uploadPendingPurchasesBatches(
      businessId: 'business-a',
      branchId: 'branch-a',
    );

    expect(first.batchesWaitingForDependencies, 1);
    expect(first.batchesUploaded, 0);
    expect(first.waitingProductIds, ['product-pending']);
    expect(remote.uploadCalls, 0);
    expect(await _purchaseBatchStatus(database), 'pending');

    final catalogMutations = await outboxService.getMutationsForBatch(
      catalog.localBatchId,
    );
    await outboxService.markMutationApplied(
      localMutationId: catalogMutations.single['id'].toString(),
    );
    await outboxService.markBatchCompleted(
      localBatchId: catalog.localBatchId,
      appliedCount: 1,
    );

    final restartedResolver = PurchaseProductDependencyResolver(
      PurchaseProductDependencyLocalDao(database),
    );
    final second = await _uploader(
      database,
      outboxService,
      restartedResolver,
      remote,
    ).uploadPendingPurchasesBatches(
      businessId: 'business-a',
      branchId: 'branch-a',
    );

    expect(second.batchesCompleted, 1);
    expect(second.batchesWaitingForDependencies, 0);
    expect(remote.uploadCalls, 1);
  });

  test('clean Product from bootstrap proceeds without catalog mutation',
      () async {
    await _insertProduct(
      database,
      id: 'product-bootstrap',
      syncStatus: SyncStatus.synced,
    );
    await _enqueuePurchase(
      outboxService,
      productIds: const ['product-bootstrap'],
    );
    final remote = _FakePurchasesRemoteDataSource();

    final result = await _uploader(
      database,
      outboxService,
      resolver,
      remote,
    ).uploadPendingPurchasesBatches(
      businessId: 'business-a',
      branchId: 'branch-a',
    );

    expect(result.batchesCompleted, 1);
    expect(remote.uploadCalls, 1);
  });

  test('Product applied plus barcode conflict still satisfies purchase',
      () async {
    await _insertProduct(
      database,
      id: 'product-applied',
      syncStatus: SyncStatus.pendingInsert,
    );
    await _enqueueCatalog(
      outboxService,
      productIds: const ['product-applied'],
      includeBarcode: true,
    );
    await CatalogSyncUploadService(
      outboxService: outboxService,
      remoteDataSource: _PartialCatalogRemoteDataSource(),
    ).uploadPendingCatalogBatches(businessId: 'business-a');
    expect(
      await outboxService.hasMutationForEntity(
        businessId: 'business-a',
        domain: 'catalog',
        entityTable: 'products',
        entityId: 'product-applied',
      ),
      isTrue,
    );
    await _enqueuePurchase(
      outboxService,
      productIds: const ['product-applied'],
    );
    final remote = _FakePurchasesRemoteDataSource();

    final result = await _uploader(
      database,
      outboxService,
      resolver,
      remote,
    ).uploadPendingPurchasesBatches(
      businessId: 'business-a',
      branchId: 'branch-a',
    );

    final catalogStatuses = await database.customSelect(
      '''
      select entity_table, status
      from local_sync_mutations
      where business_id = 'business-a' and entity_table in ('products', 'product_barcodes')
      order by entity_table
      ''',
    ).get();
    expect(
      {
        for (final row in catalogStatuses)
          row.data['entity_table']: row.data['status']
      },
      {
        'product_barcodes': 'conflict',
        'products': 'applied',
      },
    );
    expect(result.batchesCompleted, 1);
    expect(remote.uploadCalls, 1);
  });

  test('Product conflict blocks purchase without changing purchase outbox',
      () async {
    await _insertProduct(
      database,
      id: 'product-conflict',
      syncStatus: SyncStatus.synced,
    );
    final catalog = await _enqueueCatalog(
      outboxService,
      productIds: const ['product-conflict'],
    );
    final catalogMutations = await outboxService.getMutationsForBatch(
      catalog.localBatchId,
    );
    await outboxService.markMutationConflict(
      localMutationId: catalogMutations.single['id'].toString(),
      errorCode: 'validation_error',
      errorMessage: 'Product inválido',
    );
    await outboxService.markBatchPartial(
      localBatchId: catalog.localBatchId,
      conflictCount: 1,
    );
    await _enqueuePurchase(
      outboxService,
      productIds: const ['product-conflict'],
    );
    final remote = _FakePurchasesRemoteDataSource();

    final result = await _uploader(
      database,
      outboxService,
      resolver,
      remote,
    ).uploadPendingPurchasesBatches(
      businessId: 'business-a',
      branchId: 'branch-a',
    );

    expect(result.batchesBlockedByDependencies, 1);
    expect(result.blockedProductIds, ['product-conflict']);
    expect(result.dependencyIssues.single.code, 'product_dependency_conflict');
    expect(remote.uploadCalls, 0);
    expect(await _purchaseBatchStatus(database), 'pending');
  });

  test('one pending Product defers the entire deduplicated multi-product batch',
      () async {
    await _insertProduct(
      database,
      id: 'product-ready',
      syncStatus: SyncStatus.synced,
      masterProductId: 'master-1',
    );
    await _insertProduct(
      database,
      id: 'product-pending',
      syncStatus: SyncStatus.pendingInsert,
    );
    await _enqueueCatalog(
      outboxService,
      productIds: const ['product-pending'],
    );
    final purchase = await _enqueuePurchase(
      outboxService,
      productIds: const [
        'product-ready',
        'product-pending',
        'product-ready',
      ],
    );
    final mutations = await outboxService.getMutationsForBatch(
      purchase.localBatchId,
    );

    final resolution = await resolver.resolve(
      businessId: 'business-a',
      purchaseMutations: mutations,
    );

    expect(
      resolution.requiredProductIds,
      ['product-pending', 'product-ready'],
    );
    expect(resolution.status, PurchaseProductDependencyStatus.waiting);

    final remote = _FakePurchasesRemoteDataSource();
    final result = await _uploader(
      database,
      outboxService,
      resolver,
      remote,
    ).uploadPendingPurchasesBatches(
      businessId: 'business-a',
      branchId: 'branch-a',
    );
    expect(result.batchesWaitingForDependencies, 1);
    expect(remote.uploadCalls, 0);
  });

  test('soft-deleted Product is blocked under the current backend contract',
      () async {
    await _insertProduct(
      database,
      id: 'product-deleted',
      syncStatus: SyncStatus.synced,
      deletedAt: DateTime.utc(2026, 8, 25),
    );
    final purchase = await _enqueuePurchase(
      outboxService,
      productIds: const ['product-deleted'],
    );
    final mutations = await outboxService.getMutationsForBatch(
      purchase.localBatchId,
    );

    final resolution = await resolver.resolve(
      businessId: 'business-a',
      purchaseMutations: mutations,
    );

    expect(resolution.status, PurchaseProductDependencyStatus.blocked);
    expect(resolution.issues.single.code, 'product_soft_deleted');
  });

  test('Product evidence from another business never satisfies a purchase',
      () async {
    await database.into(database.businesses).insert(
          BusinessesCompanion.insert(
            id: 'business-b',
            name: 'Business B',
          ),
        );
    await database.into(database.products).insert(
          ProductsCompanion.insert(
            id: 'product-foreign',
            businessId: const Value('business-b'),
            name: 'Foreign Product',
            salePrice: 1,
            syncStatus: const Value(SyncStatus.synced),
          ),
        );
    final purchase = await _enqueuePurchase(
      outboxService,
      productIds: const ['product-foreign'],
    );
    final mutations = await outboxService.getMutationsForBatch(
      purchase.localBatchId,
    );

    final resolution = await resolver.resolve(
      businessId: 'business-a',
      purchaseMutations: mutations,
    );

    expect(resolution.status, PurchaseProductDependencyStatus.blocked);
    expect(
      resolution.issues.single.code,
      'product_not_in_purchase_business',
    );
  });
}

PurchasesSyncUploadService _uploader(
  AppDatabase database,
  LocalSyncOutboxService outboxService,
  PurchaseProductDependencyResolver resolver,
  PurchasesSyncRemoteDataSource remote,
) {
  return PurchasesSyncUploadService(
    outboxService: outboxService,
    remoteDataSource: remote,
    purchaseLocalDao: PurchaseLocalDao(database),
    dependencyResolver: resolver,
  );
}

Future<void> _insertProduct(
  AppDatabase database, {
  required String id,
  required SyncStatus syncStatus,
  String? masterProductId,
  DateTime? deletedAt,
}) {
  return database.into(database.products).insert(
        ProductsCompanion.insert(
          id: id,
          businessId: const Value('business-a'),
          masterProductId: Value(masterProductId),
          name: id,
          salePrice: 1,
          syncStatus: Value(syncStatus),
          deletedAt: Value(deletedAt),
        ),
      );
}

Future<LocalSyncEnqueueResult> _enqueueCatalog(
  LocalSyncOutboxService outboxService, {
  required List<String> productIds,
  bool includeBarcode = false,
}) {
  final mutations = <LocalSyncMutationDraft>[];
  var sequence = 1;
  for (final productId in productIds) {
    mutations.add(
      LocalSyncMutationDraft(
        clientMutationId: 'catalog-product-$productId',
        clientSequence: sequence++,
        entityTable: 'products',
        entityId: productId,
        operation: 'insert',
        payload: {
          'id': productId,
          'business_id': 'business-a',
        },
        changedFields: const ['id', 'business_id'],
        idempotencyKey: 'catalog-product-$productId',
        businessId: 'business-a',
      ),
    );
  }
  if (includeBarcode) {
    mutations.add(
      LocalSyncMutationDraft(
        clientMutationId: 'catalog-barcode-1',
        clientSequence: sequence,
        entityTable: 'product_barcodes',
        entityId: 'barcode-1',
        operation: 'insert',
        payload: const {
          'id': 'barcode-1',
          'business_id': 'business-a',
          'product_id': 'product-applied',
        },
        changedFields: const ['id', 'business_id', 'product_id'],
        idempotencyKey: 'catalog-barcode-1',
        businessId: 'business-a',
      ),
    );
  }
  return outboxService.enqueueCatalogMutations(
    businessId: 'business-a',
    mutations: mutations,
  );
}

Future<LocalSyncEnqueueResult> _enqueuePurchase(
  LocalSyncOutboxService outboxService, {
  required List<String> productIds,
}) {
  final purchaseId = 'purchase-${DateTime.now().microsecondsSinceEpoch}';
  final mutations = <LocalSyncMutationDraft>[
    LocalSyncMutationDraft(
      clientMutationId: '$purchaseId-mutation',
      clientSequence: 1,
      entityTable: 'purchases',
      entityId: purchaseId,
      operation: 'insert',
      payload: {
        'id': purchaseId,
        'business_id': 'business-a',
        'branch_id': 'branch-a',
      },
      changedFields: const ['id', 'business_id', 'branch_id'],
      idempotencyKey: '$purchaseId-insert',
      businessId: 'business-a',
      branchId: 'branch-a',
    ),
  ];
  for (var index = 0; index < productIds.length; index++) {
    final itemId = '$purchaseId-item-$index';
    mutations.add(
      LocalSyncMutationDraft(
        clientMutationId: '$itemId-mutation',
        clientSequence: index + 2,
        entityTable: 'purchase_items',
        entityId: itemId,
        operation: 'insert',
        payload: {
          'id': itemId,
          'purchase_id': purchaseId,
          'business_id': 'business-a',
          'branch_id': 'branch-a',
          'product_id': productIds[index],
        },
        changedFields: const [
          'id',
          'purchase_id',
          'business_id',
          'branch_id',
          'product_id',
        ],
        idempotencyKey: '$itemId-insert',
        businessId: 'business-a',
        branchId: 'branch-a',
      ),
    );
  }
  return outboxService.enqueueUploadBatch(
    businessId: 'business-a',
    branchId: 'branch-a',
    domain: 'purchases',
    mutations: mutations,
  );
}

Future<String?> _purchaseBatchStatus(AppDatabase database) async {
  final row = await database
      .customSelect(
        "select status from local_sync_batches where domain = 'purchases' limit 1",
      )
      .getSingleOrNull();
  return row?.data['status']?.toString();
}

class _FakePurchasesRemoteDataSource implements PurchasesSyncRemoteDataSource {
  int uploadCalls = 0;

  @override
  Future<bool> allPurchaseMutationEntitiesAlreadyExist({
    required List<Map<String, dynamic>> localMutations,
  }) async {
    return false;
  }

  @override
  Future<bool> duplicatePurchasesConflictsAreIdempotent({
    required String serverBatchId,
    required List<Map<String, dynamic>> localMutations,
  }) async {
    return false;
  }

  @override
  Future<CatalogUploadBatchResult> uploadAndProcessPurchasesBatch({
    required Map<String, dynamic> localBatch,
    required List<Map<String, dynamic>> localMutations,
  }) async {
    uploadCalls++;
    return CatalogUploadBatchResult(
      localBatchId: localBatch['id'].toString(),
      serverBatchId: 'server-purchase-batch-$uploadCalls',
      status: 'completed',
      mutationCount: localMutations.length,
      appliedCount: localMutations.length,
      skippedCount: 0,
      conflictCount: 0,
      errorCount: 0,
      raw: const {},
    );
  }
}

class _PartialCatalogRemoteDataSource implements CatalogSyncRemoteDataSource {
  @override
  Future<bool> duplicateCatalogConflictsAreIdempotent({
    required String serverBatchId,
  }) async {
    return false;
  }

  @override
  Future<CatalogUploadBatchResult> uploadAndProcessCatalogBatch({
    required Map<String, dynamic> localBatch,
    required List<Map<String, dynamic>> localMutations,
  }) async {
    return CatalogUploadBatchResult(
      localBatchId: localBatch['id'].toString(),
      serverBatchId: 'server-catalog-batch',
      status: 'partial',
      mutationCount: 2,
      appliedCount: 1,
      skippedCount: 0,
      conflictCount: 1,
      errorCount: 0,
      raw: const {},
      mutationResults: const [
        CatalogUploadMutationResult(
          serverMutationId: 'server-product-mutation',
          idempotencyKey: 'catalog-product-product-applied',
          entityTable: 'products',
          entityId: 'product-applied',
          status: 'applied',
        ),
        CatalogUploadMutationResult(
          serverMutationId: 'server-barcode-mutation',
          idempotencyKey: 'catalog-barcode-1',
          entityTable: 'product_barcodes',
          entityId: 'barcode-1',
          status: 'conflict',
          errorCode: 'permission_denied',
          errorMessage: 'Barcode pendiente de CATALOG-2E',
        ),
      ],
    );
  }
}
