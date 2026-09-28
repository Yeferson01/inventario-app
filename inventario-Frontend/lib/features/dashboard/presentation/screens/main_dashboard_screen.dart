import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes_constants.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/providers/device_provider.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../../cash/application/cash_session_local_provider.dart';
import '../../../cash/presentation/screens/cash_dashboard_screen.dart';
import '../../../auth/application/authenticated_access_providers.dart';
import '../../../auth/application/productive_auth_providers.dart';
import '../../application/dashboard_module_access.dart';
import '../../../inventory/application/product_stock_balance_providers.dart';
import '../../../inventory/presentation/screens/inventory_product_stock_list_screen.dart';
import '../../../inventory/presentation/screens/inventory_movements_screen.dart';
import '../../../inventory/presentation/screens/purchase_entry_screen.dart';
import '../../../reports/presentation/screens/sales_report_screen.dart';
import '../../../reports/presentation/screens/cash_flow_report_screen.dart';
import '../../../sync/application/app_context_models.dart';
import '../../../sync/application/app_current_context_provider.dart';
import '../../../sync/application/app_router_sync_bootstrap_provider.dart';
import '../../../sync/application/operational_bootstrap_entry_providers.dart';
import '../../../sync/application/productive_sync_status.dart';
import '../../../sync/application/productive_sync_status_provider.dart';
import '../../../sync/data/models/authorized_operational_context_models.dart';
import '../../../sync/presentation/productive_error_presentation.dart';
import '../../../sync/presentation/widgets/operational_branch_switcher.dart';
import '../../../sales/presentation/sales_presentation.dart';

class MainDashboardScreen extends ConsumerStatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  ConsumerState<MainDashboardScreen> createState() =>
      _MainDashboardScreenState();
}

class _MainDashboardScreenState extends ConsumerState<MainDashboardScreen> {
  bool _isLoading = true;
  bool _isSwitchingBranch = false;
  bool _isManualSyncing = false;
  Object? _lastError;

  AppCurrentContext? _appContext;
  Map<String, dynamic>? _cashSummary;
  Map<String, dynamic>? _cashReadiness;

  @override
  void initState() {
    super.initState();

    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _lastError = null;
    });

    try {
      final installationId = await ref.read(installationIdProvider.future);

      final contextRequest = AppCurrentContextRequest(
        installationId: installationId,
        isOnline: true,
      );

      final appContext = await ref.read(
        appCurrentContextProvider(contextRequest).future,
      );

      Map<String, dynamic>? cashSummary;
      Map<String, dynamic>? cashReadiness;

      final businessId = appContext?.businessId;
      final branchId = appContext?.branchId;

      if (businessId != null && branchId != null) {
        final service = ref.read(cashSessionLocalServiceProvider);

        try {
          cashSummary = await service.getLatestCashSessionSummaryForBranch(
            businessId: businessId,
            branchId: branchId,
          );
        } catch (_) {
          cashSummary = null;
        }

        cashReadiness = await service.getPosCashReadinessSummary(
          businessId: businessId,
          branchId: branchId,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _appContext = appContext;
        _cashSummary = cashSummary;
        _cashReadiness = cashReadiness;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _lastError = error;
        _isLoading = false;
      });
    }
  }

  Future<void> _openCashDashboard() async {
    final appContext = _appContext;
    final access = DashboardModuleAccess.fromContext(appContext);

    if (appContext == null || !access.canUseCash) {
      _showInfoSheet(
        title: appContext == null ? 'Selecciona una sucursal' : 'Sin acceso',
        message: appContext == null
            ? 'Selecciona un negocio y una sucursal antes de abrir el módulo de caja.'
            : 'No tienes permiso para usar Caja. Pídele acceso al administrador.',
      );
      return;
    }

    final branchId = appContext.branchId;
    final profileId = appContext.profileId;
    final cashRegisterId = appContext.cashRegisterId?.trim();

    if (branchId == null ||
        profileId == null ||
        cashRegisterId == null ||
        cashRegisterId.isEmpty) {
      final copy = ProductiveErrorPresentation.forCategory(
        ProductiveErrorCategory.contextNotReady,
      );
      _showInfoSheet(
        title: copy.title,
        message:
            '${copy.message} Actualiza la información antes de abrir caja.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CashDashboardScreen(
          businessId: appContext.businessId,
          branchId: branchId,
          profileId: profileId,
          cashRegisterId: cashRegisterId,
          appDeviceId: appContext.appDeviceId,
          deviceInstallationId: appContext.installationId,
          canReadCash: access.canReadCash,
          canOpenCash: access.canOpenCash,
          canCloseCash: access.canCloseCash,
          effectivePermissions: appContext.permissions.values,
        ),
      ),
    );

    await _load();
  }

  Future<void> _openPurchases() async {
    final appContext = _appContext;
    final access = DashboardModuleAccess.fromContext(appContext);

    if (appContext == null || !access.canPurchaseInventory) {
      _showInfoSheet(
        title: appContext == null ? 'Selecciona una sucursal' : 'Sin acceso',
        message: appContext == null
            ? 'Selecciona un negocio y una sucursal antes de abrir compras.'
            : 'No tienes permiso para registrar compras. Pídele acceso al administrador.',
      );
      return;
    }

    final branchId = appContext.branchId;
    final profileId = appContext.profileId;

    if (branchId == null || profileId == null) {
      _showInfoSheet(
        title: 'No pudimos abrir Compras',
        message: 'Selecciona un negocio y una sucursal e inténtalo nuevamente.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PurchaseEntryScreen(
          businessId: appContext.businessId,
          branchId: branchId,
          profileId: profileId,
          appDeviceId: appContext.appDeviceId,
          deviceInstallationId: appContext.installationId,
          effectivePermissions: appContext.permissions.values,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _load();
  }

  Future<void> _openInventory({
    String? branchName,
    InventoryProductStockFilter initialStockFilter =
        InventoryProductStockFilter.all,
  }) async {
    final appContext = _appContext;
    final access = DashboardModuleAccess.fromContext(appContext);

    if (appContext == null || !access.canReadInventory) {
      _showInfoSheet(
        title: appContext == null ? 'Selecciona una sucursal' : 'Sin acceso',
        message: appContext == null
            ? 'Selecciona un negocio y una sucursal antes de abrir inventario.'
            : 'No tienes permiso para consultar Inventario. Pídele acceso al administrador.',
      );
      return;
    }

    final businessId = appContext.businessId.trim();
    final branchId = appContext.branchId?.trim();
    final profileId = appContext.profileId?.trim();

    if (businessId.isEmpty ||
        branchId == null ||
        branchId.isEmpty ||
        profileId == null ||
        profileId.isEmpty) {
      _showInfoSheet(
        title: 'No pudimos abrir Inventario',
        message: 'Selecciona un negocio y una sucursal e inténtalo nuevamente.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryProductStockListScreen(
          businessId: businessId,
          branchId: branchId,
          branchName: branchName ?? 'Sucursal',
          profileId: profileId,
          appDeviceId: appContext.appDeviceId,
          deviceInstallationId: appContext.installationId,
          effectivePermissions: appContext.permissions.values,
          initialStockFilter: initialStockFilter,
          onOpenProductMovements: ({
            required productId,
            required productName,
            productBarcode,
          }) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => InventoryMovementsScreen(
                  appContext: appContext,
                  branchName: branchName ?? 'Sucursal',
                  productId: productId,
                  productName: productName,
                  productBarcode: productBarcode,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _openMovements({
    String? branchName,
  }) async {
    final appContext = _appContext;
    final access = DashboardModuleAccess.fromContext(appContext);

    if (appContext == null || !access.canReadInventory) {
      _showInfoSheet(
        title: appContext == null ? 'Selecciona una sucursal' : 'Sin acceso',
        message: appContext == null
            ? 'Selecciona un negocio y una sucursal antes de abrir movimientos.'
            : 'No tienes permiso para consultar Movimientos. Pídele acceso al administrador.',
      );
      return;
    }

    final businessId = appContext.businessId.trim();
    final branchId = appContext.branchId?.trim();
    final profileId = appContext.profileId?.trim();

    if (businessId.isEmpty ||
        branchId == null ||
        branchId.isEmpty ||
        profileId == null ||
        profileId.isEmpty ||
        !appContext.authorizationContextReady) {
      _showInfoSheet(
        title: 'No pudimos abrir Movimientos',
        message: 'Selecciona un negocio y una sucursal e inténtalo nuevamente.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryMovementsScreen(
          appContext: appContext,
          branchName: branchName ?? 'Sucursal',
        ),
      ),
    );
  }

  Future<void> _openSalesReports({String? branchName}) async {
    final appContext = _appContext;
    final access = DashboardModuleAccess.fromContext(appContext);

    if (appContext == null ||
        (!access.canViewSalesReports && !access.canViewCashReports)) {
      _showInfoSheet(
        title: appContext == null ? 'Selecciona una sucursal' : 'Sin acceso',
        message: appContext == null
            ? 'Selecciona un negocio y una sucursal antes de abrir reportes.'
            : 'No tienes permiso para consultar reportes.',
      );
      return;
    }

    final businessId = appContext.businessId.trim();
    final branchId = appContext.branchId?.trim();
    final profileId = appContext.profileId?.trim();
    if (businessId.isEmpty ||
        branchId == null ||
        branchId.isEmpty ||
        profileId == null ||
        profileId.isEmpty ||
        !appContext.authorizationContextReady) {
      _showInfoSheet(
        title: 'No pudimos abrir Reportes',
        message: 'Selecciona un negocio y una sucursal e inténtalo nuevamente.',
      );
      return;
    }

    Future<void> openCashFlow() => Navigator.of(context).push(
          MaterialPageRoute<void>(
              builder: (_) => CashFlowReportScreen(
                    profileId: profileId,
                    businessId: businessId,
                    branchId: branchId,
                    branchName: branchName ?? 'Sucursal',
                    effectivePermissions: appContext.permissions.values,
                    authorizationContextReady:
                        appContext.authorizationContextReady,
                    authorizationValidatedAt:
                        appContext.authorizationValidatedAt,
                  )),
        );
    if (!access.canViewSalesReports) {
      await openCashFlow();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SalesReportScreen(
          profileId: profileId,
          businessId: businessId,
          branchId: branchId,
          branchName: branchName ?? 'Sucursal',
          effectivePermissions: appContext.permissions.values,
          authorizationContextReady: appContext.authorizationContextReady,
          authorizationValidatedAt: appContext.authorizationValidatedAt,
          onOpenCashFlow: access.canViewCashReports ? openCashFlow : null,
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(productiveSignOutProvider)();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _lastError = 'No fue posible cerrar la sesión.';
        _isLoading = false;
      });
    }
  }

  Future<void> _runManualSync() async {
    if (_isManualSyncing) {
      return;
    }

    setState(() => _isManualSyncing = true);

    final result = await ref.read(productiveManualSyncRunnerProvider)();

    if (!mounted) {
      return;
    }

    setState(() => _isManualSyncing = false);
    ref.invalidate(productiveSyncStatusProvider);

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(result.message)));
  }

  void _switchOperationalBranch(AuthorizedOperationalContext target) {
    if (_isSwitchingBranch) {
      return;
    }

    final current = _appContext;
    final profileId = current?.profileId;
    if (current == null || profileId == null) {
      _showInfoSheet(
        title: 'No pudimos cambiar de sucursal',
        message: 'Vuelve al inicio y selecciona tu negocio nuevamente.',
      );
      return;
    }

    setState(() => _isSwitchingBranch = true);
    final accepted = ref
        .read(productiveOperationalSelectionIntentProvider.notifier)
        .requestSwitch(
          currentProfileId: profileId,
          currentBusinessId: current.businessId,
          target: target,
        );

    if (!accepted && mounted) {
      setState(() => _isSwitchingBranch = false);
      _showInfoSheet(
        title: 'Sucursal no autorizada',
        message:
            'No tienes acceso a esa sucursal. Elige otra o pide acceso al administrador.',
      );
    }
  }

  void _openPosGate() {
    final appContext = _appContext;
    final access = DashboardModuleAccess.fromContext(appContext);

    if (appContext == null || !access.canCreateSales) {
      _showInfoSheet(
        title: appContext == null ? 'Selecciona una sucursal' : 'Sin acceso',
        message: appContext == null
            ? 'Selecciona un negocio y una sucursal antes de iniciar una venta.'
            : 'No tienes permiso para crear ventas en esta sucursal.',
      );
      return;
    }

    final branchId = appContext.branchId;
    final profileId = appContext.profileId;

    if (branchId == null || profileId == null) {
      _showInfoSheet(
        title: 'No pudimos iniciar la venta',
        message: 'Selecciona un negocio y una sucursal e inténtalo nuevamente.',
      );
      return;
    }

    final cashStatus = _string(_cashSummary?['status']);
    final activeCashSessionId =
        cashStatus == 'open' ? _string(_cashSummary?['cash_session_id']) : null;
    final activeCashRegisterId = cashStatus == 'open'
        ? _string(_cashSummary?['cash_register_id'])
        : null;

    if (activeCashSessionId == null || activeCashRegisterId == null) {
      _showInfoSheet(
        title: 'Abre la caja para vender',
        message: 'Necesitas una caja abierta antes de registrar ventas.',
        primaryLabel: 'Ir a Caja',
        onPrimary: () {
          Navigator.of(context).pop();
          _openCashDashboard();
        },
      );
      return;
    }

    final blockedReason = _cashReadiness?['pos_upload_blocked_reason'];

    if (blockedReason != null) {
      _showInfoSheet(
        title: 'Venta no disponible',
        message:
            'Antes de vender, revisa que la caja esté abierta y que no tenga operaciones pendientes.',
        primaryLabel: 'Ir a Caja',
        onPrimary: () {
          Navigator.of(context).pop();
          _openCashDashboard();
        },
      );
      return;
    }

    Navigator.of(context)
        .push(
      MaterialPageRoute<void>(
        builder: (_) => PosSaleScreen(
          businessId: appContext.businessId,
          branchId: branchId,
          profileId: profileId,
          appDeviceId: appContext.appDeviceId,
          deviceInstallationId: appContext.installationId,
          cashRegisterId: activeCashRegisterId,
          cashSessionId: activeCashSessionId,
          cashRegisterName: _string(_cashSummary?['cash_register_name']),
        ),
      ),
    )
        .then((_) {
      if (mounted) {
        _load();
      }
    });
  }

  void _showInfoSheet({
    required String title,
    required String message,
    String primaryLabel = 'Entendido',
    VoidCallback? onPrimary,
  }) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(CronosSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: CronosSpacing.sm),
              Text(message),
              const SizedBox(height: CronosSpacing.lg),
              FilledButton(
                onPressed: onPrimary ?? () => Navigator.of(context).pop(),
                child: Text(primaryLabel),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final moduleAccess = DashboardModuleAccess.fromContext(_appContext);
    final profileId = _appContext?.profileId;
    final businessId = _appContext?.businessId;
    final branchId = _appContext?.branchId;
    final authorizedContexts = profileId == null
        ? const <AuthorizedOperationalContext>[]
        : ref
                .watch(authenticatedAccessResolverProvider(profileId))
                .value
                ?.contexts ??
            const <AuthorizedOperationalContext>[];
    final branchContexts = profileId == null || businessId == null
        ? const <AuthorizedOperationalContext>[]
        : scopedOperationalBranchContexts(
            contexts: authorizedContexts,
            profileId: profileId,
            businessId: businessId,
          );
    final operationalContext = _findOperationalContext(
      branchContexts,
      branchId,
    );
    AsyncValue<InventoryAlertSummary>? inventoryAlerts;
    AsyncValue<ProductiveSyncStatus>? productiveSyncStatus;
    if (moduleAccess.canReadInventory &&
        businessId?.trim().isNotEmpty == true &&
        branchId?.trim().isNotEmpty == true) {
      inventoryAlerts = ref.watch(
        inventoryAlertSummaryProvider(
          InventoryAlertSummaryKey(
            businessId: businessId!.trim(),
            branchId: branchId!.trim(),
          ),
        ),
      );
    }
    if (profileId?.trim().isNotEmpty == true &&
        businessId?.trim().isNotEmpty == true &&
        branchId?.trim().isNotEmpty == true) {
      productiveSyncStatus = ref.watch(
        productiveSyncStatusProvider(
          ProductiveSyncStatusRequest(
            profileId: profileId!.trim(),
            businessId: businessId!.trim(),
            branchId: branchId!.trim(),
            isSyncing: _isManualSyncing,
          ),
        ),
      );
    }

    return Theme(
      data: CronosTheme.light(),
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Cronos POS'),
              actions: [
                IconButton(
                  onPressed: _isLoading ? null : _load,
                  icon: const Icon(Icons.refresh_outlined),
                  tooltip: 'Actualizar',
                ),
                if (moduleAccess.canOpenAdministration)
                  IconButton(
                    onPressed: () => context.push(AppRoutes.administrationPath),
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Administración',
                  ),
                IconButton(
                  onPressed: _isLoading ? null : _signOut,
                  icon: const Icon(Icons.logout_outlined),
                  tooltip: 'Cerrar sesión',
                ),
              ],
            ),
            body: AppGradientBackground(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(CronosSpacing.md),
                  children: [
                    AppAnimatedEntrance(
                      child: _DashboardHeader(
                        appContext: _appContext,
                        operationalContext: operationalContext,
                        branchContexts: branchContexts,
                        isSwitchingBranch: _isSwitchingBranch,
                        onSwitchBranch: _switchOperationalBranch,
                        isLoading: _isLoading,
                        lastError: _lastError,
                      ),
                    ),
                    if (inventoryAlerts != null) ...[
                      const SizedBox(height: CronosSpacing.lg),
                      AppAnimatedEntrance(
                        delay: const Duration(milliseconds: 160),
                        child: _InventoryAlertsCard(
                          summary: inventoryAlerts,
                          onOpenOutOfStock: () => _openInventory(
                            branchName: operationalContext?.branchName,
                            initialStockFilter:
                                InventoryProductStockFilter.outOfStock,
                          ),
                          onOpenLowStock: () => _openInventory(
                            branchName: operationalContext?.branchName,
                            initialStockFilter:
                                InventoryProductStockFilter.lowStock,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: CronosSpacing.lg),
                    AppAnimatedEntrance(
                      delay: const Duration(milliseconds: 80),
                      child: _QuickStatusRow(
                        appContext: _appContext,
                        moduleAccess: moduleAccess,
                        cashSummary: _cashSummary,
                        cashReadiness: _cashReadiness,
                      ),
                    ),
                    const SizedBox(height: CronosSpacing.lg),
                    Text(
                      'Módulos principales',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: CronosSpacing.sm),
                    AppAnimatedEntrance(
                      delay: const Duration(milliseconds: 120),
                      child: _ModulesGrid(
                        moduleAccess: moduleAccess,
                        cashSummary: _cashSummary,
                        cashReadiness: _cashReadiness,
                        onOpenCash: _openCashDashboard,
                        onOpenPos: _openPosGate,
                        onOpenInventory: () => _openInventory(
                          branchName: operationalContext?.branchName,
                        ),
                        onOpenMovements: () => _openMovements(
                          branchName: operationalContext?.branchName,
                        ),
                        onOpenPurchases: _openPurchases,
                        onOpenSalesReports: () => _openSalesReports(
                          branchName: operationalContext?.branchName,
                        ),
                        isManualSyncing: _isManualSyncing,
                        productiveSyncStatus: productiveSyncStatus,
                        onManualSync: _runManualSync,
                      ),
                    ),
                    const SizedBox(height: CronosSpacing.lg),
                    if (moduleAccess.canCreateSales || moduleAccess.canReadCash)
                      AppAnimatedEntrance(
                        delay: const Duration(milliseconds: 180),
                        child: _TodaySummaryCard(
                          cashSummary: _cashSummary,
                          cashReadiness: _cashReadiness,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InventoryAlertsCard extends StatelessWidget {
  const _InventoryAlertsCard({
    required this.summary,
    required this.onOpenOutOfStock,
    required this.onOpenLowStock,
  });

  final AsyncValue<InventoryAlertSummary> summary;
  final VoidCallback onOpenOutOfStock;
  final VoidCallback onOpenLowStock;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Atención de inventario',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: CronosSpacing.xs),
          Text(
            'Estado local de la sucursal activa.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: CronosSpacing.md),
          summary.when(
            loading: () => const LinearProgressIndicator(
              key: Key('inventory-alerts-loading'),
            ),
            error: (_, __) => const Text(
              'No fue posible leer el resumen local de inventario.',
              key: Key('inventory-alerts-error'),
            ),
            data: (value) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  key: const Key('inventory-alerts-out-of-stock'),
                  onPressed: onOpenOutOfStock,
                  icon: const Icon(Icons.remove_shopping_cart_outlined),
                  label: Text('Agotados: ${value.outOfStockCount}'),
                ),
                const SizedBox(height: CronosSpacing.sm),
                OutlinedButton.icon(
                  key: const Key('inventory-alerts-low-stock'),
                  onPressed: onOpenLowStock,
                  icon: const Icon(Icons.warning_amber_rounded),
                  label: Text('Bajo stock: ${value.lowStockCount}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.appContext,
    required this.operationalContext,
    required this.branchContexts,
    required this.isSwitchingBranch,
    required this.onSwitchBranch,
    required this.isLoading,
    required this.lastError,
  });

  final AppCurrentContext? appContext;
  final AuthorizedOperationalContext? operationalContext;
  final List<AuthorizedOperationalContext> branchContexts;
  final bool isSwitchingBranch;
  final ValueChanged<AuthorizedOperationalContext> onSwitchBranch;
  final bool isLoading;
  final Object? lastError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String title = 'Cronos POS';
    String subtitle = 'Ventas, compras, inventario y caja en un solo lugar.';

    if (isLoading) {
      subtitle = 'Preparando tu negocio...';
    } else if (lastError != null) {
      title = 'No pudimos cargar el inicio';
      subtitle = 'Comprueba tu conexión e inténtalo nuevamente.';
    } else if (appContext == null) {
      title = 'Selecciona tu sucursal';
      subtitle = 'Elige un negocio y una sucursal para continuar.';
    } else {
      final businessName = operationalContext?.businessName;
      subtitle = businessName == null
          ? 'Tu sucursal está lista para trabajar.'
          : 'Negocio: $businessName';
    }

    return AppGlassCard(
      padding: EdgeInsets.zero,
      child: Container(
        decoration: const BoxDecoration(
          gradient: CronosColors.primaryGradient,
          borderRadius: BorderRadius.all(
            Radius.circular(CronosRadius.lg),
          ),
        ),
        padding: const EdgeInsets.all(CronosSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(CronosRadius.lg),
              ),
              child: const Icon(
                Icons.storefront_outlined,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(width: CronosSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: CronosSpacing.xs),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.88),
                    ),
                  ),
                  if (operationalContext != null) ...[
                    const SizedBox(height: CronosSpacing.xs),
                    OperationalBranchSwitcher(
                      currentContext: operationalContext!,
                      contexts: branchContexts,
                      isSwitching: isSwitchingBranch,
                      foregroundColor: Colors.white,
                      onSelected: onSwitchBranch,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

AuthorizedOperationalContext? _findOperationalContext(
  Iterable<AuthorizedOperationalContext> contexts,
  String? branchId,
) {
  if (branchId == null) {
    return null;
  }
  for (final context in contexts) {
    if (context.branchId == branchId) {
      return context;
    }
  }
  return null;
}

class _QuickStatusRow extends StatelessWidget {
  const _QuickStatusRow({
    required this.appContext,
    required this.moduleAccess,
    required this.cashSummary,
    required this.cashReadiness,
  });

  final AppCurrentContext? appContext;
  final DashboardModuleAccess moduleAccess;
  final Map<String, dynamic>? cashSummary;
  final Map<String, dynamic>? cashReadiness;

  @override
  Widget build(BuildContext context) {
    final status = cashSummary?['status']?.toString();
    final blockedReason = cashReadiness?['pos_upload_blocked_reason'];
    final dirtyCash = _int(cashReadiness?['dirty_cash_register_count']) > 0 ||
        _int(cashReadiness?['dirty_cash_session_count']) > 0;

    return Wrap(
      spacing: CronosSpacing.sm,
      runSpacing: CronosSpacing.sm,
      children: [
        AppStatusChip(
          label: appContext == null ? 'Sin sucursal' : 'Sucursal lista',
          tone: appContext == null ? AppStatusTone.warning : AppStatusTone.info,
          icon: appContext == null
              ? Icons.warning_amber_outlined
              : Icons.verified_outlined,
        ),
        if (moduleAccess.canUseCash)
          AppStatusChip(
            label: status == 'open'
                ? 'Caja abierta'
                : status == 'closed'
                    ? 'Caja cerrada'
                    : 'Sin caja',
            tone: status == 'open'
                ? AppStatusTone.success
                : status == 'closed'
                    ? AppStatusTone.warning
                    : AppStatusTone.neutral,
            icon: Icons.point_of_sale_outlined,
          ),
        if (moduleAccess.canCreateSales)
          AppStatusChip(
            label:
                blockedReason == null ? 'Ventas disponibles' : 'Revisa la caja',
            tone: blockedReason == null
                ? AppStatusTone.success
                : AppStatusTone.danger,
            icon: Icons.shopping_cart_checkout_outlined,
          ),
        if (moduleAccess.canUseCash && dirtyCash)
          const AppStatusChip(
            label: 'Caja pendiente',
            tone: AppStatusTone.warning,
            icon: Icons.sync_problem_outlined,
          ),
      ],
    );
  }
}

class _ModulesGrid extends StatelessWidget {
  const _ModulesGrid({
    required this.moduleAccess,
    required this.cashSummary,
    required this.cashReadiness,
    required this.onOpenCash,
    required this.onOpenPos,
    required this.onOpenInventory,
    required this.onOpenMovements,
    required this.onOpenPurchases,
    required this.onOpenSalesReports,
    required this.isManualSyncing,
    required this.productiveSyncStatus,
    required this.onManualSync,
  });

  final DashboardModuleAccess moduleAccess;
  final Map<String, dynamic>? cashSummary;
  final Map<String, dynamic>? cashReadiness;
  final VoidCallback onOpenCash;
  final VoidCallback onOpenPos;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenMovements;
  final VoidCallback onOpenPurchases;
  final VoidCallback onOpenSalesReports;
  final bool isManualSyncing;
  final AsyncValue<ProductiveSyncStatus>? productiveSyncStatus;
  final VoidCallback onManualSync;

  @override
  Widget build(BuildContext context) {
    final cashStatus = cashSummary?['status']?.toString();
    final blockedReason = cashReadiness?['pos_upload_blocked_reason'];
    final dirtyCash = _int(cashReadiness?['dirty_cash_register_count']) > 0 ||
        _int(cashReadiness?['dirty_cash_session_count']) > 0;

    final cashLabel = dirtyCash
        ? 'Pendiente de envío'
        : cashStatus == 'open'
            ? 'Abierta'
            : cashStatus == 'closed'
                ? 'Cerrada'
                : 'Sin caja';

    final cashTone = dirtyCash
        ? AppStatusTone.warning
        : cashStatus == 'open'
            ? AppStatusTone.success
            : cashStatus == 'closed'
                ? AppStatusTone.warning
                : AppStatusTone.neutral;

    final posLabel = blockedReason == null ? 'Habilitado' : 'Bloqueado';
    final posTone =
        blockedReason == null ? AppStatusTone.success : AppStatusTone.danger;
    final syncCopy = _productiveSyncCopy(productiveSyncStatus);

    final modules = [
      if (moduleAccess.canCreateSales)
        _DashboardModule(
          title: 'Venta',
          subtitle: blockedReason == null
              ? 'Registra una venta y cobra al cliente.'
              : 'Abre la caja para empezar a vender.',
          icon: Icons.shopping_cart_checkout_outlined,
          gradient: CronosColors.primaryGradient,
          statusLabel: posLabel,
          statusTone: posTone,
          onTap: onOpenPos,
        ),
      if (moduleAccess.canPurchaseInventory)
        _DashboardModule(
          title: 'Compras',
          subtitle: 'Registra compras y actualiza el inventario.',
          icon: Icons.local_shipping_outlined,
          gradient: const LinearGradient(
            colors: [
              CronosColors.secondary,
              CronosColors.accent,
            ],
          ),
          statusLabel: 'Disponible',
          statusTone: AppStatusTone.success,
          onTap: onOpenPurchases,
        ),
      if (moduleAccess.canReadInventory)
        _DashboardModule(
          title: 'Inventario',
          subtitle: 'Consulta el stock de esta sucursal.',
          icon: Icons.inventory_2_outlined,
          gradient: CronosColors.warningGradient,
          statusLabel: 'Disponible',
          statusTone: AppStatusTone.success,
          onTap: onOpenInventory,
        ),
      if (moduleAccess.canUseCash)
        _DashboardModule(
          title: 'Caja',
          subtitle: 'Abre, cierra y revisa el efectivo.',
          icon: Icons.point_of_sale_outlined,
          gradient: CronosColors.successGradient,
          statusLabel: cashLabel,
          statusTone: cashTone,
          onTap: onOpenCash,
        ),
      if (moduleAccess.canReadInventory)
        _DashboardModule(
          title: 'Movimientos',
          subtitle: 'Consulta las entradas y salidas de productos.',
          icon: Icons.timeline_outlined,
          gradient: const LinearGradient(
            colors: [
              Color(0xFF0F766E),
              Color(0xFF14B8A6),
            ],
          ),
          statusLabel: 'Historial',
          statusTone: AppStatusTone.success,
          onTap: onOpenMovements,
        ),
      if (moduleAccess.canViewSalesReports || moduleAccess.canViewCashReports)
        _DashboardModule(
          title: 'Reportes',
          subtitle: 'Consulta ventas, rentabilidad y flujo de caja.',
          icon: Icons.assessment_outlined,
          gradient: const LinearGradient(
            colors: [
              Color(0xFF4338CA),
              Color(0xFF7C3AED),
            ],
          ),
          statusLabel: moduleAccess.canViewSalesReports ? 'Ventas' : 'Caja',
          statusTone: AppStatusTone.info,
          onTap: onOpenSalesReports,
        ),
      if (moduleAccess.hasEffectiveAuthorization)
        _DashboardModule(
          title: 'Sincronizar ahora',
          subtitle: syncCopy.subtitle,
          icon: Icons.sync_outlined,
          gradient: const LinearGradient(
            colors: [
              Color(0xFF334155),
              Color(0xFF64748B),
            ],
          ),
          statusLabel: syncCopy.statusLabel,
          statusTone: syncCopy.statusTone,
          onTap: isManualSyncing ? null : onManualSync,
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = width >= 900
            ? 3
            : width >= 580
                ? 2
                : 1;

        return GridView.builder(
          itemCount: modules.length,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: CronosSpacing.sm,
            crossAxisSpacing: CronosSpacing.sm,
            childAspectRatio: crossAxisCount == 1 ? 1.65 : 1.25,
          ),
          itemBuilder: (context, index) {
            final module = modules[index];

            return AppModuleCard(
              title: module.title,
              subtitle: module.subtitle,
              icon: module.icon,
              gradient: module.gradient,
              statusLabel: module.statusLabel,
              statusTone: module.statusTone,
              onTap: module.onTap,
            );
          },
        );
      },
    );
  }
}

class _ProductiveSyncCopy {
  const _ProductiveSyncCopy({
    required this.subtitle,
    required this.statusLabel,
    required this.statusTone,
  });

  final String subtitle;
  final String statusLabel;
  final AppStatusTone statusTone;
}

_ProductiveSyncCopy _productiveSyncCopy(
  AsyncValue<ProductiveSyncStatus>? status,
) {
  if (status == null || status.isLoading) {
    return const _ProductiveSyncCopy(
      subtitle: 'Revisando tus cambios...',
      statusLabel: 'Revisando...',
      statusTone: AppStatusTone.neutral,
    );
  }

  if (status.hasError) {
    return const _ProductiveSyncCopy(
      subtitle: 'No pudimos revisar tus cambios. Inténtalo nuevamente.',
      statusLabel: 'Estado no disponible',
      statusTone: AppStatusTone.danger,
    );
  }

  final value = status.value;
  if (value == null) {
    return const _ProductiveSyncCopy(
      subtitle: 'No pudimos revisar tus cambios. Inténtalo nuevamente.',
      statusLabel: 'Estado no disponible',
      statusTone: AppStatusTone.danger,
    );
  }

  if (value.isSyncing) {
    return const _ProductiveSyncCopy(
      subtitle: 'Enviando tus cambios.',
      statusLabel: 'Sincronizando...',
      statusTone: AppStatusTone.warning,
    );
  }

  if (value.requiresAttention) {
    return const _ProductiveSyncCopy(
      subtitle: 'Algunos cambios necesitan revisión.',
      statusLabel: 'Necesita atención',
      statusTone: AppStatusTone.danger,
    );
  }

  if (!value.isOnline) {
    final pending = value.totalPending;
    return _ProductiveSyncCopy(
      subtitle: pending == 0
          ? 'No hay conexión. Tus cambios están guardados en este dispositivo.'
          : 'No hay conexión. Tus cambios están guardados en este dispositivo. '
              '$pending ${pending == 1 ? 'cambio pendiente' : 'cambios pendientes'}.',
      statusLabel: 'Sin conexión',
      statusTone: AppStatusTone.warning,
    );
  }

  if (value.allUpToDate) {
    return const _ProductiveSyncCopy(
      subtitle: 'Todos tus cambios están al día.',
      statusLabel: 'Todo al día',
      statusTone: AppStatusTone.success,
    );
  }

  final pendingLabels = <String>[
    _pendingLabel(value.pendingSales, 'venta', 'ventas'),
    _pendingLabel(value.pendingPurchases, 'compra', 'compras'),
    _pendingLabel(value.pendingCashOperations, 'operación de caja',
        'operaciones de caja'),
    _pendingLabel(value.pendingProductOperations, 'producto', 'productos'),
    _pendingLabel(value.pendingInventoryOperations, 'movimiento de inventario',
        'movimientos de inventario'),
  ].where((label) => label.isNotEmpty).toList();

  return _ProductiveSyncCopy(
    subtitle: pendingLabels.join(' · '),
    statusLabel:
        '${value.totalPending} ${value.totalPending == 1 ? 'pendiente' : 'pendientes'}',
    statusTone: AppStatusTone.warning,
  );
}

String _pendingLabel(int count, String singular, String plural) {
  if (count <= 0) {
    return '';
  }
  return '$count ${count == 1 ? singular : plural} ${count == 1 ? 'pendiente' : 'pendientes'}';
}

class _TodaySummaryCard extends StatelessWidget {
  const _TodaySummaryCard({
    required this.cashSummary,
    required this.cashReadiness,
  });

  final Map<String, dynamic>? cashSummary;
  final Map<String, dynamic>? cashReadiness;

  @override
  Widget build(BuildContext context) {
    final blockedReason = cashReadiness?['pos_upload_blocked_reason'];
    final salesTotal = _money(cashSummary?['sales_total']);
    final expectedCash =
        _money(cashSummary?['calculated_expected_cash_amount']);

    return AppGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Resumen operativo',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: CronosSpacing.sm),
          Text(
            blockedReason == null
                ? 'La operación está lista para POS.'
                : 'Hay una condición pendiente antes de vender: $blockedReason',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: CronosSpacing.md),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: 'Ventas sesión',
                  value: salesTotal,
                  icon: Icons.receipt_long_outlined,
                ),
              ),
              const SizedBox(width: CronosSpacing.sm),
              Expanded(
                child: _SummaryMetric(
                  label: 'Efectivo esperado',
                  value: expectedCash,
                  icon: Icons.payments_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CronosSpacing.md),
      decoration: BoxDecoration(
        color: CronosColors.surfaceMuted,
        borderRadius: BorderRadius.circular(CronosRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: CronosColors.primary),
          const SizedBox(width: CronosSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardModule {
  const _DashboardModule({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.statusLabel,
    required this.statusTone,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final String statusLabel;
  final AppStatusTone statusTone;
  final VoidCallback? onTap;
}

String? _string(Object? value) {
  if (value == null) {
    return null;
  }

  final text = value.toString().trim();

  if (text.isEmpty) {
    return null;
  }

  return text;
}

int _int(Object? value) {
  if (value == null) {
    return 0;
  }

  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value.toString()) ?? 0;
}

double _num(Object? value) {
  if (value == null) {
    return 0;
  }

  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value.toString()) ?? 0;
}

String _money(Object? value) {
  return '\$${_num(value).toStringAsFixed(2)}';
}
