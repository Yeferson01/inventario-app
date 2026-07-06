import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/providers/device_provider.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../../cash/application/cash_session_local_provider.dart';
import '../../../cash/presentation/screens/cash_dashboard_screen.dart';
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

    if (appContext == null) {
      _showInfoSheet(
        title: 'Falta contexto',
        message:
            'Selecciona un negocio y una sucursal antes de abrir el módulo de caja.',
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
        ),
      ),
    );

    await _load();
  }

  void _openPosGate() {
    final blockedReason = _cashReadiness?['pos_upload_blocked_reason'];
    final canOpenPos = blockedReason == null;

    if (!canOpenPos) {
      _showInfoSheet(
        title: 'POS bloqueado',
        message:
            'Para vender primero debes tener caja abierta y sin pendientes críticos de cash.\n\nMotivo: ${blockedReason ?? 'Caja no lista.'}',
        primaryLabel: 'Ir a Caja',
        onPrimary: () {
          Navigator.of(context).pop();
          _openCashDashboard();
        },
      );
      return;
    }

    _showInfoSheet(
      title: 'POS',
      message:
          'La caja está lista. La pantalla POS real se construye en la fase 6.18C.40.',
    );
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
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Configuración',
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
                        appContext: _appContext,
                        cashSummary: _cashSummary,
                        cashReadiness: _cashReadiness,
                        onOpenCash: _openCashDashboard,
                        onOpenPos: _openPosGate,
                        onComingSoon: _showInfoSheet,
                      ),
                    ),
                    const SizedBox(height: CronosSpacing.lg),
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
      subtitle = lastError.toString();
    } else if (appContext == null) {
      title = 'Selecciona un contexto';
      subtitle =
          'Antes de operar debes seleccionar negocio, sucursal y perfil.';
    } else {
      final role = appContext?.roleName;
      subtitle =
          'Negocio activo: ${appContext!.businessId}. Rol: ${role ?? 'sin rol local'}.';
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
    required this.cashSummary,
    required this.cashReadiness,
  });

  final AppCurrentContext? appContext;
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
        AppStatusChip(
          label: blockedReason == null ? 'POS habilitado' : 'POS bloqueado',
          tone: blockedReason == null
              ? AppStatusTone.success
              : AppStatusTone.danger,
          icon: Icons.shopping_cart_checkout_outlined,
        ),
        if (dirtyCash)
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
    required this.appContext,
    required this.cashSummary,
    required this.cashReadiness,
    required this.onOpenCash,
    required this.onOpenPos,
    required this.onComingSoon,
  });

  final AppCurrentContext? appContext;
  final Map<String, dynamic>? cashSummary;
  final Map<String, dynamic>? cashReadiness;
  final VoidCallback onOpenCash;
  final VoidCallback onOpenPos;
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
      _DashboardModule(
        title: 'Caja',
        subtitle: 'Abrir, cerrar, sincronizar y revisar efectivo.',
        icon: Icons.point_of_sale_outlined,
        gradient: CronosColors.successGradient,
        statusLabel: cashLabel,
        statusTone: cashTone,
        onTap: onOpenCash,
      ),
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
      _DashboardModule(
        title: 'Inventario',
        subtitle: 'Consultar stock, saldos y alertas.',
        icon: Icons.inventory_2_outlined,
        gradient: CronosColors.warningGradient,
        statusLabel: 'Base lista',
        statusTone: AppStatusTone.warning,
        onTap: () {
          onComingSoon(
            title: 'Inventario',
            message: 'Conectaremos inventario después de POS.',
          );
        },
      ),
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
        statusLabel: 'Backend listo',
        statusTone: AppStatusTone.info,
        onTap: () {
          onComingSoon(
            title: 'Compras',
            message: 'La UI de compras se conectará después de inventario.',
          );
        },
      ),
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
