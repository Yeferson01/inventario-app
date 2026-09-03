import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/logging/app_logger.dart';
import '../../application/intentional_stale_sale_reconciliation_service.dart';
import '../../application/productive_stale_sale_reconciliation_service.dart';
import '../../application/unmaterialized_local_sale_discard_service.dart';

enum _SaleRealityDecision { occurred, didNotOccur, later }

enum _MissingDestinationDecision { openCash, later }

typedef ProductiveDialogVisibilityChanged = void Function(bool visible);
typedef ProductiveCashRepairAction = Future<void> Function({
  required String saleId,
  required String originalCashSessionId,
  required String cashRegisterId,
});

class ProductiveStaleSaleReconciliationPresenter {
  const ProductiveStaleSaleReconciliationPresenter._();

  static final Map<String, Future<void>> _inFlightBySale = {};

  static Future<void> show({
    required BuildContext context,
    required ProductiveStaleSaleReconciliationController service,
    required String profileId,
    required String businessId,
    required String branchId,
    required String appDeviceId,
    required Set<String> effectivePermissions,
    required ProductiveCashRepairAction onOpenCash,
    ProductiveCashRepairAction? onRefreshCashContext,
    ProductiveDialogVisibilityChanged? onDialogVisibilityChanged,
    Color? dialogBarrierColor,
  }) async {
    while (context.mounted) {
      late final List<StaleSaleResolutionCandidate> pending;
      try {
        pending = await service.loadPending(
          profileId: profileId,
          businessId: businessId,
          branchId: branchId,
        );
      } catch (error, stackTrace) {
        AppLogger.error(
          'Productive stale Sale candidates could not be loaded',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          await _message(
            context,
            'No se pudieron cargar las ventas pendientes',
            'Actualice el estado e intente nuevamente.',
            onDialogVisibilityChanged: onDialogVisibilityChanged,
            barrierColor: dialogBarrierColor,
          );
        }
        return;
      }
      if (!context.mounted) return;
      if (pending.isEmpty) return;
      final candidate = pending.first;
      final inFlight = _inFlightBySale[candidate.saleId];
      if (inFlight != null) {
        await inFlight;
        continue;
      }
      final authorizedToReconcile = effectivePermissions.contains(
            'sales.reconcile_stale_cash_session',
          ) &&
          effectivePermissions.contains('sales.create');
      final decision = await _askReality(
        context,
        candidate,
        pending.length,
        authorizedToReconcile,
        onDialogVisibilityChanged: onDialogVisibilityChanged,
        barrierColor: dialogBarrierColor,
      );
      if (decision == null || decision == _SaleRealityDecision.later) return;
      if (!context.mounted) return;

      Completer<void>? operation;
      Future<void>? operationFuture;
      try {
        if (decision == _SaleRealityDecision.didNotOccur) {
          final confirmed = await _confirmDiscard(
            context,
            candidate,
            onDialogVisibilityChanged: onDialogVisibilityChanged,
            barrierColor: dialogBarrierColor,
          );
          if (!context.mounted || !confirmed) return;
          final claim = _claimTerminalOperation(candidate.saleId);
          if (claim.completer == null) {
            await claim.future;
            continue;
          }
          operation = claim.completer;
          operationFuture = claim.future;
          final discard = await service.discardDidNotOccur(
            profileId: profileId,
            appDeviceId: appDeviceId,
            candidate: candidate,
          );
          if (!context.mounted) return;
          final remaining = await _reloadAfterTerminalAction(
            service: service,
            profileId: profileId,
            businessId: businessId,
            branchId: branchId,
            targetSaleId: candidate.saleId,
          );
          if (!context.mounted) return;
          _success(
            context,
            discard.localResult.alreadyDiscarded
                ? 'La venta ya estaba retirada y auditada.'
                : 'La venta no ocurrida fue retirada y auditada.',
          );
          if (remaining.isEmpty) return;
          continue;
        }

        if (!authorizedToReconcile) {
          await _message(
            context,
            'Usuario autorizado requerido',
            'No tiene permiso para reconciliar esta venta.',
            onDialogVisibilityChanged: onDialogVisibilityChanged,
            barrierColor: dialogBarrierColor,
          );
          return;
        }

        await onRefreshCashContext?.call(
          saleId: candidate.saleId,
          originalCashSessionId: candidate.originalCashSessionId,
          cashRegisterId: candidate.cashRegisterId,
        );
        var destination = _validDestination(
          candidate,
          await service.resolveOpenDestination(candidate),
        );
        if (destination == null) {
          if (!context.mounted) return;
          final missing = await _askOpenCash(
            context,
            onDialogVisibilityChanged: onDialogVisibilityChanged,
            barrierColor: dialogBarrierColor,
          );
          if (missing != _MissingDestinationDecision.openCash) return;
          await onOpenCash(
            saleId: candidate.saleId,
            originalCashSessionId: candidate.originalCashSessionId,
            cashRegisterId: candidate.cashRegisterId,
          );
          destination = _validDestination(
            candidate,
            await service.resolveOpenDestination(candidate),
          );
          if (destination == null) return;
        }

        if (!context.mounted) return;
        final treatment = candidate.cashTotal > 0
            ? await _askCashTreatment(
                context,
                onDialogVisibilityChanged: onDialogVisibilityChanged,
                barrierColor: dialogBarrierColor,
              )
            : IntentionalStaleSaleCashTreatment.notIncludedInDestinationOpening;
        if (treatment == null || !context.mounted) return;
        final preview = await service.previewOccurred(
          candidate: candidate,
          destinationCashSessionId: destination,
          cashTreatment: treatment,
        );
        if (!context.mounted) return;
        final confirmed = await _confirmOccurred(
          context,
          candidate,
          preview,
          onDialogVisibilityChanged: onDialogVisibilityChanged,
          barrierColor: dialogBarrierColor,
        );
        if (!context.mounted || !confirmed) return;
        final claim = _claimTerminalOperation(candidate.saleId);
        if (claim.completer == null) {
          await claim.future;
          continue;
        }
        operation = claim.completer;
        operationFuture = claim.future;
        await _withProgress(
          context,
          onDialogVisibilityChanged: onDialogVisibilityChanged,
          barrierColor: dialogBarrierColor,
          action: () => service.reconcileDidOccur(
            profileId: profileId,
            appDeviceId: appDeviceId,
            effectivePermissions: effectivePermissions,
            candidate: candidate,
            destinationCashSessionId: destination!,
            cashTreatment: treatment,
          ),
        );
        if (!context.mounted) return;
        final remaining = await _reloadAfterTerminalAction(
          service: service,
          profileId: profileId,
          businessId: businessId,
          branchId: branchId,
          targetSaleId: candidate.saleId,
        );
        if (!context.mounted) return;
        _success(context, 'La venta real fue reconciliada correctamente.');
        if (remaining.isEmpty) return;
      } catch (error, stackTrace) {
        AppLogger.error(
          'Productive stale Sale reconciliation failed',
          error: error,
          stackTrace: stackTrace,
        );
        if (context.mounted) {
          await _message(
            context,
            'No se pudo resolver la venta',
            _friendlyError(error),
            onDialogVisibilityChanged: onDialogVisibilityChanged,
            barrierColor: dialogBarrierColor,
          );
        }
        return;
      } finally {
        final ownedOperation = operation;
        final ownedFuture = operationFuture;
        if (ownedOperation != null && ownedFuture != null) {
          if (!ownedOperation.isCompleted) ownedOperation.complete();
          if (identical(_inFlightBySale[candidate.saleId], ownedFuture)) {
            final removed = _inFlightBySale.remove(candidate.saleId);
            assert(identical(removed, ownedFuture));
          }
        }
      }
    }
  }

  static ({Completer<void>? completer, Future<void> future})
      _claimTerminalOperation(String saleId) {
    final existing = _inFlightBySale[saleId];
    if (existing != null) return (completer: null, future: existing);
    final completer = Completer<void>();
    final future = completer.future;
    _inFlightBySale[saleId] = future;
    return (completer: completer, future: future);
  }

  static String? _validDestination(
    StaleSaleResolutionCandidate candidate,
    String? destinationCashSessionId,
  ) {
    final destination = destinationCashSessionId?.trim();
    if (destination == null ||
        destination.isEmpty ||
        destination == candidate.originalCashSessionId) {
      return null;
    }
    return destination;
  }

  static Future<List<StaleSaleResolutionCandidate>> _reloadAfterTerminalAction({
    required ProductiveStaleSaleReconciliationController service,
    required String profileId,
    required String businessId,
    required String branchId,
    required String targetSaleId,
  }) async {
    final remaining = await service.loadPending(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
    );
    if (remaining.any((sale) => sale.saleId == targetSaleId)) {
      throw StateError(
        'La venta objetivo continúa pendiente después de la resolución.',
      );
    }
    return remaining;
  }

  static Future<_SaleRealityDecision?> _askReality(
    BuildContext context,
    StaleSaleResolutionCandidate candidate,
    int pendingCount,
    bool canReconcile, {
    ProductiveDialogVisibilityChanged? onDialogVisibilityChanged,
    Color? barrierColor,
  }) {
    final payments =
        candidate.payments.map((payment) => payment.method).toSet().join(', ');
    final items = candidate.items
        .map((item) => '${item.productName} × ${item.quantity}')
        .join('\n');
    return _showDialog<_SaleRealityDecision>(
      context: context,
      onDialogVisibilityChanged: onDialogVisibilityChanged,
      barrierColor: barrierColor,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          pendingCount == 1
              ? 'Venta pendiente de reconciliación'
              : '$pendingCount ventas pendientes de reconciliación',
        ),
        content: SingleChildScrollView(
          child: Text(
            'Esta venta no pudo sincronizarse porque la caja original ya '
            'estaba cerrada.\n\n¿La venta ocurrió realmente?\n\n'
            'Total: ${_money(candidate.total)}\n'
            'Fecha: ${candidate.createdAt.toLocal()}\n'
            'Pagos: ${payments.isEmpty ? 'Sin pagos' : payments}\n'
            'Productos:\n${items.isEmpty ? 'Sin items' : items}\n'
            'Sesión original: caja cerrada\n'
            'Sucursal: ${candidate.branchName}'
            '${canReconcile ? '' : '\n\nLa opción “Sí ocurrió” requiere un usuario autorizado.'}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _SaleRealityDecision.later,
            ),
            child: const Text('Resolver después'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _SaleRealityDecision.didNotOccur,
            ),
            child: const Text('No, no ocurrió'),
          ),
          if (canReconcile)
            FilledButton(
              onPressed: () => Navigator.pop(
                dialogContext,
                _SaleRealityDecision.occurred,
              ),
              child: const Text('Sí, ocurrió'),
            ),
        ],
      ),
    );
  }

  static Future<bool> _confirmDiscard(
    BuildContext context,
    StaleSaleResolutionCandidate candidate, {
    ProductiveDialogVisibilityChanged? onDialogVisibilityChanged,
    Color? barrierColor,
  }) async {
    return await _showDialog<bool>(
          context: context,
          onDialogVisibilityChanged: onDialogVisibilityChanged,
          barrierColor: barrierColor,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Confirmar que la venta NO ocurrió'),
            content: Text(
              'Use esta opción únicamente si no recibió dinero y no entregó '
              'productos.\n\nEl stock de ${candidate.items.length} producto(s) '
              'será restaurado de forma auditada.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Resolver después'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirmo: la venta NO ocurrió'),
              ),
            ],
          ),
        ) ??
        false;
  }

  static Future<_MissingDestinationDecision?> _askOpenCash(
    BuildContext context, {
    ProductiveDialogVisibilityChanged? onDialogVisibilityChanged,
    Color? barrierColor,
  }) {
    return _showDialog<_MissingDestinationDecision>(
      context: context,
      onDialogVisibilityChanged: onDialogVisibilityChanged,
      barrierColor: barrierColor,
      builder: (dialogContext) => AlertDialog(
        title: const Text('No hay una caja abierta'),
        content: const Text(
          'No hay una caja abierta donde contabilizar esta venta.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _MissingDestinationDecision.later,
            ),
            child: const Text('Resolver después'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              _MissingDestinationDecision.openCash,
            ),
            child: const Text('Abrir caja'),
          ),
        ],
      ),
    );
  }

  static Future<IntentionalStaleSaleCashTreatment?> _askCashTreatment(
    BuildContext context, {
    ProductiveDialogVisibilityChanged? onDialogVisibilityChanged,
    Color? barrierColor,
  }) {
    return _showDialog<IntentionalStaleSaleCashTreatment>(
      context: context,
      onDialogVisibilityChanged: onDialogVisibilityChanged,
      barrierColor: barrierColor,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tratamiento del efectivo'),
        content: const Text(
          '¿El efectivo de esta venta ya estaba incluido en el monto de '
          'apertura de la caja actual?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Resolver después'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              IntentionalStaleSaleCashTreatment.notIncludedInDestinationOpening,
            ),
            child: const Text('No estaba incluido'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              IntentionalStaleSaleCashTreatment
                  .alreadyIncludedInDestinationOpening,
            ),
            child: const Text('Sí, ya estaba incluido'),
          ),
        ],
      ),
    );
  }

  static Future<bool> _confirmOccurred(
    BuildContext context,
    StaleSaleResolutionCandidate candidate,
    IntentionalStaleSaleReconciliationPreview preview, {
    ProductiveDialogVisibilityChanged? onDialogVisibilityChanged,
    Color? barrierColor,
  }) async {
    final included = preview.cashTreatment ==
        IntentionalStaleSaleCashTreatment.alreadyIncludedInDestinationOpening;
    final stock = candidate.items
        .map((item) => '${item.productName}: -${item.quantity}')
        .join('\n');
    return await _showDialog<bool>(
          context: context,
          onDialogVisibilityChanged: onDialogVisibilityChanged,
          barrierColor: barrierColor,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Confirmar venta real'),
            content: SingleChildScrollView(
              child: Text(
                'Venta total: ${_money(candidate.total)}\n'
                'Efectivo total: ${_money(preview.local.cashTotal)}\n'
                'Caja destino: sesión abierta actual\n'
                'Monto de apertura: ${_money(preview.local.destinationOpeningAmount)}\n\n'
                '${included ? 'Efectivo de la venta: +${_money(preview.local.cashTotal)}\nAjuste: ${_signedMoney(preview.expectedAdjustment)}\nImpacto neto en efectivo: ${_money(0)}' : 'Impacto en efectivo: +${_money(preview.local.cashTotal)}'}\n\n'
                'Impacto de stock ya aplicado localmente:\n$stock',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Resolver después'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Confirmo: la venta SÍ ocurrió'),
              ),
            ],
          ),
        ) ??
        false;
  }

  static Future<void> _message(
    BuildContext context,
    String title,
    String message, {
    ProductiveDialogVisibilityChanged? onDialogVisibilityChanged,
    Color? barrierColor,
  }) {
    return _showDialog<void>(
      context: context,
      onDialogVisibilityChanged: onDialogVisibilityChanged,
      barrierColor: barrierColor,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  static Future<T?> _showDialog<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    ProductiveDialogVisibilityChanged? onDialogVisibilityChanged,
    Color? barrierColor,
  }) async {
    onDialogVisibilityChanged?.call(true);
    try {
      return await showDialog<T>(
        context: context,
        barrierColor: barrierColor,
        builder: builder,
      );
    } finally {
      onDialogVisibilityChanged?.call(false);
    }
  }

  static Future<T> _withProgress<T>(
    BuildContext context, {
    required Future<T> Function() action,
    ProductiveDialogVisibilityChanged? onDialogVisibilityChanged,
    Color? barrierColor,
  }) async {
    if (!context.mounted) return action();
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierColor: barrierColor,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(),
            ),
            SizedBox(width: 16),
            Flexible(child: Text('Reconciliando venta…')),
          ],
        ),
      ),
    );
    onDialogVisibilityChanged?.call(true);
    try {
      final progressDialog = navigator.push<void>(route);
      try {
        return await action();
      } finally {
        final routeNavigator = route.navigator;
        if (route.isActive &&
            routeNavigator != null &&
            routeNavigator.mounted) {
          routeNavigator.removeRoute(route);
        }
        await progressDialog;
      }
    } finally {
      onDialogVisibilityChanged?.call(false);
    }
  }

  static void _success(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static String _friendlyError(Object error) {
    if (error is UnmaterializedSaleDiscardException) {
      return switch (error.kind) {
        UnmaterializedSaleDiscardFailureKind.remoteUnavailable =>
          'No se pudo verificar el estado en el servidor.',
        UnmaterializedSaleDiscardFailureKind.remoteMaterializationFound =>
          'La venta ya tiene información en el servidor y requiere revisión.',
        _ => 'La venta no pudo descartarse de forma segura.',
      };
    }
    if (error is ProductiveStaleSaleException) return error.message;
    if (error is IntentionalStaleSaleReconciliationException) {
      final source = '${error.message} ${error.cause}'.toLowerCase();
      if (source.contains('destination_cash_session_required')) {
        return 'Debe abrir una caja antes de reconciliar esta venta.';
      }
      if (source.contains('closed')) {
        return 'La caja destino ya fue cerrada. Actualice el estado.';
      }
      if (source.contains('permission') || source.contains('42501')) {
        return 'No tiene permiso para reconciliar esta venta.';
      }
      if (source.contains('evidence')) {
        return 'La venta ya tiene información en el servidor y requiere revisión.';
      }
      return 'No se pudo verificar el estado en el servidor.';
    }
    return 'No fue posible completar la reconciliación. Intente actualizar.';
  }

  static String _money(num value) => '\$${value.toStringAsFixed(2)}';

  static String _signedMoney(num value) {
    final sign = value < 0
        ? '-'
        : value > 0
            ? '+'
            : '';
    return '$sign\$${value.abs().toStringAsFixed(2)}';
  }
}
