import '../../sync/application/local_sync_outbox_service.dart';
import '../../sync/data/models/local_sync_outbox_models.dart';
import 'inventory_product_creation_models.dart';
import 'inventory_product_creation_service.dart';

class InventoryProductFromMasterSyncResult {
  const InventoryProductFromMasterSyncResult({
    required this.createdProduct,
    required this.outboxResult,
  });

  final CreatedLocalProductResult createdProduct;
  final LocalSyncEnqueueResult outboxResult;

  Map<String, dynamic> toJson() {
    return {
      'created_product': createdProduct.toJson(),
      'outbox_result': outboxResult.toJson(),
    };
  }
}

class InventoryManualProductSyncResult {
  const InventoryManualProductSyncResult({
    required this.createdProduct,
    required this.outboxResult,
  });

  final CreatedManualLocalProductResult createdProduct;
  final LocalSyncEnqueueResult outboxResult;

  Map<String, dynamic> toJson() {
    return {
      'created_product': createdProduct.toJson(),
      'outbox_result': outboxResult.toJson(),
    };
  }
}

class InventoryProductMasterLinkSyncResult {
  const InventoryProductMasterLinkSyncResult({
    required this.linkedProduct,
    required this.outboxResult,
  });

  final LinkedLocalProductToMasterResult linkedProduct;
  final LocalSyncEnqueueResult outboxResult;

  Map<String, dynamic> toJson() {
    return {
      'linked_product': linkedProduct.toJson(),
      'outbox_result': outboxResult.toJson(),
    };
  }
}

class InventoryProductFromMasterSyncService {
  InventoryProductFromMasterSyncService({
    required InventoryProductCreationService productCreationService,
    required LocalSyncOutboxService outboxService,
  })  : _productCreationService = productCreationService,
        _outboxService = outboxService;

  final InventoryProductCreationService _productCreationService;
  final LocalSyncOutboxService _outboxService;

  Future<int> enqueueManualProductsUsedByUnsyncedPurchasesForCatalogSync({
    required String businessId,
    required String branchId,
    String? profileId,
    String? appDeviceId,
    String? deviceInstallationId,
    int limit = 100,
  }) async {
    final productIds = await _productCreationService
        .getManualProductIdsUsedByUnsyncedPurchases(
      businessId: businessId,
      branchId: branchId,
      limit: limit,
    );

    var enqueued = 0;
    var sequence =
        DateTime.now().toUtc().microsecondsSinceEpoch.remainder(2000000000);

    for (final productId in productIds) {
      final alreadyQueued = await _outboxService.hasMutationForEntity(
        businessId: businessId,
        domain: 'catalog',
        entityTable: 'products',
        entityId: productId,
      );

      if (alreadyQueued) {
        continue;
      }

      final createdProduct = await _productCreationService
          .buildExistingManualProductCatalogSyncDraft(
        businessId: businessId,
        branchId: branchId,
        profileId: profileId,
        appDeviceId: appDeviceId,
        deviceInstallationId: deviceInstallationId,
        productId: productId,
        clientSequenceStart: sequence,
      );

      if (createdProduct == null) {
        continue;
      }

      final mutations = createdProduct.pendingMutations
          .map(mapPendingCatalogMutationToLocalSyncDraft)
          .toList();

      await _outboxService.enqueueCatalogMutations(
        businessId: businessId,
        branchId: branchId,
        appDeviceId: appDeviceId,
        profileId: profileId,
        deviceInstallationId: deviceInstallationId,
        mutations: mutations,
        metadata: {
          'source': 'purchase_catalog_backfill',
          'product_id': createdProduct.productId,
          'barcode_normalized': createdProduct.barcodeNormalized,
          'catalog_status': 'manual_unmatched',
        },
      );

      enqueued++;
      sequence += 10;
    }

    return enqueued;
  }

  Future<InventoryManualProductSyncResult> createManualProductAndQueueSync(
    CreateManualLocalProductInput input,
  ) async {
    final createdProduct =
        await _productCreationService.createManualLocalProduct(input);

    final mutations = createdProduct.pendingMutations
        .map(mapPendingCatalogMutationToLocalSyncDraft)
        .toList();

    final outboxResult = await _outboxService.enqueueCatalogMutations(
      businessId: input.businessId,
      branchId: input.branchId,
      appDeviceId: input.appDeviceId,
      profileId: input.profileId,
      deviceInstallationId: input.deviceInstallationId,
      mutations: mutations,
      metadata: {
        'source': 'quick_purchase_manual_product',
        'product_id': createdProduct.productId,
        'barcode_normalized': createdProduct.barcodeNormalized,
        'catalog_status': 'manual_unmatched',
      },
    );

    return InventoryManualProductSyncResult(
      createdProduct: createdProduct,
      outboxResult: outboxResult,
    );
  }

  Future<InventoryProductFromMasterSyncResult> createProductAndQueueSync(
    CreateProductFromMasterInput input,
  ) async {
    final createdProduct =
        await _productCreationService.createLocalProductFromMaster(input);

    final mutations = createdProduct.pendingMutations
        .map(mapPendingCatalogMutationToLocalSyncDraft)
        .toList();

    final outboxResult = await _outboxService.enqueueCatalogMutations(
      businessId: input.businessId,
      branchId: input.branchId,
      appDeviceId: input.appDeviceId,
      profileId: input.profileId,
      deviceInstallationId: input.deviceInstallationId,
      mutations: mutations,
      metadata: {
        'source': 'inventory_product_from_master',
        'product_id': createdProduct.productId,
        'master_product_id': createdProduct.masterProductId,
        'barcode_normalized': createdProduct.barcodeNormalized,
      },
    );

    return InventoryProductFromMasterSyncResult(
      createdProduct: createdProduct,
      outboxResult: outboxResult,
    );
  }

  Future<InventoryProductMasterLinkSyncResult> linkProductToMasterAndQueueSync(
    LinkLocalProductToMasterInput input,
  ) async {
    final linkedProduct =
        await _productCreationService.linkLocalProductToMaster(input);
    final mutations = linkedProduct.pendingMutations
        .map(mapPendingCatalogMutationToLocalSyncDraft)
        .toList();
    final outboxResult = await _outboxService.enqueueCatalogMutations(
      businessId: input.businessId,
      branchId: input.branchId,
      appDeviceId: input.appDeviceId,
      profileId: input.profileId,
      deviceInstallationId: input.deviceInstallationId,
      mutations: mutations,
      metadata: {
        'source': 'manual_product_master_link',
        'product_id': input.productId,
        'master_product_id': input.masterProductId,
        'business_barcode_id': linkedProduct.businessBarcodeId,
      },
    );
    return InventoryProductMasterLinkSyncResult(
      linkedProduct: linkedProduct,
      outboxResult: outboxResult,
    );
  }
}

LocalSyncMutationDraft mapPendingCatalogMutationToLocalSyncDraft(
  PendingCatalogSyncMutationDraft mutation,
) {
  return LocalSyncMutationDraft(
    clientMutationId: mutation.clientMutationId,
    clientSequence: mutation.clientSequence,
    entityTable: mutation.entityTable,
    entityId: mutation.entityId,
    operation: mutation.operation,
    payload: mutation.payload,
    changedFields: mutation.changedFields,
    idempotencyKey: mutation.idempotencyKey,
    businessId: mutation.businessId,
    branchId: mutation.branchId,
    profileId: mutation.profileId,
    appDeviceId: mutation.appDeviceId,
  );
}
