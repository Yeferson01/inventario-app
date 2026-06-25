import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_creation_models.dart';

void main() {
  group('ProductFromMasterDraft', () {
    test('serializes to json', () {
      const draft = ProductFromMasterDraft(
        businessId: 'business-1',
        masterProductId: 'master-1',
        barcode: '7706191234567',
        barcodeNormalized: '7706191234567',
        barcodeType: 'ean13',
        name: 'Producto Test',
        brand: 'Marca Test',
        confidenceScore: 0.91,
      );

      final json = draft.toJson();

      expect(json['business_id'], equals('business-1'));
      expect(json['master_product_id'], equals('master-1'));
      expect(json['barcode'], equals('7706191234567'));
      expect(json['barcode_normalized'], equals('7706191234567'));
      expect(json['barcode_type'], equals('ean13'));
      expect(json['name'], equals('Producto Test'));
      expect(json['brand'], equals('Marca Test'));
      expect(json['confidence_score'], equals(0.91));
    });
  });

  group('PendingCatalogSyncMutationDraft', () {
    test('serializes sync mutation draft', () {
      const mutation = PendingCatalogSyncMutationDraft(
        clientMutationId: 'device-1:mutation:1',
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
        idempotencyKey: 'device-1:products:product-1:insert:1',
        businessId: 'business-1',
      );

      final json = mutation.toJson();

      expect(json['entity_table'], equals('products'));
      expect(json['operation'], equals('insert'));
      expect(json['client_sequence'], equals(1));
      expect(json['idempotency_key'],
          equals('device-1:products:product-1:insert:1'));
      expect(json['payload'], isA<Map<String, dynamic>>());
      expect(json['changed_fields'], isA<List<String>>());
    });
  });

  group('CreatedLocalProductResult', () {
    test('serializes created result with pending mutations', () {
      const result = CreatedLocalProductResult(
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
        pendingMutations: [
          PendingCatalogSyncMutationDraft(
            clientMutationId: 'device-1:mutation:1',
            clientSequence: 1,
            entityTable: 'products',
            entityId: 'product-1',
            operation: 'insert',
            payload: {
              'id': 'product-1',
            },
            changedFields: ['id'],
            idempotencyKey: 'device-1:products:product-1:insert:1',
          ),
        ],
      );

      final json = result.toJson();

      expect(json['product_id'], equals('product-1'));
      expect(json['business_id'], equals('business-1'));
      expect(json['master_product_id'], equals('master-1'));
      expect(json['pending_mutations'], isA<List<dynamic>>());
      expect((json['pending_mutations'] as List<dynamic>), hasLength(1));
    });
  });

  group('CreateProductFromMasterInput', () {
    test('keeps inventory confirmation values', () {
      const input = CreateProductFromMasterInput(
        businessId: 'business-1',
        branchId: 'branch-1',
        profileId: 'profile-1',
        appDeviceId: 'device-1',
        deviceInstallationId: 'installation-1',
        masterProduct: {
          'id': 'master-1',
          'product_name': 'Producto Test',
        },
        barcodeRecord: {
          'barcode': '7706191234567',
          'barcode_normalized': '7706191234567',
          'barcode_type': 'ean13',
        },
        salePrice: 2500,
        purchasePrice: 1800,
      );

      expect(input.businessId, equals('business-1'));
      expect(input.branchId, equals('branch-1'));
      expect(input.salePrice, equals(2500));
      expect(input.purchasePrice, equals(1800));
      expect(input.masterProduct['id'], equals('master-1'));
    });
  });
}
