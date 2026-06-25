import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';

void main() {
  group('AppPermissionSet', () {
    test('checks single permission', () {
      final permissions = AppPermissionSet.fromIterable([
        'products.read',
        'products.create',
        'sales.create',
      ]);

      expect(permissions.has('products.read'), isTrue);
      expect(permissions.has('inventory.adjust'), isFalse);
    });

    test('checks any permission', () {
      final permissions = AppPermissionSet.fromIterable([
        'products.read',
      ]);

      expect(
        permissions.hasAny([
          'sales.create',
          'products.read',
        ]),
        isTrue,
      );
    });

    test('checks all permissions', () {
      final permissions = AppPermissionSet.fromIterable([
        'products.read',
        'products.create',
      ]);

      expect(
        permissions.hasAll([
          'products.read',
          'products.create',
        ]),
        isTrue,
      );

      expect(
        permissions.hasAll([
          'products.read',
          'products.delete',
        ]),
        isFalse,
      );
    });

    test('normalizes duplicated and empty permissions', () {
      final permissions = AppPermissionSet.fromIterable([
        'products.read',
        ' products.read ',
        '',
        'sales.create',
      ]);

      expect(
          permissions.sorted(),
          equals([
            'products.read',
            'sales.create',
          ]));
    });
  });

  group('AppCurrentContext', () {
    test('serializes to json', () {
      final context = AppCurrentContext(
        businessId: 'business-1',
        branchId: 'branch-1',
        profileId: 'profile-1',
        installationId: 'installation-1',
        appDeviceId: 'device-1',
        roleId: 'role-1',
        roleName: 'owner',
        permissions: AppPermissionSet.fromIterable([
          'products.read',
          'sales.create',
        ]),
        isOnline: true,
        lastSyncStatus: 'completed',
      );

      final json = context.toJson();

      expect(json['business_id'], equals('business-1'));
      expect(json['branch_id'], equals('branch-1'));
      expect(json['app_device_id'], equals('device-1'));
      expect(json['role_name'], equals('owner'));
      expect(json['permissions'], contains('products.read'));
      expect(json['is_online'], isTrue);
      expect(json['last_sync_status'], equals('completed'));
    });

    test('delegates permission checks', () {
      final context = AppCurrentContext(
        businessId: 'business-1',
        installationId: 'installation-1',
        isOnline: true,
        permissions: AppPermissionSet.fromIterable([
          'products.read',
          'inventory.adjust',
        ]),
      );

      expect(context.hasPermission('products.read'), isTrue);
      expect(context.hasPermission('sales.create'), isFalse);
      expect(
        context.hasAnyPermission([
          'sales.create',
          'inventory.adjust',
        ]),
        isTrue,
      );
    });
  });
}
