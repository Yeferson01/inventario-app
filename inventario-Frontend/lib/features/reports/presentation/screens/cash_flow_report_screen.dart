import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../app/theme/app_theme.dart';
import '../../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../../cash/application/cash_movement_models.dart';
import '../../application/cash_flow_report_controller.dart';
import '../../application/sales_report_controller.dart';
import 'sales_report_screen.dart' show formatSalesReportMoney;

class CashFlowReportScreen extends ConsumerWidget {
  const CashFlowReportScreen(
      {super.key,
      required this.profileId,
      required this.businessId,
      required this.branchId,
      required this.branchName,
      required this.effectivePermissions,
      required this.authorizationContextReady,
      this.authorizationValidatedAt});

  final String profileId;
  final String businessId;
  final String branchId;
  final String branchName;
  final Set<String> effectivePermissions;
  final bool authorizationContextReady;
  final DateTime? authorizationValidatedAt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = SalesReportViewRequest(
        profileId: profileId,
        businessId: businessId,
        branchId: branchId,
        branchName: branchName,
        effectivePermissions: effectivePermissions,
        authorizationContextReady: authorizationContextReady,
        authorizationValidatedAt: authorizationValidatedAt);
    final state = ref.watch(cashFlowReportControllerProvider(request));
    final controller =
        ref.read(cashFlowReportControllerProvider(request).notifier);
    return Theme(
      data: CronosTheme.light(),
      child: Builder(
          builder: (themedContext) => Scaffold(
                appBar: AppBar(
                    title: const Text('Flujo de caja y gastos'),
                    actions: [
                      IconButton(
                          key: const Key('cash-flow-refresh'),
                          onPressed:
                              state.isRefreshing ? null : controller.refresh,
                          tooltip: 'Actualizar reporte',
                          icon: const Icon(Icons.refresh_outlined)),
                    ]),
                body: AppGradientBackground(
                    child: RefreshIndicator(
                  onRefresh: controller.refresh,
                  child: ListView(
                      key: const Key('cash-flow-scroll'),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(CronosSpacing.md),
                      children: [
                        Text(branchName,
                            style:
                                Theme.of(themedContext).textTheme.titleLarge),
                        const SizedBox(height: CronosSpacing.sm),
                        Wrap(
                            spacing: CronosSpacing.xs,
                            runSpacing: CronosSpacing.xs,
                            children: [
                              for (final preset in CashFlowPreset.values)
                                ChoiceChip(
                                    key: Key('cash-flow-preset-${preset.name}'),
                                    label: Text(preset.label),
                                    selected: state.preset == preset,
                                    onSelected: state.isRefreshing
                                        ? null
                                        : (selected) async {
                                            if (preset ==
                                                CashFlowPreset.custom) {
                                              final range =
                                                  await showDateRangePicker(
                                                      context: themedContext,
                                                      initialDateRange:
                                                          DateTimeRange(
                                                              start: state
                                                                  .startDate,
                                                              end: state
                                                                  .endDate),
                                                      firstDate: DateTime(1),
                                                      lastDate: DateTime(
                                                          9999, 12, 31),
                                                      helpText:
                                                          'Selecciona un rango de fechas');
                                              if (!themedContext.mounted ||
                                                  range == null) {
                                                return;
                                              }
                                              await controller
                                                  .selectCustomRange(
                                                      range.start, range.end);
                                            } else if (selected) {
                                              await controller
                                                  .selectPreset(preset);
                                            }
                                          }),
                            ]),
                        const SizedBox(height: CronosSpacing.md),
                        if (state.notice != null) ...[
                          AppGlassCard(
                              key: const Key('cash-flow-notice'),
                              child: Text(state.notice ==
                                      CashFlowNotice.offlineCache
                                  ? 'Sin conexión · mostrando último reporte guardado'
                                  : 'No se pudo actualizar · mostrando datos guardados')),
                          const SizedBox(height: CronosSpacing.sm),
                        ],
                        if (state.phase == CashFlowPhase.loading)
                          const Center(child: CircularProgressIndicator())
                        else if (state.phase == CashFlowPhase.unauthorized)
                          const _Message(
                              'No tienes permiso para consultar este reporte.')
                        else if (state.phase ==
                            CashFlowPhase.unavailableOffline)
                          const _Message(
                              'Este período no tiene un reporte guardado para uso sin conexión.')
                        else if (state.phase == CashFlowPhase.error ||
                            state.snapshot == null)
                          const _Message(
                              'No fue posible cargar el reporte. Intenta actualizar.')
                        else
                          _CashFlowBody(state: state),
                      ]),
                )),
              )),
    );
  }
}

class _CashFlowBody extends StatelessWidget {
  const _CashFlowBody({required this.state});
  final CashFlowScreenState state;

  @override
  Widget build(BuildContext context) {
    final snapshot = state.snapshot!;
    final summary = snapshot.summary;
    final categoryTotals = summary.outflowByCategory;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (snapshot.hasPendingLocalSync ||
          snapshot.hasPendingLocalCashSales) ...[
        AppGlassCard(
            key: const Key('cash-flow-pending-warning'),
            child: Text(snapshot.hasPendingLocalSync &&
                    snapshot.hasPendingLocalCashSales
                ? 'Hay movimientos o ventas en efectivo pendientes de sincronización; este reporte puede no incluirlos todavía.'
                : snapshot.hasPendingLocalCashSales
                    ? 'Hay ventas en efectivo pendientes de sincronización; este reporte puede no incluirlas todavía.'
                    : 'Hay movimientos de caja pendientes de sincronización; este reporte autoritativo puede no incluirlos todavía.')),
        const SizedBox(height: CronosSpacing.sm),
      ],
      _Metric('Entradas de caja', summary.totalInflowsCents,
          key: const Key('cash-flow-inflows')),
      _Metric('Salidas de caja', summary.totalOutflowsCents,
          key: const Key('cash-flow-outflows')),
      _Metric('Flujo neto de caja', summary.netCashFlowCents,
          key: const Key('cash-flow-net')),
      _Metric('Gastos operativos registrados', summary.operatingExpensesCents,
          key: const Key('cash-flow-operating')),
      const SizedBox(height: CronosSpacing.sm),
      _Metric('Ventas en efectivo', summary.cashSalesCents),
      _Metric('Otras entradas de caja', summary.additionalInflowsCents),
      _Metric(
          'Compras de mercancía desde caja', summary.inventoryAcquisitionCents,
          key: const Key('cash-flow-inventory-acquisition')),
      _Metric('Retiros del propietario', summary.ownerWithdrawalsCents,
          key: const Key('cash-flow-owner-withdrawals')),
      _Metric('Otros egresos', summary.otherOutflowsCents,
          key: const Key('cash-flow-other-outflows')),
      if (categoryTotals.isNotEmpty) ...[
        const SizedBox(height: CronosSpacing.sm),
        Text('Detalle de salidas',
            style: Theme.of(context).textTheme.titleMedium),
        for (final category in CashMovementCategoryMetadata.byCode.values)
          if (categoryTotals[category.code] case final total?)
            if (total.totalCents > BigInt.zero)
              _Metric(category.displayLabel, total.totalCents),
      ],
      const SizedBox(height: CronosSpacing.sm),
      const Text('La rentabilidad por ventas se consulta en Rentabilidad.'),
      Text('Actualizado ${snapshot.fetchedAt.toLocal()}',
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.cents, {super.key});
  final String label;
  final BigInt cents;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: CronosSpacing.sm),
        child: AppGlassCard(
            child: Row(children: [
          Expanded(child: Text(label)),
          Text(formatSalesReportMoney(cents),
              style: Theme.of(context).textTheme.titleMedium),
        ])),
      );
}

class _Message extends StatelessWidget {
  const _Message(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => AppGlassCard(child: Text(message));
}
