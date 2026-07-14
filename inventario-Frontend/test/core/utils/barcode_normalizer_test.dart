import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/utils/barcode_normalizer.dart';

void main() {
  group('BarcodeNormalizer', () {
    test('normalizes barcode like backend', () {
      expect(
        BarcodeNormalizer.normalize(' 770 619-1234567 '),
        equals('7706191234567'),
      );

      expect(
        BarcodeNormalizer.normalize(' local - abc 001 '),
        equals('LOCALABC001'),
      );
    });

    test('detects known barcode types', () {
      expect(
          BarcodeNormalizer.inferBarcodeType('7706191234567'), equals('ean13'));
      expect(BarcodeNormalizer.inferBarcodeType('12345678'), equals('ean8'));
      expect(BarcodeNormalizer.inferBarcodeType('123456789012'), equals('upc'));
      expect(
          BarcodeNormalizer.inferBarcodeType('12345678901234'), equals('gtin'));
      expect(
          BarcodeNormalizer.inferBarcodeType('SKU-001'), equals('local_sku'));
    });
  });
}
