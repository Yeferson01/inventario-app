import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_current_context_provider.dart';

void main() {
  group('AppCurrentContextRequest', () {
    test('serializes to json', () {
      const request = AppCurrentContextRequest(
        installationId: 'installation-1',
        isOnline: true,
        lastSyncStatus: 'completed',
      );

      final json = request.toJson();

      expect(json['installation_id'], equals('installation-1'));
      expect(json['is_online'], isTrue);
      expect(json['last_sync_status'], equals('completed'));
    });

    test('supports equality for provider family cache', () {
      const left = AppCurrentContextRequest(
        installationId: 'installation-1',
        isOnline: true,
        lastSyncStatus: 'completed',
      );

      const right = AppCurrentContextRequest(
        installationId: 'installation-1',
        isOnline: true,
        lastSyncStatus: 'completed',
      );

      expect(left, equals(right));
      expect(left.hashCode, equals(right.hashCode));
    });
  });

  group('Permission check requests', () {
    test('single permission request supports equality', () {
      const contextRequest = AppCurrentContextRequest(
        installationId: 'installation-1',
        isOnline: true,
      );

      const left = AppPermissionCheckRequest(
        contextRequest: contextRequest,
        permission: 'products.create',
      );

      const right = AppPermissionCheckRequest(
        contextRequest: contextRequest,
        permission: 'products.create',
      );

      expect(left, equals(right));
      expect(left.hashCode, equals(right.hashCode));
    });

    test('any permission request supports equality', () {
      const contextRequest = AppCurrentContextRequest(
        installationId: 'installation-1',
        isOnline: true,
      );

      const left = AppAnyPermissionCheckRequest(
        contextRequest: contextRequest,
        permissions: [
          'products.create',
          'products.update',
        ],
      );

      const right = AppAnyPermissionCheckRequest(
        contextRequest: contextRequest,
        permissions: [
          'products.create',
          'products.update',
        ],
      );

      expect(left, equals(right));
      expect(left.hashCode, equals(right.hashCode));
    });

    test('all permissions request supports equality', () {
      const contextRequest = AppCurrentContextRequest(
        installationId: 'installation-1',
        isOnline: true,
      );

      const left = AppAllPermissionsCheckRequest(
        contextRequest: contextRequest,
        permissions: [
          'sales.create',
          'sale_payments.create',
        ],
      );

      const right = AppAllPermissionsCheckRequest(
        contextRequest: contextRequest,
        permissions: [
          'sales.create',
          'sale_payments.create',
        ],
      );

      expect(left, equals(right));
      expect(left.hashCode, equals(right.hashCode));
    });
  });
}
