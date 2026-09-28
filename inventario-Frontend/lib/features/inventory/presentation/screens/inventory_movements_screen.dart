import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../../sync/application/app_context_models.dart';
import '../../application/inventory_history_controller.dart';
import '../../application/inventory_valuation_models.dart';
import '../../data/models/inventory_history_models.dart';

class InventoryMovementsScreen extends ConsumerWidget {
  const InventoryMovementsScreen({
    super.key,
    required this.appContext,
    this.branchName,
    this.productId,
    this.productName,
    this.productBarcode,
  });

  final AppCurrentContext appContext;
  final String? branchName;

  /// When present, the screen becomes the Product Timeline while continuing
  /// to use the branch-wide History hydration contract.
  final String? productId;
  final String? productName;
  final String? productBarcode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = InventoryHistoryViewRequest(
      context: appContext,
      productId: productId,
    );
    final provider = inventoryHistoryControllerProvider(request);
    final state = ref.watch(provider);
    final controller = ref.read(provider.notifier);

    final firstRow = state.rows.isEmpty ? null : state.rows.first;
    final resolvedProductName = _normalized(productName) ??
        _normalized(firstRow?.productName) ??
        (productId == null ? null : 'Producto no disponible');
    final resolvedProductBarcode =
        _normalized(productBarcode) ?? _normalized(firstRow?.productBarcode);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              productId == null ? 'Movimientos' : 'Movimientos del producto',
            ),
            if (_normalized(branchName) case final value?)
              Text(
                value,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        actions: [
          IconButton(
            key: const Key('inventory-history-refresh'),
            tooltip: 'Actualizar',
            onPressed: state.isRefreshing
                ? null
                : () => unawaited(controller.refresh()),
            icon: state.isRefreshing
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.isRefreshing && state.rows.isNotEmpty)
            const LinearProgressIndicator(
              key: Key('inventory-history-refresh-progress'),
            ),
          if (state.isOffline)
            const _HistoryNotice(
              key: Key('inventory-history-offline-banner'),
              icon: Icons.cloud_off_outlined,
              message: 'Sin conexión · mostrando historial guardado.',
            ),
          if (state.notice case final notice?)
            _HistoryNotice(
              key: const Key('inventory-history-notice'),
              icon: _noticeIcon(notice),
              message: _noticeMessage(notice),
            ),
          Expanded(
            child: _HistoryBody(
              state: state,
              controller: controller,
              productId: productId,
              productName: resolvedProductName,
              productBarcode: resolvedProductBarcode,
              currentDeviceId: appContext.appDeviceId,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({
    required this.state,
    required this.controller,
    required this.productId,
    required this.productName,
    required this.productBarcode,
    required this.currentDeviceId,
  });

  final InventoryHistoryScreenState state;
  final InventoryHistoryController controller;
  final String? productId;
  final String? productName;
  final String? productBarcode;
  final String? currentDeviceId;

  @override
  Widget build(BuildContext context) {
    if (state.phase == InventoryHistoryScreenPhase.initialLoading &&
        state.rows.isEmpty) {
      return const Center(
        key: Key('inventory-history-loading'),
        child: CircularProgressIndicator(),
      );
    }

    if (state.phase == InventoryHistoryScreenPhase.error &&
        state.rows.isEmpty) {
      final denied =
          state.failure == InventoryHistoryScreenFailure.accessDenied;

      return _ScrollableStateMessage(
        key: const Key('inventory-history-error'),
        icon: denied ? Icons.lock_outline : Icons.error_outline,
        title: denied
            ? 'No tienes acceso a movimientos'
            : 'No se pudo cargar el historial',
        message: denied
            ? 'Pídele acceso al administrador del negocio.'
            : 'Vuelve a intentarlo. Tus movimientos guardados no se perderán.',
        actionLabel: denied ? null : 'Reintentar',
        onAction: denied ? null : controller.refresh,
      );
    }

    return RefreshIndicator(
      key: const Key('inventory-history-refresh-indicator'),
      onRefresh: controller.refresh,
      child: ListView(
        key: const Key('inventory-history-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(CronosSpacing.md),
        children: [
          if (productId != null) ...[
            _ProductTimelineHeader(
              name: productName ?? 'Producto no disponible',
              barcode: productBarcode,
            ),
            const SizedBox(height: CronosSpacing.md),
          ],
          _MovementTypeFilter(
            selected: state.effectiveType,
            onChanged: (value) {
              unawaited(controller.setEffectiveType(value));
            },
          ),
          const SizedBox(height: CronosSpacing.md),
          if (state.rows.isEmpty)
            _HistoryEmptyState(
              offline: state.phase == InventoryHistoryScreenPhase.emptyOffline,
              filtered: state.effectiveType != null,
            )
          else
            for (var index = 0; index < state.rows.length; index++) ...[
              _MovementCard(
                key: Key('inventory-history-row-${state.rows[index].id}'),
                entry: state.rows[index],
                canViewCosts: state.canViewCosts,
                currentDeviceId: currentDeviceId,
              ),
              if (index != state.rows.length - 1)
                const SizedBox(height: CronosSpacing.sm),
            ],
          const SizedBox(height: CronosSpacing.md),
          _LoadOlderFooter(
            state: state,
            onLoadOlder: controller.loadOlder,
          ),
          const SizedBox(height: CronosSpacing.md),
        ],
      ),
    );
  }
}

class _ProductTimelineHeader extends StatelessWidget {
  const _ProductTimelineHeader({
    required this.name,
    required this.barcode,
  });

  final String name;
  final String? barcode;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      key: const Key('inventory-history-product-header'),
      child: Row(
        children: [
          ProductImage(
            barcode: barcode,
            size: 56,
            semanticLabel: 'Imagen de $name',
          ),
          const SizedBox(width: CronosSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (_normalized(barcode) case final value?) ...[
                  const SizedBox(height: CronosSpacing.xs),
                  Text(
                    value,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: CronosSpacing.xs),
                Text(
                  'Historial de movimientos del producto',
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

class _MovementTypeFilter extends StatelessWidget {
  const _MovementTypeFilter({
    required this.selected,
    required this.onChanged,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;

  static const _all = '__all__';

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      key: const Key('inventory-history-filter-card'),
      padding: const EdgeInsets.symmetric(
        horizontal: CronosSpacing.md,
        vertical: CronosSpacing.sm,
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list_outlined),
          const SizedBox(width: CronosSpacing.sm),
          Expanded(
            child: Text(
              'Tipo de movimiento',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              key: const Key('inventory-history-type-filter'),
              value: selected ?? _all,
              onChanged: (value) {
                onChanged(value == _all ? null : value);
              },
              items: const [
                DropdownMenuItem(
                  value: _all,
                  child: Text('Todos'),
                ),
                DropdownMenuItem(
                  value: 'sale',
                  child: Text('Ventas'),
                ),
                DropdownMenuItem(
                  value: 'purchase',
                  child: Text('Compras'),
                ),
                DropdownMenuItem(
                  value: 'manual_adjustment',
                  child: Text('Ajustes'),
                ),
                DropdownMenuItem(
                  value: 'initial_stock',
                  child: Text('Stock inicial'),
                ),
                DropdownMenuItem(
                  value: 'transfer',
                  child: Text('Transferencias'),
                ),
                DropdownMenuItem(
                  value: 'stock_count',
                  child: Text('Conteos'),
                ),
                DropdownMenuItem(
                  value: 'loss',
                  child: Text('Pérdidas'),
                ),
                DropdownMenuItem(
                  value: 'return',
                  child: Text('Devoluciones'),
                ),
                DropdownMenuItem(
                  value: 'reversal',
                  child: Text('Reversiones'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MovementCard extends StatelessWidget {
  const _MovementCard({
    super.key,
    required this.entry,
    required this.canViewCosts,
    required this.currentDeviceId,
  });

  final InventoryMovementHistoryEntry entry;
  final bool canViewCosts;
  final String? currentDeviceId;

  @override
  Widget build(BuildContext context) {
    final presentation = _movementPresentation(entry.effectiveType);
    final productName =
        _normalized(entry.productName) ?? 'Producto no disponible';
    final barcode = _normalized(entry.productBarcode);

    return AppGlassCard(
      onTap: () {
        unawaited(
          _showMovementDetails(
            context,
            entry: entry,
            canViewCosts: canViewCosts,
            currentDeviceId: currentDeviceId,
          ),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductImage(
            barcode: barcode,
            semanticLabel: 'Imagen de $productName',
          ),
          const SizedBox(width: CronosSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (barcode != null) ...[
                  const SizedBox(height: CronosSpacing.xs),
                  Text(
                    barcode,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: CronosSpacing.sm),
                Wrap(
                  spacing: CronosSpacing.sm,
                  runSpacing: CronosSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      avatar: Icon(
                        presentation.icon,
                        size: 18,
                      ),
                      label: Text(presentation.label),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    Text(
                      _formatDateTime(context, entry.occurredAt),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
                if (_stockSummary(entry) case final summary?) ...[
                  const SizedBox(height: CronosSpacing.sm),
                  Text(
                    summary,
                    key: Key('inventory-history-stock-${entry.id}'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (canViewCosts) ...[
                  const SizedBox(height: CronosSpacing.xs),
                  Text(
                    _formatUnitCost(entry.unitCost),
                    key: Key('inventory-history-cost-${entry.id}'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CronosSpacing.sm),
          Text(
            _formatDelta(entry.quantityDelta),
            key: Key('inventory-history-delta-${entry.id}'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: _deltaColor(context, entry.quantityDelta),
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState({
    required this.offline,
    required this.filtered,
  });

  final bool offline;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final title = offline
        ? 'Historial no disponible sin conexión'
        : filtered
            ? 'Sin movimientos de este tipo'
            : 'Sin movimientos';

    final message = offline
        ? 'Conéctate para descargar el historial de esta sucursal.'
        : filtered
            ? 'No hay movimientos guardados que coincidan con este filtro.'
            : 'Aún no hay movimientos de inventario disponibles.';

    return Padding(
      key: const Key('inventory-history-empty'),
      padding: const EdgeInsets.symmetric(vertical: CronosSpacing.xl),
      child: Column(
        children: [
          Icon(
            offline ? Icons.cloud_off_outlined : Icons.timeline_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: CronosSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: CronosSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _LoadOlderFooter extends StatelessWidget {
  const _LoadOlderFooter({
    required this.state,
    required this.onLoadOlder,
  });

  final InventoryHistoryScreenState state;
  final Future<void> Function() onLoadOlder;

  @override
  Widget build(BuildContext context) {
    if (state.isLoadingOlder) {
      return const Center(
        key: Key('inventory-history-loading-older'),
        child: Padding(
          padding: EdgeInsets.all(CronosSpacing.md),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!state.canLoadOlder) {
      if (state.rows.isEmpty) {
        return const SizedBox.shrink();
      }

      return Padding(
        key: const Key('inventory-history-end'),
        padding: const EdgeInsets.all(CronosSpacing.sm),
        child: Text(
          'No hay movimientos anteriores por cargar.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return Center(
      child: OutlinedButton.icon(
        key: const Key('inventory-history-load-older'),
        onPressed: () => unawaited(onLoadOlder()),
        icon: const Icon(Icons.history),
        label: const Text('Cargar anteriores'),
      ),
    );
  }
}

class _HistoryNotice extends StatelessWidget {
  const _HistoryNotice({
    super.key,
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: CronosSpacing.md,
          vertical: CronosSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: CronosSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScrollableStateMessage extends StatelessWidget {
  const _ScrollableStateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final Future<void> Function()? onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(CronosSpacing.xl),
      children: [
        const SizedBox(height: CronosSpacing.xl),
        Icon(
          icon,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: CronosSpacing.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: CronosSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: CronosSpacing.md),
          Center(
            child: FilledButton(
              onPressed: () => unawaited(onAction!()),
              child: Text(actionLabel!),
            ),
          ),
        ],
      ],
    );
  }
}

Future<void> _showMovementDetails(
  BuildContext context, {
  required InventoryMovementHistoryEntry entry,
  required bool canViewCosts,
  required String? currentDeviceId,
}) {
  final presentation = _movementPresentation(entry.effectiveType);
  final productName =
      _normalized(entry.productName) ?? 'Producto no disponible';

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            CronosSpacing.lg,
            0,
            CronosSpacing.lg,
            CronosSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(presentation.icon),
                  const SizedBox(width: CronosSpacing.sm),
                  Expanded(
                    child: Text(
                      presentation.label,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  Text(
                    _formatDelta(entry.quantityDelta),
                    style:
                        Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                              color: _deltaColor(
                                sheetContext,
                                entry.quantityDelta,
                              ),
                              fontWeight: FontWeight.w800,
                            ),
                  ),
                ],
              ),
              const SizedBox(height: CronosSpacing.md),
              _DetailRow(
                label: 'Producto',
                value: productName,
              ),
              if (_normalized(entry.productBarcode) case final barcode?)
                _DetailRow(
                  label: 'Código',
                  value: barcode,
                ),
              _DetailRow(
                label: 'Fecha',
                value: _formatDateTime(sheetContext, entry.occurredAt),
              ),
              _DetailRow(
                label: 'Stock anterior',
                value: entry.previousStock?.toString() ?? 'No disponible',
              ),
              _DetailRow(
                label: 'Stock resultante',
                value: entry.newStock?.toString() ?? 'No disponible',
              ),
              if (canViewCosts)
                _DetailRow(
                  label: 'Costo unitario',
                  value: entry.unitCost == null
                      ? 'Costo no disponible'
                      : _formatMoney(entry.unitCost!),
                ),
              if (_normalized(entry.sourceType) case final source?)
                _DetailRow(
                  label: 'Origen',
                  value: _humanize(source),
                ),
              if (_normalized(entry.referenceType) case final reference?)
                _DetailRow(
                  label: 'Referencia',
                  value: _humanize(reference),
                ),
              if (entry.createdBy != null)
                const _DetailRow(
                  label: 'Registrado por',
                  value: 'Usuario autorizado',
                ),
              if (entry.deviceId != null)
                _DetailRow(
                  label: 'Dispositivo',
                  value: entry.deviceId == currentDeviceId
                      ? 'Este dispositivo'
                      : 'Otro dispositivo',
                ),
              if (entry.reversedMovementId != null)
                const _DetailRow(
                  label: 'Reversión',
                  value: 'Este movimiento revierte un movimiento anterior.',
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CronosSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }
}

class _MovementPresentation {
  const _MovementPresentation({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;
}

_MovementPresentation _movementPresentation(String effectiveType) {
  switch (effectiveType.trim().toLowerCase()) {
    case 'sale':
      return const _MovementPresentation(
        label: 'Venta',
        icon: Icons.shopping_cart_outlined,
      );
    case 'purchase':
      return const _MovementPresentation(
        label: 'Compra',
        icon: Icons.local_shipping_outlined,
      );
    case 'manual_adjustment':
      return const _MovementPresentation(
        label: 'Ajuste manual',
        icon: Icons.tune,
      );
    case 'initial_stock':
      return const _MovementPresentation(
        label: 'Stock inicial',
        icon: Icons.inventory_2_outlined,
      );
    case 'transfer':
      return const _MovementPresentation(
        label: 'Transferencia',
        icon: Icons.swap_horiz_outlined,
      );
    case 'stock_count':
      return const _MovementPresentation(
        label: 'Conteo de stock',
        icon: Icons.fact_check_outlined,
      );
    case 'reversal':
      return const _MovementPresentation(
        label: 'Reversión',
        icon: Icons.undo_outlined,
      );
    case 'loss':
      return const _MovementPresentation(
        label: 'Pérdida',
        icon: Icons.remove_circle_outline,
      );
    case 'return':
      return const _MovementPresentation(
        label: 'Devolución',
        icon: Icons.assignment_return_outlined,
      );
    default:
      return const _MovementPresentation(
        label: 'Movimiento',
        icon: Icons.history,
      );
  }
}

String _formatDelta(int value) {
  if (value > 0) return '+$value';
  return '$value';
}

Color _deltaColor(BuildContext context, int value) {
  final colors = Theme.of(context).colorScheme;

  if (value < 0) {
    return colors.error;
  }

  if (value > 0) {
    return colors.primary;
  }

  return colors.onSurfaceVariant;
}

String? _stockSummary(InventoryMovementHistoryEntry entry) {
  final previous = entry.previousStock;
  final next = entry.newStock;

  if (previous != null && next != null) {
    return 'Stock: $previous → $next';
  }

  if (previous != null) {
    return 'Stock anterior: $previous';
  }

  if (next != null) {
    return 'Stock resultante: $next';
  }

  return null;
}

String _formatUnitCost(double? value) {
  if (value == null) {
    return 'Costo: no disponible';
  }

  return 'Costo: ${_formatMoney(value)}';
}

String _formatMoney(double value) {
  final cents = BigInt.from((value * 100).round());
  return formatInventoryMoneyCents(cents);
}

String _formatDateTime(BuildContext context, DateTime value) {
  final local = value.toLocal();
  final localizations = MaterialLocalizations.of(context);

  final date = localizations.formatMediumDate(local);
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );

  return '$date · $time';
}

String _humanize(String value) {
  final normalized = value.trim().replaceAll('_', ' ');
  if (normalized.isEmpty) return 'Movimiento';

  return normalized
      .split(RegExp(r'\s+'))
      .map(
        (part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String? _normalized(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) {
    return null;
  }

  return normalized;
}

IconData _noticeIcon(InventoryHistoryScreenNotice notice) {
  switch (notice) {
    case InventoryHistoryScreenNotice.connectionRequired:
      return Icons.cloud_off_outlined;
    case InventoryHistoryScreenNotice.refreshFailed:
    case InventoryHistoryScreenNotice.loadOlderFailed:
      return Icons.warning_amber_rounded;
    case InventoryHistoryScreenNotice.noAdditionalFilteredRows:
      return Icons.filter_alt_off_outlined;
  }
}

String _noticeMessage(InventoryHistoryScreenNotice notice) {
  switch (notice) {
    case InventoryHistoryScreenNotice.connectionRequired:
      return 'Conéctate para cargar movimientos anteriores.';
    case InventoryHistoryScreenNotice.refreshFailed:
      return 'No se pudo actualizar. Se mantiene el historial guardado.';
    case InventoryHistoryScreenNotice.loadOlderFailed:
      return 'No se pudieron cargar movimientos anteriores.';
    case InventoryHistoryScreenNotice.noAdditionalFilteredRows:
      return 'No hubo movimientos de este tipo en la página descargada. '
          'Puedes cargar anteriores nuevamente.';
  }
}
