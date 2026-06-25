import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/catalog/application/catalog_barcode_lookup_service.dart';
import 'package:inventario_frontend/features/catalog/data/models/catalog_local_models.dart';
import 'package:inventario_frontend/features/catalog/domain/entities/barcode_scan_result.dart';

void main() {
  group('CatalogBarcodeLookupService', () {
    test('rejects invalid barcode without querying local catalog', () async {
      var wasCalled = false;

      final service = CatalogBarcodeLookupService(
        lookupByBarcode: ({
          required String businessId,
          required String barcode,
        }) async {
          wasCalled = true;
          return LocalBarcodeLookupResult.none(barcode);
        },
      );

      final result = await service.scanBarcode(
        businessId: 'business-1',
        rawBarcode: ' --- ',
      );

      expect(wasCalled, isFalse);
      expect(result.isInvalid, isTrue);
      expect(result.found, isFalse);
      expect(result.suggestedAction,
          BarcodeScanSuggestedAction.rejectInvalidBarcode);
    });

    test('returns business match when local product exists', () async {
      final service = CatalogBarcodeLookupService(
        lookupByBarcode: ({
          required String businessId,
          required String barcode,
        }) async {
          return LocalBarcodeLookupResult(
            found: true,
            matchType: 'business',
            suggestedAction: 'use_local_product',
            normalizedBarcode: barcode,
            barcodeRecord: {
              'id': 'barcode-1',
              'barcode_normalized': barcode,
            },
            localProduct: {
              'id': 'product-1',
              'name': 'Producto Local',
            },
          );
        },
      );

      final result = await service.scanBarcode(
        businessId: 'business-1',
        rawBarcode: ' 770 619-1234567 ',
      );

      expect(result.found, isTrue);
      expect(result.matchType, BarcodeScanMatchType.business);
      expect(
          result.suggestedAction, BarcodeScanSuggestedAction.useLocalProduct);
      expect(result.canUseImmediately, isTrue);
      expect(result.normalizedBarcode, equals('7706191234567'));
      expect(result.localProduct?['id'], equals('product-1'));
    });

    test('returns global match when master product exists', () async {
      final service = CatalogBarcodeLookupService(
        lookupByBarcode: ({
          required String businessId,
          required String barcode,
        }) async {
          return LocalBarcodeLookupResult(
            found: true,
            matchType: 'global',
            suggestedAction: 'create_local_product_from_master',
            normalizedBarcode: barcode,
            barcodeRecord: {
              'id': 'barcode-1',
              'barcode_normalized': barcode,
            },
            masterProduct: {
              'id': 'master-1',
              'name': 'Producto Maestro',
            },
          );
        },
      );

      final result = await service.scanBarcode(
        businessId: 'business-1',
        rawBarcode: '7706191234567',
      );

      expect(result.found, isTrue);
      expect(result.matchType, BarcodeScanMatchType.global);
      expect(
        result.suggestedAction,
        BarcodeScanSuggestedAction.createLocalProductFromMaster,
      );
      expect(result.canCreateFromMaster, isTrue);
      expect(result.masterProduct?['id'], equals('master-1'));
    });

    test('returns manual creation action when nothing is found', () async {
      final service = CatalogBarcodeLookupService(
        lookupByBarcode: ({
          required String businessId,
          required String barcode,
        }) async {
          return LocalBarcodeLookupResult.none(barcode);
        },
      );

      final result = await service.scanBarcode(
        businessId: 'business-1',
        rawBarcode: 'SKU-001',
      );

      expect(result.found, isFalse);
      expect(result.matchType, BarcodeScanMatchType.none);
      expect(result.suggestedAction,
          BarcodeScanSuggestedAction.createManualProduct);
      expect(result.requiresManualCreation, isTrue);
      expect(result.normalizedBarcode, equals('SKU001'));
    });
  });
}
