import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/providers/device_provider.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../../cash/application/cash_session_local_provider.dart';
import '../../../cash/presentation/screens/cash_dashboard_screen.dart';
import '../../../auth/application/productive_auth_providers.dart';
import '../../application/dashboard_module_access.dart';
import '../../../inventory/presentation/screens/inventory_product_stock_list_screen.dart';
import '../../../inventory/presentation/screens/purchase_entry_screen.dart';
import '../../../sync/application/app_context_models.dart';
import '../../../sync/application/app_current_context_provider.dart';
import '../../../sales/presentation/sales_presentation.dart';

class MainDashboardScreen extends ConsumerStatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  ConsumerState<MainDashboardScreen> createState() =>
      _MainDashboardScreenState();
}

class _MainDashboardScreenState extends ConsumerState<MainDashboardScreen> {
  bool _isLoading = true;
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
        title: appContext == null ? 'Falta contexto' : 'Acceso no autorizado',
        message: appContext == null
            ? 'Selecciona un negocio y una sucursal antes de abrir el módulo de caja.'
            : 'El contexto actual no posee permisos efectivos de caja.',
      );
      return;
    }

    final branchId = appContext.branchId;
    final profileId = appContext.profileId;

    if (branchId == null || profileId == null) {
      _showInfoSheet(
        title: 'Contexto incompleto',
        message:
            'El dashboard encontró negocio, pero falta sucursal o perfil operativo.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CashDashboardScreen(
          businessId: appContext.businessId,
          branchId: branchId,
          profileId: profileId,
          appDeviceId: appContext.appDeviceId,
          deviceInstallationId: appContext.installationId,
          canReadCash: access.canReadCash,
          canOpenCash: access.canOpenCash,
          canCloseCash: access.canCloseCash,
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
        title: appContext == null ? 'Falta contexto' : 'Acceso no autorizado',
        message: appContext == null
            ? 'Selecciona un negocio y una sucursal antes de abrir compras.'
            : 'Registrar compras requiere inventory.purchase.',
      );
      return;
    }

    final branchId = appContext.branchId;
    final profileId = appContext.profileId;

    if (branchId == null || profileId == null) {
      _showInfoSheet(
        title: 'Contexto incompleto',
        message:
            'Compras necesita negocio, sucursal y perfil operativo activo.',
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

  Future<void> _openInventory() async {
    final appContext = _appContext;
    final access = DashboardModuleAccess.fromContext(appContext);

    if (appContext == null || !access.canReadInventory) {
      _showInfoSheet(
        title: appContext == null ? 'Falta contexto' : 'Acceso no autorizado',
        message: appContext == null
            ? 'Selecciona un negocio y una sucursal antes de abrir inventario.'
            : 'Consultar inventario requiere inventory.read.',
      );
      return;
    }

    final businessId = appContext.businessId.trim();
    final branchId = appContext.branchId?.trim();

    if (businessId.isEmpty || branchId == null || branchId.isEmpty) {
      _showInfoSheet(
        title: 'Contexto incompleto',
        message: 'Inventario necesita un negocio y una sucursal activos.',
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InventoryProductStockListScreen(
          businessId: businessId,
          branchId: branchId,
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

  void _openPosGate() {
    final appContext = _appContext;
    final access = DashboardModuleAccess.fromContext(appContext);

    if (appContext == null || !access.canCreateSales) {
      _showInfoSheet(
        title: appContext == null ? 'Falta contexto' : 'Acceso no autorizado',
        message: appContext == null
            ? 'Selecciona un negocio y una sucursal antes de abrir el POS.'
            : 'Crear ventas requiere sales.create.',
      );
      return;
    }

    final branchId = appContext.branchId;
    final profileId = appContext.profileId;

    if (branchId == null || profileId == null) {
      _showInfoSheet(
        title: 'Contexto incompleto',
        message: 'El POS necesita negocio, sucursal y perfil operativo activo.',
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
        title: 'POS bloqueado',
        message:
            'Para vender primero debes abrir caja. Esto aplica aunque el usuario sea admin; el admin puede usar el dashboard, pero POS requiere caja abierta.',
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
        title: 'POS bloqueado',
        message:
            'Para vender primero debes tener caja abierta y sin pendientes críticos de cash.\n\nMotivo: $blockedReason',
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
                if (moduleAccess.canManageSettings)
                  IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Configuración',
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
                        isLoading: _isLoading,
                        lastError: _lastError,
                      ),
                    ),
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
                        onOpenInventory: _openInventory,
                        onOpenPurchases: _openPurchases,
                        onComingSoon: _showInfoSheet,
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

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.appContext,
    required this.isLoading,
    required this.lastError,
  });

  final AppCurrentContext? appContext;
  final bool isLoading;
  final Object? lastError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String title = 'Bienvenido a Cronos';
    String subtitle =
        'Controla caja, ventas, inventario, compras y sincronización desde un solo lugar.';

    if (isLoading) {
      subtitle = 'Cargando contexto operativo...';
    } else if (lastError != null) {
      title = 'No se pudo cargar el dashboard';
      subtitle =
          'No fue posible cargar el contexto operativo. Intenta actualizar.';
    } else if (appContext == null) {
      title = 'Selecciona un contexto';
      subtitle =
          'Antes de operar debes seleccionar negocio, sucursal y perfil.';
    } else {
      final role = appContext?.roleName;
      subtitle =
          'Negocio activo: ${appContext!.businessId}. Roles efectivos: ${role ?? 'sin descripción local'}.';
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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
          label: appContext == null ? 'Sin contexto' : 'Contexto activo',
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
            label: blockedReason == null ? 'POS habilitado' : 'POS bloqueado',
            tone: blockedReason == null
                ? AppStatusTone.success
                : AppStatusTone.danger,
            icon: Icons.shopping_cart_checkout_outlined,
          ),
        if (moduleAccess.canUseCash && dirtyCash)
          const AppStatusChip(
            label: 'Cash pendiente',
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
    required this.onOpenPurchases,
    required this.onComingSoon,
  });

  final DashboardModuleAccess moduleAccess;
  final Map<String, dynamic>? cashSummary;
  final Map<String, dynamic>? cashReadiness;
  final VoidCallback onOpenCash;
  final VoidCallback onOpenPos;
  final VoidCallback onOpenInventory;
  final VoidCallback onOpenPurchases;
  final void Function({
    required String title,
    required String message,
    String primaryLabel,
    VoidCallback? onPrimary,
  }) onComingSoon;

  @override
  Widget build(BuildContext context) {
    final cashStatus = cashSummary?['status']?.toString();
    final blockedReason = cashReadiness?['pos_upload_blocked_reason'];
    final dirtyCash = _int(cashReadiness?['dirty_cash_register_count']) > 0 ||
        _int(cashReadiness?['dirty_cash_session_count']) > 0;

    final cashLabel = dirtyCash
        ? 'Pendiente sync'
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

    final modules = [
      if (moduleAccess.canUseCash)
        _DashboardModule(
          title: 'Caja',
          subtitle: 'Abrir, cerrar, sincronizar y revisar efectivo.',
          icon: Icons.point_of_sale_outlined,
          gradient: CronosColors.successGradient,
          statusLabel: cashLabel,
          statusTone: cashTone,
          onTap: onOpenCash,
        ),
      if (moduleAccess.canCreateSales)
        _DashboardModule(
          title: 'POS',
          subtitle: blockedReason == null
              ? 'Caja lista. Puedes iniciar ventas.'
              : 'Primero debes dejar caja lista para vender.',
          icon: Icons.shopping_cart_checkout_outlined,
          gradient: CronosColors.primaryGradient,
          statusLabel: posLabel,
          statusTone: posTone,
          onTap: onOpenPos,
        ),
      if (moduleAccess.canReadInventory)
        _DashboardModule(
          title: 'Inventario',
          subtitle: 'Consultar stock operativo de la sucursal actual.',
          icon: Icons.inventory_2_outlined,
          gradient: CronosColors.warningGradient,
          statusLabel: 'Operativo local',
          statusTone: AppStatusTone.success,
          onTap: onOpenInventory,
        ),
      if (moduleAccess.canPurchaseInventory)
        _DashboardModule(
          title: 'Compras',
          subtitle: 'Registrar compras y aumentar stock.',
          icon: Icons.local_shipping_outlined,
          gradient: const LinearGradient(
            colors: [
              CronosColors.secondary,
              CronosColors.accent,
            ],
          ),
          statusLabel: 'Operativo local',
          statusTone: AppStatusTone.success,
          onTap: onOpenPurchases,
        ),
      if (moduleAccess.canReadInventory)
        _DashboardModule(
          title: 'Movimientos',
          subtitle: 'Trazabilidad de entradas y salidas.',
          icon: Icons.timeline_outlined,
          gradient: const LinearGradient(
            colors: [
              Color(0xFF0F766E),
              Color(0xFF14B8A6),
            ],
          ),
          statusLabel: 'Pendiente',
          statusTone: AppStatusTone.neutral,
          onTap: () {
            onComingSoon(
              title: 'Movimientos',
              message: 'Mostraremos movimientos de inventario y auditoría.',
            );
          },
        ),
      if (moduleAccess.hasEffectiveAuthorization)
        _DashboardModule(
          title: 'Sync',
          subtitle: 'Estado de cola, pendientes y errores.',
          icon: Icons.sync_outlined,
          gradient: const LinearGradient(
            colors: [
              Color(0xFF334155),
              Color(0xFF64748B),
            ],
          ),
          statusLabel: 'Interno',
          statusTone: AppStatusTone.neutral,
          onTap: () {
            onComingSoon(
              title: 'Sync',
              message: 'El monitor visual de sync viene después.',
            );
          },
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
  final VoidCallback onTap;
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
