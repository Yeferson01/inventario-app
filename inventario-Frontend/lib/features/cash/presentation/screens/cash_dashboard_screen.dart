import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../sync/application/cash_sync_upload_provider.dart';
import '../../application/cash_session_local_models.dart';
import '../../application/cash_session_local_provider.dart';
import '../widgets/cash_metric_tile.dart';
import '../widgets/cash_status_card.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/app_animated_entrance.dart';
import '../../../../shared/presentation/widgets/app_gradient_background.dart';

class CashDashboardScreen extends ConsumerStatefulWidget {
  const CashDashboardScreen({
    super.key,
    required this.businessId,
    required this.branchId,
    required this.profileId,
    this.appDeviceId,
    this.deviceInstallationId,
  });

  final String businessId;
  final String branchId;
  final String profileId;
  final String? appDeviceId;
  final String? deviceInstallationId;

  @override
  ConsumerState<CashDashboardScreen> createState() =>
      _CashDashboardScreenState();
}

class _CashDashboardScreenState extends ConsumerState<CashDashboardScreen> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _readiness;
  Object? _error;
  bool _isLoading = false;
  bool _isRunningAction = false;

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

      if (!mounted) {
        return;
      }

      setState(() {
        _summary = summary;
        _readiness = readiness;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
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
    final suggestedOpeningAmount = _suggestedOpeningAmount(_summary);

    final result = await showDialog<_OpenCashDialogResult>(
      context: context,
      builder: (_) {
        return _OpenCashSessionDialog(
          suggestedOpeningAmount: suggestedOpeningAmount,
        );
      },
    );

    if (result == null) {
      return;
    }

    await _runAction(
      successMessage: 'Caja abierta localmente.',
      action: () async {
        final service = ref.read(cashSessionLocalServiceProvider);

        await service.openCashSession(
          OpenCashSessionInput(
            businessId: widget.businessId,
            branchId: widget.branchId,
            profileId: widget.profileId,
            cashRegisterName: result.registerName,
            cashRegisterCode: result.registerCode,
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

  Future<void> _syncCash() async {
    await _runAction(
      successMessage: 'Cash sincronizado.',
      action: () async {
        final outboxService = ref.read(cashSyncOutboxServiceProvider);
        final uploadService = ref.read(cashSyncUploadServiceProvider);

        await outboxService.enqueuePendingCash(
          businessId: widget.businessId,
          branchId: widget.branchId,
          profileId: widget.profileId,
          appDeviceId: widget.appDeviceId,
          deviceInstallationId: widget.deviceInstallationId,
        );

        final uploadResult = await uploadService.uploadPendingCashBatches(
          businessId: widget.businessId,
        );

        if (uploadResult.batchesFailed > 0 || uploadResult.batchesPartial > 0) {
          throw StateError(
            'La sincronización de cash no completó totalmente. '
            'Parciales: ${uploadResult.batchesPartial}, '
            'fallidos: ${uploadResult.batchesFailed}.',
          );
        }
      },
    );
  }

  Future<void> _closeCashSessionDialog() async {
    final summary = _summary;
    final expected = _num(summary?['calculated_expected_cash_amount']);

    final amountController = TextEditingController(
      text: expected.toStringAsFixed(2),
    );
    final notesController = TextEditingController();

    final result = await showDialog<_CloseCashDialogResult>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cerrar caja'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CashMetricTile(
                label: 'Efectivo esperado',
                value: _money(expected),
                helper: 'Apertura + pagos en efectivo.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountController,
                decoration: const InputDecoration(
                  labelText: 'Monto contado',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
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
                final amount = double.tryParse(
                  amountController.text.trim(),
                );

                if (amount == null || amount < 0) {
                  return;
                }

                Navigator.of(context).pop(
                  _CloseCashDialogResult(
                    actualClosingAmount: amount,
                    notes: notesController.text.trim().isEmpty
                        ? null
                        : notesController.text.trim(),
                  ),
                );
              },
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    );

    amountController.dispose();
    notesController.dispose();

    if (result == null) {
      return;
    }

    await _runAction(
      successMessage: 'Caja cerrada localmente.',
      action: () async {
        final service = ref.read(cashSessionLocalServiceProvider);

        await service.closeCashSession(
          CloseCashSessionInput(
            businessId: widget.businessId,
            branchId: widget.branchId,
            profileId: widget.profileId,
            actualClosingAmount: result.actualClosingAmount,
            notes: result.notes,
          ),
        );
      },
    );
  }

  Future<void> _runAction({
    required String successMessage,
    required Future<void> Function() action,
  }) async {
    if (!mounted) {
      return;
    }

    setState(() {
      _isRunningAction = true;
      _error = null;
    });

    try {
      await action();
      await _load();

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRunningAction = false;
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
                      child: Text(
                        'Error cargando caja: $_error',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                CashStatusCard(
                  summary: summary,
                  readiness: readiness,
                ),
                const SizedBox(height: 12),
                _CashActionsSection(
                  summary: summary,
                  readiness: readiness,
                  isBusy: _isBusy,
                  onOpenCash: _openCashSessionDialog,
                  onSyncCash: _syncCash,
                  onCloseCash: _closeCashSessionDialog,
                  onRefresh: _load,
                ),
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
    required this.readiness,
    required this.isBusy,
    required this.onOpenCash,
    required this.onSyncCash,
    required this.onCloseCash,
    required this.onRefresh,
  });

  final Map<String, dynamic>? summary;
  final Map<String, dynamic>? readiness;
  final bool isBusy;
  final VoidCallback onOpenCash;
  final VoidCallback onSyncCash;
  final VoidCallback onCloseCash;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final status = summary?['status']?.toString();
    final isOpen = status == 'open';
    final isClosed = status == 'closed';
    final hasDirtyCash = _int(readiness?['dirty_cash_register_count']) > 0 ||
        _int(readiness?['dirty_cash_session_count']) > 0;
    final canClose = isOpen;
    final canOpen = summary == null || isClosed;

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
              onPressed: isBusy || !hasDirtyCash ? null : onSyncCash,
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar cash'),
            ),
            FilledButton.icon(
              onPressed: isBusy || !canClose ? null : onCloseCash,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Cerrar caja'),
            ),
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
          value: _text(summary!['cash_session_id'], fallback: 'Sin ID'),
          helper:
              'Estado: ${_text(summary!['status'], fallback: 'desconocido')}',
        ),
        CashMetricTile(
          label: 'Apertura / cierre',
          value: _text(summary!['opened_at'], fallback: 'Sin apertura'),
          helper:
              'Cierre: ${_text(summary!['closed_at'], fallback: 'sin cierre')}',
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
          value: canUploadPos ? 'POS habilitado' : 'POS bloqueado',
          helper: readiness!['pos_upload_blocked_reason']?.toString(),
        ),
        CashMetricTile(
          label: 'Cash pendiente',
          value:
              'Registros: ${_text(readiness!['dirty_cash_register_count'], fallback: '0')} / Sesiones: ${_text(readiness!['dirty_cash_session_count'], fallback: '0')}',
          helper:
              'Ventas sin cash: ${_text(readiness!['pending_sales_without_cash_count'], fallback: '0')}',
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
                    _text(row['payment_method'], fallback: 'unknown'),
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
      nextAction = 'Sincronizar cash antes de vender';
    } else {
      nextAction = 'Ir a POS';
    }

    return CashMetricTile(
      label: 'Siguiente acción sugerida',
      value: nextAction,
      helper: 'La navegación a POS se conecta en la siguiente subfase.',
    );
  }
}

class _OpenCashSessionDialog extends StatefulWidget {
  const _OpenCashSessionDialog({
    required this.suggestedOpeningAmount,
  });

  final double suggestedOpeningAmount;

  @override
  State<_OpenCashSessionDialog> createState() => _OpenCashSessionDialogState();
}

class _OpenCashSessionDialogState extends State<_OpenCashSessionDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _amountController;

  @override
  void initState() {
    super.initState();

    _nameController = TextEditingController(text: 'Caja Principal');
    _codeController = TextEditingController(text: 'MAIN');
    _amountController = TextEditingController(
      text: widget.suggestedOpeningAmount.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _amountController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Abrir caja'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nombre de caja',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Código',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Monto apertura',
                helperText:
                    'Sugerido desde el último cierre. Puedes cambiarlo.',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final amount = double.tryParse(
              _amountController.text.trim(),
            );

            if (amount == null || amount < 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Monto de apertura inválido.'),
                ),
              );
              return;
            }

            Navigator.of(context).pop(
              _OpenCashDialogResult(
                registerName: _nameController.text.trim().isEmpty
                    ? 'Caja Principal'
                    : _nameController.text.trim(),
                registerCode: _codeController.text.trim().isEmpty
                    ? 'MAIN'
                    : _codeController.text.trim(),
                openingAmount: amount,
              ),
            );
          },
          child: const Text('Abrir'),
        ),
      ],
    );
  }
}

class _OpenCashDialogResult {
  const _OpenCashDialogResult({
    required this.registerName,
    required this.registerCode,
    required this.openingAmount,
  });

  final String registerName;
  final String registerCode;
  final double openingAmount;
}

class _CloseCashDialogResult {
  const _CloseCashDialogResult({
    required this.actualClosingAmount,
    this.notes,
  });

  final double actualClosingAmount;
  final String? notes;
}

double _suggestedOpeningAmount(Map<String, dynamic>? summary) {
  if (summary == null) {
    return 50000;
  }

  final status = summary['status']?.toString();

  if (status == 'closed') {
    final closingCashAmount = _num(summary['closing_cash_amount']);

    if (closingCashAmount > 0) {
      return closingCashAmount;
    }

    final storedExpectedCashAmount = _num(
      summary['stored_expected_cash_amount'],
    );

    if (storedExpectedCashAmount > 0) {
      return storedExpectedCashAmount;
    }

    final calculatedExpectedCashAmount = _num(
      summary['calculated_expected_cash_amount'],
    );

    if (calculatedExpectedCashAmount > 0) {
      return calculatedExpectedCashAmount;
    }
  }

  final openingCashAmount = _num(summary['opening_cash_amount']);

  if (openingCashAmount > 0) {
    return openingCashAmount;
  }

  return 50000;
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
