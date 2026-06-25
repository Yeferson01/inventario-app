import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_creation_service.dart';

void main() {
  group('InventoryProductCreationService draft builder', () {
    test('builds draft from master product and barcode record', () {
      final service = InventoryProductCreationService(FakeAppDatabaseForDraftOnly());

      final draft = service.buildDraftFromMaster(
        businessId: 'business-1',
        masterProduct: {
          'id': 'master-1',
          'product_name': 'Leche Entera 1L',
          'brand': 'Marca Test',
          'category_name': 'Lácteos',
          'package_size': 1,
          'package_unit': 'L',
          'unit_type': 'unidad',
          'confidence_score': 0.91,
        },
        barcodeRecord: {
          'barcode': '7706191234567',
          'barcode_normalized': '7706191234567',
          'barcode_type': 'ean13',
        },
      );

      expect(draft.businessId, equals('business-1'));
      expect(draft.masterProductId, equals('master-1'));
      expect(draft.name, equals('Leche Entera 1L'));
      expect(draft.barcodeNormalized, equals('7706191234567'));
      expect(draft.barcodeType, equals('ean13'));
      expect(draft.brand, equals('Marca Test'));
      expect(draft.categoryName, equals('Lácteos'));
      expect(draft.confidenceScore, equals(0.91));
    });

    test('falls back to normalized barcode when barcode_normalized is absent', () {
      final service = InventoryProductCreationService(FakeAppDatabaseForDraftOnly());

      final draft = service.buildDraftFromMaster(
        businessId: 'business-1',
        masterProduct: {
          'id': 'master-1',
          'name': 'Producto Test',
        },
        barcodeRecord: {
          'barcode': ' 770 619-1234567 ',
        },
      );

      expect(draft.name, equals('Producto Test'));
      expect(draft.barcodeNormalized, equals('7706191234567'));
    });
  });
}

class FakeAppDatabaseForDraftOnly implements dynamic {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
