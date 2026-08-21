import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/dashboard/application/dashboard_module_access.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';

void main() {
  test('multi-role permission union enables cash, POS and inventory together',
      () {
    final access = DashboardModuleAccess.fromContext(
      _context(
        roles: const ['cashier', 'warehouse'],
        permissions: const [
          'sales.create',
          'cash.read',
          'cash.open',
          'cash.close',
          'inventory.read',
          'inventory.purchase',
          'inventory.adjust',
        ],
        cashSessionId: 'cash-session-open',
      ),
    );

    expect(access.canCreateSales, isTrue);
    expect(access.canUseCash, isTrue);
    expect(access.canReadInventory, isTrue);
    expect(access.canPurchaseInventory, isTrue);
    expect(access.canAdjustInventory, isTrue);
  });

  test('cashier role name grants nothing without effective permissions', () {
    final access = DashboardModuleAccess.fromContext(
      _context(roles: const ['cashier'], permissions: const []),
    );

    expect(access.canCreateSales, isFalse);
    expect(access.canUseCash, isFalse);
  });

  test('custom role receives modules exclusively from its capabilities', () {
    final access = DashboardModuleAccess.fromContext(
      _context(
        roles: const ['morning_operator'],
        permissions: const ['sales.create', 'inventory.read'],
      ),
    );

    expect(access.canCreateSales, isTrue);
    expect(access.canReadInventory, isTrue);
    expect(access.canUseCash, isFalse);
    expect(access.canPurchaseInventory, isFalse);
  });

  test('open cash session does not hide authorized inventory', () {
    final access = DashboardModuleAccess.fromContext(
      _context(
        permissions: const [
          'cash.open',
          'sales.create',
          'inventory.read',
          'inventory.adjust',
        ],
        cashSessionId: 'cash-session-open',
      ),
    );

    expect(access.canReadInventory, isTrue);
    expect(access.canAdjustInventory, isTrue);
  });

  test('inventory.read does not authorize adjustments', () {
    final access = DashboardModuleAccess.fromContext(
      _context(permissions: const ['inventory.read']),
    );

    expect(access.canReadInventory, isTrue);
    expect(access.canAdjustInventory, isFalse);
    expect(access.canPurchaseInventory, isFalse);
  });

  test('legacy permissions without active projection grant no module', () {
    final access = DashboardModuleAccess.fromContext(
      _context(
        permissions: const ['sales.create', 'inventory.read'],
        authorizationReady: false,
      ),
    );

    expect(access.hasEffectiveAuthorization, isFalse);
    expect(access.canCreateSales, isFalse);
    expect(access.canReadInventory, isFalse);
  });
}

AppCurrentContext _context({
  List<String> roles = const [],
  List<String> permissions = const [],
  String? cashSessionId,
  bool authorizationReady = true,
}) {
  return AppCurrentContext(
    businessId: 'business-1',
    branchId: 'branch-1',
    profileId: 'profile-1',
    installationId: 'installation-1',
    isOnline: true,
    effectiveRoles: roles,
    roleName: roles.join(', '),
    cashSessionId: cashSessionId,
    authorizationContextReady: authorizationReady,
    permissions: AppPermissionSet.fromIterable(permissions),
  );
}
