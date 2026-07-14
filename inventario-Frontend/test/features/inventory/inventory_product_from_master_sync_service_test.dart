import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_creation_models.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_from_master_sync_service.dart';
import 'package:inventario_frontend/features/sync/data/models/local_sync_outbox_models.dart';

void main() {
  group('mapPendingCatalogMutationToLocalSyncDraft', () {
    test('maps inventory pending mutation to local sync mutation draft', () {
      const pendingMutation = PendingCatalogSyncMutationDraft(
        clientMutationId: 'installation-1:mutation:1',
        clientSequence: 1,
        entityTable: 'products',
        entityId: 'product-1',
        operation: 'insert',
        payload: {
          'id': 'product-1',
          'business_id': 'business-1',
          'name': 'Producto Test',
        },
        changedFields: ['id', 'business_id', 'name'],
        idempotencyKey: 'installation-1:products:product-1:insert:1',
        businessId: 'business-1',
        branchId: 'branch-1',
        profileId: 'profile-1',
        appDeviceId: 'device-1',
      );

      final draft = mapPendingCatalogMutationToLocalSyncDraft(pendingMutation);

      expect(draft, isA<LocalSyncMutationDraft>());
      expect(draft.clientMutationId, equals('installation-1:mutation:1'));
      expect(draft.clientSequence, equals(1));
      expect(draft.entityTable, equals('products'));
      expect(draft.entityId, equals('product-1'));
      expect(draft.operation, equals('insert'));
      expect(draft.payload['name'], equals('Producto Test'));
      expect(draft.changedFields, contains('business_id'));
      expect(
        draft.idempotencyKey,
        equals('installation-1:products:product-1:insert:1'),
      );
      expect(draft.businessId, equals('business-1'));
      expect(draft.branchId, equals('branch-1'));
      expect(draft.profileId, equals('profile-1'));
      expect(draft.appDeviceId, equals('device-1'));
    });
  });

  group('InventoryProductFromMasterSyncResult', () {
    test('serializes result to json', () {
      const result = InventoryProductFromMasterSyncResult(
        createdProduct: CreatedLocalProductResult(
          productId: 'product-1',
          businessId: 'business-1',
          masterProductId: 'master-1',
          barcode: '7706191234567',
          barcodeNormalized: '7706191234567',
          name: 'Producto Test',
          productPayload: {
            'id': 'product-1',
            'business_id': 'business-1',
            'name': 'Producto Test',
          },
          businessBarcodePayload: {
            'id': 'barcode-1',
            'scope': 'business',
            'product_id': 'product-1',
          },
          pendingMutations: [],
        ),
        outboxResult: LocalSyncEnqueueResult(
          localBatchId: 'local-batch-1',
          clientBatchId: 'installation-1:batch:1',
          domain: 'catalog',
          mutationCount: 2,
        ),
      );

      final json = result.toJson();

      expect(json['created_product'], isA<Map<String, dynamic>>());
      expect(json['outbox_result'], isA<Map<String, dynamic>>());
      expect(
        (json['outbox_result'] as Map<String, dynamic>)['domain'],
        equals('catalog'),
      );
    });
  });
}
