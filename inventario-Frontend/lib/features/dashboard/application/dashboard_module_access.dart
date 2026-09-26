import '../../sync/application/app_context_models.dart';

class DashboardModuleAccess {
  const DashboardModuleAccess({
    required this.hasEffectiveAuthorization,
    required this.canCreateSales,
    required this.canReadCash,
    required this.canOpenCash,
    required this.canCloseCash,
    this.canReceiveCash = false,
    this.canDisburseCash = false,
    required this.canReadInventory,
    required this.canPurchaseInventory,
    required this.canAdjustInventory,
    required this.canViewSalesReports,
    required this.canManageBranches,
    required this.canInviteMembers,
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
      canReceiveCash: context.hasPermission('cash.receive'),
      canDisburseCash: context.hasPermission('cash.disburse'),
      canReadInventory: context.hasPermission('inventory.read'),
      canPurchaseInventory: context.hasPermission('inventory.purchase'),
      canAdjustInventory: context.hasPermission('inventory.adjust'),
      canViewSalesReports: context.hasPermission('reports.sales'),
      canManageBranches: context.hasPermission('settings.branches'),
      canInviteMembers: context.hasPermission('members.invite'),
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
        canReceiveCash = false,
        canDisburseCash = false,
        canReadInventory = false,
        canPurchaseInventory = false,
        canAdjustInventory = false,
        canViewSalesReports = false,
        canManageBranches = false,
        canInviteMembers = false,
        canManageSettings = false;

  final bool hasEffectiveAuthorization;
  final bool canCreateSales;
  final bool canReadCash;
  final bool canOpenCash;
  final bool canCloseCash;
  final bool canReceiveCash;
  final bool canDisburseCash;
  final bool canReadInventory;
  final bool canPurchaseInventory;
  final bool canAdjustInventory;
  final bool canViewSalesReports;
  final bool canManageBranches;
  final bool canInviteMembers;
  final bool canManageSettings;

  bool get canOpenAdministration => canManageBranches || canInviteMembers;

  bool get canUseCash =>
      canReadCash ||
      canOpenCash ||
      canCloseCash ||
      canReceiveCash ||
      canDisburseCash;
}
