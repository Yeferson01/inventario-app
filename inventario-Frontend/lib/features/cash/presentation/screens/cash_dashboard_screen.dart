import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../../sync/application/app_router_sync_bootstrap_provider.dart';
import '../../../sync/application/cash_close_sync_trigger_service.dart';
import '../../../sync/application/cash_repair_context_service.dart';
import '../../../sync/application/operational_bootstrap_entry_providers.dart';
import '../../../sync/presentation/productive_error_presentation.dart';
import '../../application/cash_session_local_models.dart';
import '../../application/cash_session_local_provider.dart';
import '../../application/cash_movement_models.dart';
import '../../application/cash_movement_provider.dart';
import '../widgets/cash_metric_tile.dart';
import '../widgets/cash_movement_dialog.dart';
import '../widgets/cash_status_card.dart';
import '../widgets/productive_open_cash_session_dialog.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/app_animated_entrance.dart';
import '../../../../shared/presentation/widgets/app_gradient_background.dart';
import '../../../sync/application/pos_sync_upload_provider.dart';
import '../../../sync/presentation/widgets/productive_stale_sale_reconciliation_presenter.dart';

class CashDashboardScreen extends ConsumerStatefulWidget {
  const CashDashboardScreen({
    super.key,
    required this.businessId,
    required this.branchId,
    required this.profileId,
    required this.cashRegisterId,
    required this.canReadCash,
    required this.canOpenCash,
    required this.canCloseCash,
    this.effectivePermissions = const <String>{},
    this.appDeviceId,
    this.deviceInstallationId,
  });

  final String businessId;
  final String branchId;
  final String profileId;
  final String cashRegisterId;
  final bool canReadCash;
  final bool canOpenCash;
  final bool canCloseCash;
  final Set<String> effectivePermissions;
  final String? appDeviceId;
  final String? deviceInstallationId;

  @override
  ConsumerState<CashDashboardScreen> createState() =>
      _CashDashboardScreenState();
}

class _CashDashboardScreenState extends ConsumerState<CashDashboardScreen> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _readiness;
  ProductiveErrorPresentation? _error;
  bool _isLoading = false;
  bool _isRunningAction = false;
  String? _runningAction;
  int _pendingStaleSales = 0;

  bool get _isBusy => _isLoading || _isRunningAction;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final service = ref.read(cashSessionLocalServiceProvider);

      Map<String, dynamic>? summary;

      try {
        summary = await service.getLatestCashSessionSummaryForBranch(
          businessId: widget.businessId,
          branchId: widget.branchId,
        );
      } on StateError {
        summary = null;
      }

      final readiness = await service.getPosCashReadinessSummary(
        businessId: widget.businessId,
        branchId: widget.branchId,
      );
      final pending = await ref
          .read(productiveStaleSaleReconciliationServiceProvider)
          .loadPending(
            profileId: widget.profileId,
            businessId: widget.businessId,
            branchId: widget.branchId,
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _summary = summary;
        _readiness = readiness;
        _pendingStaleSales = pending.length;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'Productive cash state could not be loaded',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _error = ProductiveErrorPresentation.forCategory(
          ProductiveErrorCategory.contextNotReady,
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openCashSessionDialog() async {
    final suggestedOpeningAmount = suggestedProductiveOpeningAmount(_summary);

    final result = await showDialog<ProductiveOpenCashDialogResult>(
      context: context,
      builder: (_) {
        return ProductiveOpenCashSessionDialog(
          suggestedOpeningAmount: suggestedOpeningAmount,
        );
      },
    );

    if (result == null) {
      return;
    }

    await _runAction(
      actionCode: 'open',
      successMessage: 'Caja abierta localmente.',
      action: () async {
        final service = ref.read(cashSessionLocalServiceProvider);

        await service.openCashSession(
          OpenCashSessionInput(
            businessId: widget.businessId,
            branchId: widget.branchId,
            profileId: widget.profileId,
            cashRegisterId: widget.cashRegisterId,
            openingCashAmount: result.openingAmount,
            appDeviceId: widget.appDeviceId,
            deviceInstallationId: widget.deviceInstallationId,
            metadata: {
              'source': 'cash_dashboard_screen',
              'flow': 'open_cash_session',
            },
          ),
        );
      },
    );
  }

  Future<void> _closeCashSessionDialog() async {
    final summary = _summary;
    final expected = _num(summary?['calculated_expected_cash_amount']);

    final result = await showDialog<_CloseCashDialogResult>(
      context: context,
      builder: (_) {
        return _CloseCashSessionDialog(
          expectedCashAmount: expected,
        );
      },
    );

    if (result == null) {
      return;
    }

    ProductiveCashCloseResult? closeResult;

    await _runAction(
      actionCode: 'close',
      successMessage: 'Caja cerrada.',
      action: () async {
        closeResult = await ref
            .read(cashCloseSyncTriggerServiceProvider)
            .closeCashSession(
              CloseCashSessionInput(
                businessId: widget.businessId,
                branchId: widget.branchId,
                profileId: widget.profileId,
                actualClosingAmount: result.actualClosingAmount,
                appDeviceId: widget.appDeviceId,
                deviceInstallationId: widget.deviceInstallationId,
                notes: result.notes,
              ),
            );
      },
    );

    if (!mounted || closeResult == null) {
      return;
    }

    final hasNonCriticalPending =
        closeResult!.nonCriticalPendingDomains.isNotEmpty;

    if (hasNonCriticalPending) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Hay operaciones pendientes'),
          content: const Text(
            'La caja se cerró correctamente. Algunas operaciones no '
            'relacionadas con el cierre siguen pendientes y podrán '
            'reintentarse después.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
    }
    if (mounted) await _openPendingStaleSales();
  }

  Future<void> _openCashMovementDialog(CashMovementDirection direction) async {
    if (_isBusy) return;
    final permission = direction == CashMovementDirection.outflow
        ? 'cash.disburse'
        : 'cash.receive';
    final summary = _summary;
    final sessionId = summary?['cash_session_id']?.toString();
    if (!widget.effectivePermissions.contains(permission) ||
        summary?['status'] != 'open' ||
        summary?['cash_register_id'] != widget.cashRegisterId ||
        sessionId == null ||
        sessionId.isEmpty) {
      return;
    }
    final service = ref.read(cashMovementServiceProvider);
    final recorded = await showDialog<bool>(
      context: context,
      builder: (_) => CashMovementDialog(
        profileId: widget.profileId,
        businessId: widget.businessId,
        branchId: widget.branchId,
        cashRegisterId: widget.cashRegisterId,
        cashSessionId: sessionId,
        direction: direction,
        loadExpectedCashCents: () => service.loadExpectedCashCents(
          profileId: widget.profileId,
          businessId: widget.businessId,
          branchId: widget.branchId,
          cashRegisterId: widget.cashRegisterId,
          cashSessionId: sessionId,
          direction: direction,
        ),
        submit: service.recordMovement,
      ),
    );
    if (recorded != true || !mounted) return;
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Movimiento registrado en el dispositivo.'),
    ));
  }

  Future<void> _openPendingStaleSales() async {
    final appDeviceId = widget.appDeviceId?.trim();
    if (appDeviceId == null || appDeviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Actualice el contexto antes de resolver ventas pendientes.',
          ),
        ),
      );
      return;
    }
    await ProductiveStaleSaleReconciliationPresenter.show(
      context: context,
      service: ref.read(productiveStaleSaleReconciliationServiceProvider),
      profileId: widget.profileId,
      businessId: widget.businessId,
      branchId: widget.branchId,
      appDeviceId: appDeviceId,
      effectivePermissions: widget.effectivePermissions,
      onRefreshCashContext: ({
        required saleId,
        required originalCashSessionId,
        required cashRegisterId,
      }) async {
        await _refreshCashForStaleSale(
          saleId: saleId,
          originalCashSessionId: originalCashSessionId,
          cashRegisterId: cashRegisterId,
        );
      },
      onOpenCash: ({
        required saleId,
        required originalCashSessionId,
        required cashRegisterId,
      }) =>
          _openCashSessionDialog(),
    );
    await _load();
  }

  Future<CashRepairContextResult> _refreshCashForStaleSale({
    required String saleId,
    required String originalCashSessionId,
    required String cashRegisterId,
  }) {
    final installationId = widget.deviceInstallationId?.trim();
    final appDeviceId = widget.appDeviceId?.trim();
    if (installationId == null ||
        installationId.isEmpty ||
        appDeviceId == null ||
        appDeviceId.isEmpty) {
      throw const CashRepairContextException(
        'El contexto de instalación no está disponible para reparar caja.',
      );
    }
    return ref.read(cashRepairContextServiceProvider).refresh(
          CashRepairContextRequest(
            profileId: widget.profileId,
            businessId: widget.businessId,
            branchId: widget.branchId,
            installationId: installationId,
            appDeviceId: appDeviceId,
            cashRegisterId: cashRegisterId,
            originalCashSessionId: originalCashSessionId,
            saleId: saleId,
            effectivePermissions: widget.effectivePermissions,
          ),
        );
  }

  Future<void> _runAction({
    required String actionCode,
    String? successMessage,
    required Future<void> Function() action,
  }) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isRunningAction = true;
      _runningAction = actionCode;
      _error = null;
    });

    try {
      await action();
      await _load();

      if (!mounted) {
        return;
      }

      if (successMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } on CashCloseSyncBlockedException catch (error, stackTrace) {
      AppLogger.warning(
        'Productive cash close was blocked safely',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;

      final category =
          error.reason == CashCloseSyncBlockReason.requiresAttention
              ? ProductiveErrorCategory.needsAttention
              : ProductiveErrorCategory.retryable;
      setState(() {
        _error = ProductiveErrorPresentation.forCategory(category);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Productive cash action failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) {
        return;
      }

      final copy = ProductiveErrorPresentation.forCategory(
        ProductiveErrorCategory.retryable,
      );
      setState(() {
        _error = copy;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${copy.title}. ${copy.message}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRunningAction = false;
          _runningAction = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final readiness = _readiness;

    return Theme(
      data: CronosTheme.light(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Caja'),
          actions: [
            if (widget.canReadCash)
              IconButton(
                onPressed: _isBusy ? null : _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'Actualizar',
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Centro de caja',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: CronosSpacing.xs),
                      Text(
                        'Controla apertura, cierre, sincronización y resumen de efectivo.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: CronosSpacing.md),
                if (_isBusy) const LinearProgressIndicator(),
                if (_error != null) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _error!.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(_error!.message),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _isBusy ? null : _load,
                            child: Text(_error!.actionLabel),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.canReadCash) ...[
                  CashStatusCard(
                    summary: summary,
                    readiness: _cashReadinessForPresentation(readiness),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_pendingStaleSales > 0) ...[
                  Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.warning_amber_outlined),
                      title: Text(
                        _pendingStaleSales == 1
                            ? '1 venta pendiente de revisión'
                            : '$_pendingStaleSales ventas pendientes de revisión',
                      ),
                      subtitle: const Text(
                        'La caja original estaba cerrada. Resuélvalas una por una.',
                      ),
                      trailing: FilledButton(
                        onPressed: _isBusy ? null : _openPendingStaleSales,
                        child: const Text('Resolver'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _CashActionsSection(
                  summary: summary,
                  isBusy: _isBusy,
                  isClosing: _runningAction == 'close',
                  allowRead: widget.canReadCash,
                  allowOpen: widget.canOpenCash,
                  allowClose: widget.canCloseCash,
                  allowReceive:
                      widget.effectivePermissions.contains('cash.receive'),
                  allowDisburse:
                      widget.effectivePermissions.contains('cash.disburse'),
                  cashRegisterId: widget.cashRegisterId,
                  onOpenCash: _openCashSessionDialog,
                  onReceive: () => _openCashMovementDialog(
                    CashMovementDirection.inflow,
                  ),
                  onDisburse: () => _openCashMovementDialog(
                    CashMovementDirection.outflow,
                  ),
                  onCloseCash: _closeCashSessionDialog,
                  onRefresh: _load,
                ),
                if (widget.canReadCash) ...[
                  const SizedBox(height: 12),
                  _CashIdentitySection(summary: summary),
                  const SizedBox(height: 12),
                  _CashAmountsSection(summary: summary),
                  const SizedBox(height: 12),
                  _CashSyncSection(readiness: readiness),
                  const SizedBox(height: 12),
                  _PaymentsByMethodSection(summary: summary),
                  const SizedBox(height: 12),
                  _NextActionsSection(summary: summary, readiness: readiness),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CashActionsSection extends StatelessWidget {
  const _CashActionsSection({
    required this.summary,
    required this.isBusy,
    required this.isClosing,
    required this.allowRead,
    required this.allowOpen,
    required this.allowClose,
    required this.allowReceive,
    required this.allowDisburse,
    required this.cashRegisterId,
    required this.onOpenCash,
    required this.onReceive,
    required this.onDisburse,
    required this.onCloseCash,
    required this.onRefresh,
  });

  final Map<String, dynamic>? summary;
  final bool isBusy;
  final bool isClosing;
  final bool allowRead;
  final bool allowOpen;
  final bool allowClose;
  final bool allowReceive;
  final bool allowDisburse;
  final String cashRegisterId;
  final VoidCallback onOpenCash;
  final VoidCallback onReceive;
  final VoidCallback onDisburse;
  final VoidCallback onCloseCash;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final status = summary?['status']?.toString();
    final isOpen = status == 'open';
    final isClosed = status == 'closed';
    final canClose = allowClose && isOpen;
    final canOpen = allowOpen && (summary == null || isClosed);
    final canMove = isOpen &&
        summary?['cash_register_id'] == cashRegisterId &&
        (summary?['cash_session_id']?.toString().isNotEmpty ?? false);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: isBusy || !canOpen ? null : onOpenCash,
              icon: const Icon(Icons.lock_open_outlined),
              label: Text(isClosed ? 'Abrir nueva caja' : 'Abrir caja'),
            ),
            FilledButton.icon(
              onPressed: isBusy || !canClose ? null : onCloseCash,
              icon: const Icon(Icons.lock_outline),
              label: Text(isClosing ? 'Cerrando caja…' : 'Cerrar caja'),
            ),
            if (canMove && allowReceive)
              FilledButton.icon(
                onPressed: isBusy ? null : onReceive,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('Registrar entrada'),
              ),
            if (canMove && allowDisburse)
              FilledButton.icon(
                onPressed: isBusy ? null : onDisburse,
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('Gastos y salidas'),
              ),
            if (allowRead)
              OutlinedButton.icon(
                onPressed: isBusy ? null : onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
          ],
        ),
      ),
    );
  }
}

class _CashIdentitySection extends StatelessWidget {
  const _CashIdentitySection({
    required this.summary,
  });

  final Map<String, dynamic>? summary;

  @override
  Widget build(BuildContext context) {
    if (summary == null) {
      return const CashMetricTile(
        label: 'Sesión',
        value: 'Sin sesión local',
        helper: 'Abre una caja para empezar a vender.',
      );
    }

    return Column(
      children: [
        CashMetricTile(
          label: 'Caja',
          value: _text(summary!['cash_register_name'], fallback: 'Sin nombre'),
          helper: _text(summary!['cash_register_code'], fallback: null),
        ),
        CashMetricTile(
          label: 'Sesión',
          value: switch (summary!['status']) {
            'open' => 'Abierta',
            'closed' => 'Cerrada',
            _ => 'Estado no disponible',
          },
        ),
        CashMetricTile(
          label: 'Apertura / cierre',
          value: _cashDate(context, summary!['opened_at'], 'Sin apertura'),
          helper:
              'Cierre: ${_cashDate(context, summary!['closed_at'], 'sin cierre')}',
        ),
      ],
    );
  }
}

class _CashAmountsSection extends StatelessWidget {
  const _CashAmountsSection({
    required this.summary,
  });

  final Map<String, dynamic>? summary;

  @override
  Widget build(BuildContext context) {
    if (summary == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        CashMetricTile(
          label: 'Monto apertura',
          value: _money(summary!['opening_cash_amount']),
        ),
        CashMetricTile(
          label: 'Ventas de la sesión',
          value: _money(summary!['sales_total']),
          helper:
              'Cantidad de ventas: ${_text(summary!['sale_count'], fallback: '0')}',
        ),
        CashMetricTile(
          label: 'Pagos totales',
          value: _money(summary!['total_payments']),
          helper: 'Efectivo: ${_money(summary!['cash_payments'])}',
        ),
        CashMetricTile(
          label: 'Efectivo esperado',
          value: _money(summary!['calculated_expected_cash_amount']),
          helper:
              'Guardado al cierre: ${_money(summary!['stored_expected_cash_amount'])}',
        ),
        CashMetricTile(
          label: 'Monto contado',
          value: _money(summary!['closing_cash_amount']),
          helper: 'Diferencia: ${_money(summary!['difference_amount'])}',
        ),
      ],
    );
  }
}

class _CashSyncSection extends StatelessWidget {
  const _CashSyncSection({
    required this.readiness,
  });

  final Map<String, dynamic>? readiness;

  @override
  Widget build(BuildContext context) {
    if (readiness == null) {
      return const SizedBox.shrink();
    }

    final canUploadPos = readiness!['pos_upload_blocked_reason'] == null;

    return Column(
      children: [
        CashMetricTile(
          label: 'Estado para POS',
          value: canUploadPos ? 'Listo para vender' : 'Ventas no disponibles',
          helper: canUploadPos
              ? null
              : 'Revisa la caja y los cambios pendientes antes de vender.',
        ),
        CashMetricTile(
          label: 'Cambios de caja pendientes',
          value:
              '${_int(readiness!['dirty_cash_register_count']) + _int(readiness!['dirty_cash_session_count'])}',
          helper:
              'Ventas pendientes de revisar: ${_text(readiness!['pending_sales_without_cash_count'], fallback: '0')}',
        ),
      ],
    );
  }
}

class _PaymentsByMethodSection extends StatelessWidget {
  const _PaymentsByMethodSection({
    required this.summary,
  });

  final Map<String, dynamic>? summary;

  @override
  Widget build(BuildContext context) {
    final rows = summary?['payments_by_method'];

    if (rows is! List || rows.isEmpty) {
      return const CashMetricTile(
        label: 'Pagos por método',
        value: 'Sin pagos',
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pagos por método',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              if (row is Map)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _text(row['payment_method'], fallback: 'Otro medio'),
                  ),
                  subtitle: Text(
                    'Pagos: ${_text(row['payment_count'], fallback: '0')}',
                  ),
                  trailing: Text(_money(row['payment_total'])),
                ),
          ],
        ),
      ),
    );
  }
}

class _NextActionsSection extends StatelessWidget {
  const _NextActionsSection({
    required this.summary,
    required this.readiness,
  });

  final Map<String, dynamic>? summary;
  final Map<String, dynamic>? readiness;

  @override
  Widget build(BuildContext context) {
    final status = summary?['status']?.toString();
    final blockedReason = readiness?['pos_upload_blocked_reason'];

    String nextAction;

    if (summary == null) {
      nextAction = 'Abrir caja';
    } else if (status == 'closed') {
      nextAction = 'Abrir nueva caja';
    } else if (blockedReason != null) {
      nextAction = 'Sincronizar caja antes de vender';
    } else {
      nextAction = 'Ir a POS';
    }

    return CashMetricTile(
      label: 'Siguiente acción sugerida',
      value: nextAction,
    );
  }
}

class _CloseCashSessionDialog extends StatefulWidget {
  const _CloseCashSessionDialog({
    required this.expectedCashAmount,
  });

  final double expectedCashAmount;

  @override
  State<_CloseCashSessionDialog> createState() =>
      _CloseCashSessionDialogState();
}

class _CloseCashSessionDialogState extends State<_CloseCashSessionDialog> {
  late final TextEditingController _amountController;
  late final TextEditingController _notesController;

  @override
  void initState() {
    super.initState();

    _amountController = TextEditingController(
      text: widget.expectedCashAmount.toStringAsFixed(2),
    );
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _notesController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cerrar caja'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CashMetricTile(
            label: 'Efectivo esperado',
            value: _money(widget.expectedCashAmount),
            helper: 'Apertura + pagos en efectivo.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            decoration: const InputDecoration(
              labelText: 'Monto contado',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesController,
            decoration: const InputDecoration(
              labelText: 'Notas',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(_amountController.text.trim());

            if (amount == null || amount < 0) {
              return;
            }

            Navigator.of(context).pop(
              _CloseCashDialogResult(
                actualClosingAmount: amount,
                notes: _notesController.text.trim().isEmpty
                    ? null
                    : _notesController.text.trim(),
              ),
            );
          },
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}

Map<String, dynamic>? _cashReadinessForPresentation(
  Map<String, dynamic>? readiness,
) {
  if (readiness == null) return null;
  final blockedReason = readiness['pos_upload_blocked_reason'];
  if (blockedReason == null) return readiness;
  return {
    ...readiness,
    'pos_upload_blocked_reason':
        'Hay operaciones de caja pendientes de revisión.',
  };
}

class _CloseCashDialogResult {
  const _CloseCashDialogResult({
    required this.actualClosingAmount,
    this.notes,
  });

  final double actualClosingAmount;
  final String? notes;
}

String _money(Object? value) {
  if (value == null) {
    return r'$0.00';
  }

  final number = value is num ? value : num.tryParse(value.toString()) ?? 0;

  return '\$${number.toStringAsFixed(2)}';
}

String _text(Object? value, {required String? fallback}) {
  final text = value?.toString().trim();

  if (text == null || text.isEmpty) {
    return fallback ?? '';
  }

  return text;
}

String _cashDate(BuildContext context, Object? value, String fallback) {
  final date =
      value is DateTime ? value : DateTime.tryParse(value?.toString() ?? '');
  if (date == null) return fallback;
  final local = date.toLocal();
  final localization = MaterialLocalizations.of(context);
  final day = localization.formatMediumDate(local);
  final time = localization.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
  );
  return '$day · $time';
}

double _num(Object? value) {
  if (value is double) {
    return value;
  }

  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _int(Object? value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value?.toString() ?? '') ?? 0;
}
