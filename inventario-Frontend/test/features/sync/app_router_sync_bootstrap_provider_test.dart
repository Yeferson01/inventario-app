import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_router_sync_bootstrap_provider.dart';

void main() {
  group('AppRouterSyncBootstrapData', () {
    test('canRunShellSync is false without input', () {
      const data = AppRouterSyncBootstrapData(
        hasAuthenticatedUser: true,
      );

      expect(data.canRunShellSync, isFalse);
    });
  });
}
