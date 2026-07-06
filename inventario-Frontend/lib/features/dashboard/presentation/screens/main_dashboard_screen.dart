import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';

class MainDashboardScreen extends StatelessWidget {
  const MainDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: CronosTheme.light(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cronos POS'),
          actions: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_outlined),
              tooltip: 'Notificaciones',
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.settings_outlined),
              tooltip: 'Configuración',
            ),
          ],
        ),
        body: AppGradientBackground(
          child: ListView(
            padding: const EdgeInsets.all(CronosSpacing.md),
            children: [
              const AppAnimatedEntrance(
                child: _DashboardHeader(),
              ),
              const SizedBox(height: CronosSpacing.lg),
              AppAnimatedEntrance(
                delay: const Duration(milliseconds: 80),
                child: _QuickStatusRow(),
              ),
              const SizedBox(height: CronosSpacing.lg),
              Text(
                'Módulos principales',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: CronosSpacing.sm),
              AppAnimatedEntrance(
                delay: const Duration(milliseconds: 120),
                child: _ModulesGrid(),
              ),
              const SizedBox(height: CronosSpacing.lg),
              AppAnimatedEntrance(
                delay: const Duration(milliseconds: 180),
                child: const _TodaySummaryCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                    'Bienvenido a Cronos',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: CronosSpacing.xs),
                  Text(
                    'Controla caja, ventas, inventario, compras y sincronización desde un solo lugar.',
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
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: CronosSpacing.sm,
      runSpacing: CronosSpacing.sm,
      children: const [
        AppStatusChip(
          label: 'Offline-first',
          tone: AppStatusTone.info,
          icon: Icons.cloud_done_outlined,
        ),
        AppStatusChip(
          label: 'Inventario por movimientos',
          tone: AppStatusTone.success,
          icon: Icons.inventory_2_outlined,
        ),
        AppStatusChip(
          label: 'Caja obligatoria',
          tone: AppStatusTone.warning,
          icon: Icons.point_of_sale_outlined,
        ),
      ],
    );
  }
}

class _ModulesGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final modules = [
      _DashboardModule(
        title: 'Caja',
        subtitle: 'Abrir, cerrar, sincronizar y revisar efectivo.',
        icon: Icons.point_of_sale_outlined,
        gradient: CronosColors.successGradient,
        statusLabel: 'Activo',
        statusTone: AppStatusTone.success,
        onTap: () {
          _showComingSoon(
            context,
            'Caja',
            'Por ahora entra desde el laboratorio E2E. En la siguiente fase conectamos esta tarjeta a la ruta real de caja.',
          );
        },
      ),
      _DashboardModule(
        title: 'POS',
        subtitle: 'Crear ventas, agregar productos y cobrar.',
        icon: Icons.shopping_cart_checkout_outlined,
        gradient: CronosColors.primaryGradient,
        statusLabel: 'Próximo',
        statusTone: AppStatusTone.info,
        onTap: () {
          _showComingSoon(context, 'POS',
              'La pantalla POS real viene en la fase 6.18C.40.');
        },
      ),
      _DashboardModule(
        title: 'Inventario',
        subtitle: 'Consultar stock, saldos y alertas.',
        icon: Icons.inventory_2_outlined,
        gradient: CronosColors.warningGradient,
        statusLabel: 'Base lista',
        statusTone: AppStatusTone.warning,
        onTap: () {
          _showComingSoon(
              context, 'Inventario', 'Conectaremos inventario después de POS.');
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
          _showComingSoon(context, 'Compras',
              'La UI de compras se conectará después de inventario.');
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
          _showComingSoon(context, 'Movimientos',
              'Mostraremos movimientos de inventario y auditoría.');
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
          _showComingSoon(
              context, 'Sync', 'El monitor visual de sync viene después.');
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

  void _showComingSoon(
    BuildContext context,
    String title,
    String message,
  ) {
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
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TodaySummaryCard extends StatelessWidget {
  const _TodaySummaryCard();

  @override
  Widget build(BuildContext context) {
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
            'Aquí mostraremos ventas del día, efectivo esperado, productos con bajo stock y pendientes de sincronización.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: CronosSpacing.md),
          const Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: 'Ventas',
                  value: '—',
                  icon: Icons.receipt_long_outlined,
                ),
              ),
              SizedBox(width: CronosSpacing.sm),
              Expanded(
                child: _SummaryMetric(
                  label: 'Stock bajo',
                  value: '—',
                  icon: Icons.warning_amber_outlined,
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
