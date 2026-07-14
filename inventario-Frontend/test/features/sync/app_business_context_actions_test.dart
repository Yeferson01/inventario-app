import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_business_context_actions.dart';

void main() {
  group('AppBusinessContextActions', () {
    test('provider exists', () {
      expect(appBusinessContextActionsProvider, isNotNull);
    });
  });
}
