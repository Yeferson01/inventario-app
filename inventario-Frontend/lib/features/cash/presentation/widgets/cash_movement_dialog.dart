import 'package:flutter/material.dart';

import '../../../../core/utils/app_uuid.dart';
import '../../application/cash_movement_models.dart';

/// COP amounts in this pilot are whole pesos. Dots and commas are accepted
/// only as three-digit grouping separators, never as decimal separators.
BigInt? parseCashMovementCopCents(String input) {
  final text = input.trim();
  if (!RegExp(r'^(?:[0-9]+|[1-9][0-9]{0,2}(?:[.,][0-9]{3})+)$')
      .hasMatch(text)) {
    return null;
  }
  final pesos = BigInt.tryParse(text.replaceAll(RegExp(r'[.,]'), ''));
  if (pesos == null || pesos <= BigInt.zero) return null;
  final cents = pesos * BigInt.from(100);
  return cents <= BigInt.from(99999999999999) ? cents : null;
}

String formatCashMovementCopCents(BigInt cents) {
  final negative = cents.isNegative;
  final positive = cents.abs();
  final pesos = (positive ~/ BigInt.from(100)).toString();
  final grouped = StringBuffer();
  for (var index = 0; index < pesos.length; index++) {
    if (index > 0 && (pesos.length - index) % 3 == 0) grouped.write('.');
    grouped.write(pesos[index]);
  }
  final fraction = positive % BigInt.from(100);
  final decimals =
      fraction == BigInt.zero ? '' : ',${fraction.toString().padLeft(2, '0')}';
  return '${negative ? '-' : ''}\$ ${grouped.toString()}$decimals';
}

String cashMovementErrorMessage(
  Object error,
  CashMovementDirection direction,
) {
  if (error is CashMovementException) {
    return switch (error.kind) {
      CashMovementFailure.invalidRequest =>
        'Ingresa un monto válido y selecciona una categoría compatible.',
      CashMovementFailure.invalidContext =>
        'La caja activa cambió. Cierra este formulario y vuelve a intentarlo.',
      CashMovementFailure.permissionDenied =>
        direction == CashMovementDirection.outflow
            ? 'No tienes permiso para registrar esta salida de efectivo.'
            : 'No tienes permiso para registrar esta entrada de efectivo.',
      CashMovementFailure.invalidSession =>
        'La sesión de caja ya no está abierta.',
      CashMovementFailure.insufficientCash =>
        'La salida supera el efectivo esperado. Registra primero una entrada de efectivo.',
      CashMovementFailure.idempotencyConflict =>
        'El movimiento cambió durante un reintento. Revisa los datos antes de volver a registrarlo.',
    };
  }
  return 'No se pudo registrar el movimiento. Revisa los datos e inténtalo de nuevo.';
}

class CashMovementDialog extends StatefulWidget {
  const CashMovementDialog({
    super.key,
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.cashRegisterId,
    required this.cashSessionId,
    required this.direction,
    required this.loadExpectedCashCents,
    required this.submit,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String cashRegisterId;
  final String cashSessionId;
  final CashMovementDirection direction;
  final Future<BigInt> Function() loadExpectedCashCents;
  final Future<CashMovementResult> Function(CashMovementRequest) submit;

  @override
  State<CashMovementDialog> createState() => _CashMovementDialogState();
}

class _CashMovementDialogState extends State<CashMovementDialog> {
  static const _labels = <String, String>{
    'supplier_purchase': 'Compra a proveedor',
    'payroll': 'Nómina',
    'utilities': 'Servicios públicos',
    'rent': 'Arriendo',
    'maintenance': 'Mantenimiento',
    'repairs': 'Reparaciones',
    'transport': 'Transporte',
    'infrastructure': 'Infraestructura',
    'cleaning': 'Aseo',
    'office_supplies': 'Papelería / suministros',
    'owner_withdrawal': 'Retiro del propietario',
    'owner_contribution': 'Aporte del propietario',
    'other_income': 'Otro ingreso',
    'other': 'Otro',
  };

  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  String? _category;
  String? _intentKey;
  BigInt? _expectedCents;
  String? _error;
  bool _loading = true;
  bool _submitting = false;

  bool get _isOutflow => widget.direction == CashMovementDirection.outflow;
  String get _title =>
      _isOutflow ? 'Salida de efectivo' : 'Entrada de efectivo';

  Iterable<String> get _availableCategories =>
      CashMovementRequest.categories.where((category) => _isOutflow
          ? !CashMovementRequest.inflowOnly.contains(category)
          : !CashMovementRequest.outflowOnly.contains(category));

  @override
  void initState() {
    super.initState();
    _refreshExpected();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _refreshExpected() async {
    if (!_loading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final expected = await widget.loadExpectedCashCents();
      if (!mounted) return;
      setState(() {
        _expectedCents = expected;
        _error = null;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _expectedCents = null;
        _error = cashMovementErrorMessage(error, widget.direction);
        _loading = false;
      });
    }
  }

  void _semanticEdit() {
    setState(() {
      _intentKey = null;
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final amount = parseCashMovementCopCents(_amountController.text);
    if (amount == null) {
      setState(() => _error = 'Ingresa un monto válido mayor que cero.');
      return;
    }
    final category = _category;
    if (category == null || !_availableCategories.contains(category)) {
      setState(() => _error = 'Selecciona una categoría válida.');
      return;
    }
    final key = _intentKey ??= AppUuid.v7();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final expected = await widget.loadExpectedCashCents();
      if (!mounted) return;
      final after = _isOutflow ? expected - amount : expected + amount;
      setState(() => _expectedCents = expected);
      if (after.isNegative) {
        throw const CashMovementException(CashMovementFailure.insufficientCash);
      }
      var confirmationChosen = false;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_title),
          content: Text(
            'Categoría: ${_labels[category]}\n'
            'Monto: ${formatCashMovementCopCents(amount)}\n'
            'Efectivo esperado: ${formatCashMovementCopCents(expected)} '
            '→ ${formatCashMovementCopCents(after)}\n\n'
            '¿Registrar movimiento?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (confirmationChosen) return;
                confirmationChosen = true;
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () {
                if (confirmationChosen) return;
                confirmationChosen = true;
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await widget.submit(CashMovementRequest(
        profileId: widget.profileId,
        businessId: widget.businessId,
        branchId: widget.branchId,
        cashRegisterId: widget.cashRegisterId,
        cashSessionId: widget.cashSessionId,
        direction: widget.direction,
        category: category,
        amountCents: amount,
        idempotencyKey: key,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = cashMovementErrorMessage(error, widget.direction);
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = parseCashMovementCopCents(_amountController.text);
    final expected = _expectedCents;
    final after = amount == null || expected == null
        ? null
        : _isOutflow
            ? expected - amount
            : expected + amount;
    return AlertDialog(
      title: Text(_title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Categoría'),
              items: [
                for (final category in _availableCategories)
                  DropdownMenuItem(
                    value: category,
                    child: Text(_labels[category]!),
                  ),
              ],
              onChanged: _submitting
                  ? null
                  : (value) {
                      _category = value;
                      _semanticEdit();
                    },
            ),
            TextField(
              controller: _amountController,
              enabled: !_submitting,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Monto',
                prefixText: '\$ ',
                helperText: 'Pesos enteros; 50000 o 50.000',
              ),
              onChanged: (_) => _semanticEdit(),
            ),
            TextField(
              controller: _noteController,
              enabled: !_submitting,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'Nota (opcional)'),
              onChanged: (_) => _semanticEdit(),
            ),
            if (_loading) const LinearProgressIndicator(),
            if (expected != null) ...[
              Text('Efectivo esperado actual: '
                  '${formatCashMovementCopCents(expected)}'),
              if (after != null)
                Text('Después del movimiento: '
                    '${formatCashMovementCopCents(after)}'),
            ],
            if (after?.isNegative == true)
              const Text(
                'La salida supera el efectivo esperado. '
                'Registra primero una entrada de efectivo.',
              ),
            if (_error != null) Text(_error!),
            if (!_loading && expected == null)
              TextButton(
                onPressed: _refreshExpected,
                child: const Text('Reintentar consulta local'),
              ),
            if (_submitting) const Text('Registrando movimiento…'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _loading ||
                  _submitting ||
                  expected == null ||
                  after?.isNegative == true
              ? null
              : _submit,
          child: const Text('Registrar movimiento'),
        ),
      ],
    );
  }
}
