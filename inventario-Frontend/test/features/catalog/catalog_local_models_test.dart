import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/catalog/data/models/catalog_local_models.dart';

void main() {
  group('LocalBarcodeLookupResult', () {
    test('creates none result', () {
      final result = LocalBarcodeLookupResult.none('ABC123');

      expect(result.found, isFalse);
      expect(result.matchType, equals('none'));
      expect(result.suggestedAction, equals('create_manual_product'));
      expect(result.normalizedBarcode, equals('ABC123'));
    });

    test('serializes result to json', () {
      const result = LocalBarcodeLookupResult(
        found: true,
        matchType: 'global',
        suggestedAction: 'create_local_product_from_master',
        normalizedBarcode: '7706191234567',
        barcodeRecord: {'id': 'barcode-id'},
        masterProduct: {'id': 'master-id'},
      );

      final json = result.toJson();

      expect(json['found'], isTrue);
      expect(json['match_type'], equals('global'));
      expect(json['barcode_record'], isA<Map<String, dynamic>>());
      expect(json['master_product'], isA<Map<String, dynamic>>());
    });
  });

  group('CatalogDeltaApplyResult', () {
    test('computes total applied', () {
      const result = CatalogDeltaApplyResult(
        masterProductsUpserted: 2,
        productBarcodesUpserted: 3,
        ignoredRecords: 1,
      );

      expect(result.totalApplied, equals(5));
      expect(result.toJson()['total_applied'], equals(5));
    });
  });
}
