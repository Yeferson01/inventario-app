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

  group('CreatedLocalProductResult', () {
    test('serializes to json', () {
      const result = CreatedLocalProductResult(
        productId: 'product-1',
        businessId: 'business-1',
        masterProductId: 'master-1',
        barcode: '7706191234567',
        barcodeNormalized: '7706191234567',
        name: 'Producto Test',
        syncStatus: 'pending_create',
      );

      final json = result.toJson();

      expect(json['product_id'], equals('product-1'));
      expect(json['business_id'], equals('business-1'));
      expect(json['master_product_id'], equals('master-1'));
      expect(json['barcode_normalized'], equals('7706191234567'));
      expect(json['name'], equals('Producto Test'));
      expect(json['sync_status'], equals('pending_create'));
    });
  });

  group('CreateProductFromMasterInput', () {
    test('can be created with required inventory confirmation fields', () {
      const input = CreateProductFromMasterInput(
        businessId: 'business-1',
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
        initialStock: 10,
        minimumStock: 2,
      );

      expect(input.businessId, equals('business-1'));
      expect(input.salePrice, equals(2500));
      expect(input.purchasePrice, equals(1800));
      expect(input.initialStock, equals(10));
      expect(input.minimumStock, equals(2));
      expect(input.masterProduct['id'], equals('master-1'));
    });
  });
}
