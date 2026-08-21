import '../../sync/application/app_context_models.dart';

class DashboardModuleAccess {
  const DashboardModuleAccess({
    required this.hasEffectiveAuthorization,
    required this.canCreateSales,
    required this.canReadCash,
    required this.canOpenCash,
    required this.canCloseCash,
    required this.canReadInventory,
    required this.canPurchaseInventory,
    required this.canAdjustInventory,
    required this.canManageSettings,
  });

  factory DashboardModuleAccess.fromContext(AppCurrentContext? context) {
    if (context == null || !context.authorizationContextReady) {
      return const DashboardModuleAccess.denied();
    }

    return DashboardModuleAccess(
      hasEffectiveAuthorization: true,
      canCreateSales: context.hasPermission('sales.create'),
      canReadCash: context.hasPermission('cash.read'),
      canOpenCash: context.hasPermission('cash.open'),
      canCloseCash: context.hasPermission('cash.close'),
      canReadInventory: context.hasPermission('inventory.read'),
      canPurchaseInventory: context.hasPermission('inventory.purchase'),
      canAdjustInventory: context.hasPermission('inventory.adjust'),
      canManageSettings: context.hasAnyPermission(const [
        'settings.business',
        'settings.branches',
        'settings.taxes',
        'settings.billing',
      ]),
    );
  }

  const DashboardModuleAccess.denied()
      : hasEffectiveAuthorization = false,
        canCreateSales = false,
        canReadCash = false,
        canOpenCash = false,
        canCloseCash = false,
        canReadInventory = false,
        canPurchaseInventory = false,
        canAdjustInventory = false,
        canManageSettings = false;

  final bool hasEffectiveAuthorization;
  final bool canCreateSales;
  final bool canReadCash;
  final bool canOpenCash;
  final bool canCloseCash;
  final bool canReadInventory;
  final bool canPurchaseInventory;
  final bool canAdjustInventory;
  final bool canManageSettings;

  bool get canUseCash => canReadCash || canOpenCash || canCloseCash;
}
