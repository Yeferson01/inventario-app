import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_business_selection_provider.dart';

void main() {
  group('Business selection providers', () {
    test('appAvailableBusinessContextsProvider exists', () {
      expect(appAvailableBusinessContextsProvider, isNotNull);
    });

    test('appSelectedBusinessOptionProvider exists', () {
      expect(appSelectedBusinessOptionProvider, isNotNull);
    });
  });
}
