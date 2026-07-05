import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/cash_session_local_provider.dart';
import '../widgets/cash_metric_tile.dart';
import '../widgets/cash_status_card.dart';

class CashDashboardScreen extends ConsumerStatefulWidget {
  const CashDashboardScreen({
    super.key,
    required this.businessId,
    required this.branchId,
  });

  final String businessId;
  final String branchId;

  @override
  ConsumerState<CashDashboardScreen> createState() =>
      _CashDashboardScreenState();
}

class _CashDashboardScreenState extends ConsumerState<CashDashboardScreen> {
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _readiness;
  Object? _error;
  bool _isLoading = false;

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

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final readiness = _readiness;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Caja'),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_isLoading) const LinearProgressIndicator(),
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
      helper:
          'Esta pantalla todavía es base visual. Las acciones reales se conectan en la siguiente subfase.',
    );
  }
}

String _money(Object? value) {
  if (value == null) {
    return r'$0';
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
