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

class InventoryProductFromMasterSyncService {
  InventoryProductFromMasterSyncService({
    required InventoryProductCreationService productCreationService,
    required LocalSyncOutboxService outboxService,
  })  : _productCreationService = productCreationService,
        _outboxService = outboxService;

  final InventoryProductCreationService _productCreationService;
  final LocalSyncOutboxService _outboxService;

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
