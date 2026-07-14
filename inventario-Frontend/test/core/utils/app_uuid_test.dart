import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/utils/app_uuid.dart';

void main() {
  group('AppUuid', () {
    test('generates UUIDv7-looking id', () {
      final id = AppUuid.v7();

      expect(AppUuid.looksLikeUuid(id), isTrue);
    });

    test('generates UUIDv4-looking id', () {
      final id = AppUuid.v4();

      expect(AppUuid.looksLikeUuid(id), isTrue);
    });
  });
}
