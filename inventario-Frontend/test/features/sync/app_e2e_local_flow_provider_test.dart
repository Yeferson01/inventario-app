import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_e2e_local_flow_provider.dart';

void main() {
  group('E2E local flow providers', () {
    test('service provider exists', () {
      expect(appE2ELocalFlowServiceProvider, isNotNull);
    });

    test('result provider exists', () {
      expect(appE2ELocalFlowResultProvider, isNotNull);
    });
  });
}
