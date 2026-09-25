import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_theme.dart';
import '../../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../application/profitability_report_controller.dart';
import '../../application/sales_report_controller.dart';
import '../../data/models/profitability_report_models.dart';

class SalesReportScreen extends ConsumerStatefulWidget {
  const SalesReportScreen({
    super.key,
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.branchName,
    required this.effectivePermissions,
    required this.authorizationContextReady,
    this.authorizationValidatedAt,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String branchName;
  final Set<String> effectivePermissions;
  final bool authorizationContextReady;
  final DateTime? authorizationValidatedAt;

  @override
  ConsumerState<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends ConsumerState<SalesReportScreen> {
  bool _showProfitability = false;

  @override
  Widget build(BuildContext context) {
    final request = SalesReportViewRequest(
      profileId: widget.profileId,
      businessId: widget.businessId,
      branchId: widget.branchId,
      branchName: widget.branchName,
      effectivePermissions: widget.effectivePermissions,
      authorizationContextReady: widget.authorizationContextReady,
      authorizationValidatedAt: widget.authorizationValidatedAt,
    );
    final state = ref.watch(salesReportControllerProvider(request));
    final controller = ref.read(
      salesReportControllerProvider(request).notifier,
    );
    final showProfitability =
        _showProfitability && request.canViewProfitability;
    final profitRequest =
        ProfitabilityReportViewRequest(context: request, period: state.period);
    final presentationAccess = showProfitability
        ? ref.watch(profitabilityPresentationAccessProvider(profitRequest))
        : null;
    final canPresentProfitability =
        showProfitability && presentationAccess?.asData?.value == true;
    final profitabilityProvider = profitabilityReportControllerProvider(
      profitRequest,
    );
    final profitabilityState =
        canPresentProfitability ? ref.watch(profitabilityProvider) : null;
    final isRefreshing = canPresentProfitability
        ? profitabilityState!.isRefreshing
        : state.isRefreshing;
    final Future<void> Function() refresh = canPresentProfitability
        ? ref.read(profitabilityProvider.notifier).refresh
        : controller.refresh;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reportes'),
        actions: [
          IconButton(
            key: const Key('sales-report-refresh'),
            onPressed:
                isRefreshing || (showProfitability && !canPresentProfitability)
                    ? null
                    : refresh,
            tooltip: 'Actualizar reporte',
            icon: isRefreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: AppGradientBackground(
        child: RefreshIndicator(
          onRefresh: showProfitability && !canPresentProfitability
              ? () async {}
              : refresh,
          child: ListView(
            key: const Key('sales-report-scroll'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(CronosSpacing.md),
            children: [
              Text(
                widget.branchName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: CronosSpacing.xs),
              Text(
                _formatPeriod(state.period.from, state.period.to),
                key: const Key('sales-report-period'),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: CronosSpacing.md),
              if (request.canViewProfitability) ...[
                SegmentedButton<bool>(
                  key: const Key('report-view-selector'),
                  segments: const [
                    ButtonSegment(value: false, label: Text('Ventas')),
                    ButtonSegment(value: true, label: Text('Rentabilidad')),
                  ],
                  selected: {showProfitability},
                  onSelectionChanged: (selection) {
                    setState(() => _showProfitability = selection.single);
                  },
                ),
                const SizedBox(height: CronosSpacing.md),
              ],
              Wrap(
                spacing: CronosSpacing.xs,
                runSpacing: CronosSpacing.xs,
                children: [
                  for (final preset in SalesReportPreset.values)
                    ChoiceChip(
                      key: Key('sales-report-preset-${preset.name}'),
                      label: Text(preset.label),
                      selected: state.preset == preset,
                      onSelected: isRefreshing
                          ? null
                          : (selected) async {
                              if (preset == SalesReportPreset.custom) {
                                final range = await showDateRangePicker(
                                  context: context,
                                  initialDateRange: DateTimeRange(
                                    start: state.selectedStartDate,
                                    end: state.selectedEndDate,
                                  ),
                                  // Material requires calendar bounds; use the
                                  // full four-digit calendar, no duration cap.
                                  firstDate: DateTime(1),
                                  lastDate: DateTime(9999, 12, 31),
                                  helpText: 'Selecciona un rango de fechas',
                                  cancelText: 'Cancelar',
                                  confirmText: 'Aplicar',
                                  saveText: 'Aplicar',
                                  fieldStartLabelText: 'Fecha inicial',
                                  fieldEndLabelText: 'Fecha final',
                                );
                                if (!context.mounted || range == null) return;
                                await controller.selectCustomRange(
                                  startDate: range.start,
                                  endDate: range.end,
                                );
                              } else if (selected) {
                                await controller.selectPreset(preset);
                              }
                            },
                    ),
                ],
              ),
              const SizedBox(height: CronosSpacing.md),
              if (!showProfitability && state.notice != null) ...[
                _SalesReportNotice(notice: state.notice!),
                const SizedBox(height: CronosSpacing.md),
              ],
              if (canPresentProfitability &&
                  profitabilityState!.notice != null) ...[
                _ProfitabilityReportNotice(notice: profitabilityState.notice!),
                const SizedBox(height: CronosSpacing.md),
              ],
              if (showProfitability)
                if (presentationAccess!.isLoading)
                  const Center(
                    child: CircularProgressIndicator(
                      key: Key('profitability-report-access-loading'),
                    ),
                  )
                else if (!canPresentProfitability)
                  const _SalesReportMessage(
                    key: Key('profitability-report-unauthorized'),
                    icon: Icons.lock_outline,
                    title: 'Reporte no autorizado',
                    message: 'No tienes permiso para consultar rentabilidad.',
                  )
                else
                  _ProfitabilityReportBody(state: profitabilityState!)
              else
                _SalesReportBody(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

class _SalesReportBody extends StatelessWidget {
  const _SalesReportBody({required this.state});

  final SalesReportScreenState state;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot;
    if (state.phase == SalesReportScreenPhase.initialLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(CronosSpacing.xl),
          child: CircularProgressIndicator(
            key: Key('sales-report-loading'),
          ),
        ),
      );
    }

    if (state.phase == SalesReportScreenPhase.unauthorized) {
      return const _SalesReportMessage(
        key: Key('sales-report-unauthorized'),
        icon: Icons.lock_outline,
        title: 'Reporte no autorizado',
        message: 'No tienes permiso para consultar reportes de ventas.',
      );
    }

    if (state.phase == SalesReportScreenPhase.unavailableOffline) {
      return const _SalesReportMessage(
        key: Key('sales-report-unavailable-offline'),
        icon: Icons.cloud_off_outlined,
        title: 'Reporte no disponible sin conexión',
        message:
            'Este periodo todavía no tiene un reporte guardado en el dispositivo.',
      );
    }

    if (state.phase == SalesReportScreenPhase.error || snapshot == null) {
      return const _SalesReportMessage(
        key: Key('sales-report-error'),
        icon: Icons.error_outline,
        title: 'No fue posible cargar el reporte',
        message: 'Intenta actualizar cuando tengas conexión.',
      );
    }

    final summary = snapshot.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SalesMetricCard(
          key: const Key('sales-report-gross-sales'),
          label: 'Ventas totales',
          value: formatSalesReportMoney(summary.grossSalesCents),
          icon: Icons.payments_outlined,
        ),
        const SizedBox(height: CronosSpacing.sm),
        _SalesMetricCard(
          key: const Key('sales-report-sale-count'),
          label: 'Número de ventas',
          value: summary.saleCount.toString(),
          icon: Icons.receipt_long_outlined,
        ),
        const SizedBox(height: CronosSpacing.sm),
        _SalesMetricCard(
          key: const Key('sales-report-average-ticket'),
          label: 'Ticket promedio',
          value: summary.averageTicketCents == null
              ? '—'
              : formatSalesReportMoney(summary.averageTicketCents!),
          icon: Icons.calculate_outlined,
        ),
        const SizedBox(height: CronosSpacing.md),
        Text(
          'Actualizado ${_formatDateTime(snapshot.fetchedAt)}',
          key: const Key('sales-report-fetched-at'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ProfitabilityReportBody extends StatelessWidget {
  const _ProfitabilityReportBody({required this.state});

  final ProfitabilityReportScreenState state;

  @override
  Widget build(BuildContext context) {
    if (state.phase == ProfitabilityReportPhase.initialLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(CronosSpacing.xl),
          child: CircularProgressIndicator(
            key: Key('profitability-report-loading'),
          ),
        ),
      );
    }
    if (state.phase == ProfitabilityReportPhase.unauthorized) {
      return const _SalesReportMessage(
        key: Key('profitability-report-unauthorized'),
        icon: Icons.lock_outline,
        title: 'Reporte no autorizado',
        message: 'No tienes permiso para consultar rentabilidad.',
      );
    }
    if (state.phase == ProfitabilityReportPhase.unavailableOffline) {
      return const _SalesReportMessage(
        key: Key('profitability-report-unavailable-offline'),
        icon: Icons.cloud_off_outlined,
        title: 'Reporte no disponible sin conexión',
        message:
            'Este periodo todavía no tiene un reporte guardado en el dispositivo.',
      );
    }
    final snapshot = state.snapshot;
    if (state.phase == ProfitabilityReportPhase.error || snapshot == null) {
      return const _SalesReportMessage(
        key: Key('profitability-report-error'),
        icon: Icons.error_outline,
        title: 'No fue posible cargar el reporte',
        message: 'Intenta actualizar cuando tengas conexión.',
      );
    }

    final summary = snapshot.summary;
    final complete = summary.costCoverageComplete;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!complete) ...[
          AppGlassCard(
            key: const Key('profitability-report-partial'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rentabilidad parcial',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: CronosSpacing.xs),
                const Text(
                  'Hay ventas con costo desconocido. La utilidad mostrada '
                  'corresponde solo a los ítems con costo conocido.',
                ),
              ],
            ),
          ),
          const SizedBox(height: CronosSpacing.sm),
        ],
        _SalesMetricCard(
          key: const Key('profitability-report-known-net-sales'),
          label: 'Ventas netas analizadas',
          value: formatSalesReportMoney(summary.knownNetSalesCents),
          icon: Icons.payments_outlined,
        ),
        const SizedBox(height: CronosSpacing.sm),
        _SalesMetricCard(
          key: const Key('profitability-report-known-cogs'),
          label: 'Costo de lo vendido',
          value: formatSalesReportMoney(summary.knownCogsCents),
          icon: Icons.inventory_2_outlined,
        ),
        const SizedBox(height: CronosSpacing.sm),
        _SalesMetricCard(
          key: const Key('profitability-report-known-gross-profit'),
          label: complete ? 'Utilidad bruta' : 'Utilidad bruta conocida',
          value: formatSalesReportMoney(summary.knownGrossProfitCents),
          icon: Icons.trending_up_outlined,
        ),
        const SizedBox(height: CronosSpacing.sm),
        _SalesMetricCard(
          key: const Key('profitability-report-known-gross-margin'),
          label: complete ? 'Margen bruto' : 'Margen bruto conocido',
          value: formatProfitabilityMargin(summary.knownGrossMargin),
          icon: Icons.percent_outlined,
        ),
        if (!complete) ...[
          const SizedBox(height: CronosSpacing.sm),
          _SalesMetricCard(
            key: const Key('profitability-report-unknown-count'),
            label: 'Ítems sin costo',
            value: summary.unknownCostItemCount.toString(),
            icon: Icons.help_outline,
          ),
          const SizedBox(height: CronosSpacing.sm),
          _SalesMetricCard(
            key: const Key('profitability-report-unknown-sales'),
            label: 'Ventas asociadas a costo desconocido',
            value: formatSalesReportMoney(summary.unknownCostNetSalesCents),
            icon: Icons.receipt_long_outlined,
          ),
        ] else ...[
          const SizedBox(height: CronosSpacing.sm),
          Text(
            'Cobertura de costos completa',
            key: const Key('profitability-report-complete-coverage'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: CronosSpacing.md),
        Text(
          'Actualizado ${_formatDateTime(snapshot.fetchedAt)}',
          key: const Key('profitability-report-fetched-at'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _SalesMetricCard extends StatelessWidget {
  const _SalesMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      child: Row(
        children: [
          Icon(icon, color: CronosColors.primary),
          const SizedBox(width: CronosSpacing.md),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text(
                value,
                maxLines: 1,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesReportNotice extends StatelessWidget {
  const _SalesReportNotice({required this.notice});

  final SalesReportScreenNotice notice;

  @override
  Widget build(BuildContext context) {
    final message = switch (notice) {
      SalesReportScreenNotice.offlineCache =>
        'Sin conexión · mostrando último reporte guardado',
      SalesReportScreenNotice.refreshFailed =>
        'No se pudo actualizar · mostrando datos guardados',
    };

    return AppGlassCard(
      key: const Key('sales-report-notice'),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: CronosColors.warning),
          const SizedBox(width: CronosSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _ProfitabilityReportNotice extends StatelessWidget {
  const _ProfitabilityReportNotice({required this.notice});

  final ProfitabilityReportNotice notice;

  @override
  Widget build(BuildContext context) {
    final message = switch (notice) {
      ProfitabilityReportNotice.offlineCache =>
        'Sin conexión · mostrando último reporte guardado',
      ProfitabilityReportNotice.refreshFailed =>
        'No se pudo actualizar · mostrando datos guardados',
    };
    return AppGlassCard(
      key: const Key('profitability-report-notice'),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: CronosColors.warning),
          const SizedBox(width: CronosSpacing.sm),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}

class _SalesReportMessage extends StatelessWidget {
  const _SalesReportMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      child: Column(
        children: [
          Icon(icon, size: 42, color: CronosColors.primary),
          const SizedBox(height: CronosSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: CronosSpacing.xs),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

String formatSalesReportMoney(BigInt cents) {
  final negative = cents.isNegative;
  final absolute = cents.abs();
  final whole = absolute ~/ BigInt.from(100);
  final fraction = (absolute % BigInt.from(100)).toInt();
  final digits = whole.toString();
  final grouped = StringBuffer();

  for (var index = 0; index < digits.length; index += 1) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      grouped.write('.');
    }
    grouped.write(digits[index]);
  }

  final sign = negative ? '-' : '';
  if (fraction == 0) {
    return '$sign\$$grouped';
  }
  return '$sign\$$grouped,${fraction.toString().padLeft(2, '0')}';
}

String formatProfitabilityMargin(ExactProfitabilityMargin? margin) {
  if (margin == null) return '—';
  final denominator = margin.denominator.abs();
  if (denominator == BigInt.zero) return '—';
  final numerator = margin.numerator.abs() * BigInt.from(10000);
  var hundredths = numerator ~/ denominator;
  if ((numerator % denominator) * BigInt.two >= denominator) {
    hundredths += BigInt.one;
  }
  final sign = hundredths != BigInt.zero &&
          margin.numerator.isNegative != margin.denominator.isNegative
      ? '-'
      : '';
  final whole = hundredths ~/ BigInt.from(100);
  final fraction = (hundredths % BigInt.from(100)).toString().padLeft(2, '0');
  return '$sign$whole,$fraction %';
}

String _formatPeriod(DateTime fromUtc, DateTime toUtc) {
  final from = fromUtc.toLocal();
  final exclusiveTo = toUtc.toLocal();
  final inclusiveTo = DateTime(
    exclusiveTo.year,
    exclusiveTo.month,
    exclusiveTo.day - 1,
  );
  if (from.year == inclusiveTo.year &&
      from.month == inclusiveTo.month &&
      from.day == inclusiveTo.day) {
    return _formatDate(from);
  }
  return '${_formatDate(from)} – ${_formatDate(inclusiveTo)}';
}

String _formatDate(DateTime value) {
  return '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_formatDate(local)} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}
