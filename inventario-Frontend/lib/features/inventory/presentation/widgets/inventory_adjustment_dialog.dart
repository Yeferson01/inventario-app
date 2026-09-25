import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/app_uuid.dart';
import '../../application/inventory_adjustment_models.dart';
import '../../application/inventory_adjustment_provider.dart';
import '../../application/product_stock_balance_providers.dart';

extension InventoryAdjustmentReasonLabel on InventoryAdjustmentReason {
  String get label => switch (this) {
        InventoryAdjustmentReason.expired => 'Vencido',
        InventoryAdjustmentReason.damaged => 'Dañado',
        InventoryAdjustmentReason.lost => 'Perdido',
        InventoryAdjustmentReason.theft => 'Robo',
        InventoryAdjustmentReason.gift => 'Regalo',
        InventoryAdjustmentReason.internalConsumption => 'Consumo interno',
        InventoryAdjustmentReason.manualCorrection => 'Corrección manual',
        InventoryAdjustmentReason.other => 'Otro',
      };
}

class InventoryAdjustmentDialog extends ConsumerStatefulWidget {
  const InventoryAdjustmentDialog(
      {super.key,
      required this.scope,
      required this.productId,
      required this.productName,
      required this.isScopeCurrent});
  final InventoryAdjustmentScope scope;
  final String productId;
  final String productName;
  final bool Function() isScopeCurrent;

  @override
  ConsumerState<InventoryAdjustmentDialog> createState() =>
      _InventoryAdjustmentDialogState();
}

class _InventoryAdjustmentDialogState
    extends ConsumerState<InventoryAdjustmentDialog> {
  final _form = GlobalKey<FormState>();
  InventoryAdjustmentReason _reason = InventoryAdjustmentReason.expired;
  String _quantity = '';
  String _note = '';
  bool _increase = false;
  bool _submitting = false;
  bool _ambiguous = false;
  String? _error;
  InventoryAdjustmentRequest? _attempt;

  int? get _amount => int.tryParse(_quantity.trim());
  int get _delta =>
      (_reason.isLoss || !_increase) ? -(_amount ?? 0) : (_amount ?? 0);

  void _edit(VoidCallback change) => setState(() {
        change();
        // Edits after a definite rejection are a new intention. An ambiguous
        // attempt stays frozen, so retry cannot apply its effect a second time.
        _attempt = null;
        _error = null;
      });

  Future<void> _submit() async {
    if (_submitting) return;
    if (!widget.isScopeCurrent() ||
        ref
                .read(inventoryAdjustmentAllowedProvider(widget.scope))
                .asData
                ?.value !=
            true) {
      setState(() => _error =
          'No tienes permiso para ajustar inventario en este contexto.');
      return;
    }
    // An ambiguous retry must reach B1 even if the balance already changed.
    if (!_ambiguous && !(_form.currentState?.validate() ?? false)) return;
    final scope = widget.scope;
    final note = _note.trim().isEmpty ? null : _note.trim();
    _attempt ??= _reason.isLoss
        ? InventoryAdjustmentRequest.loss(
            profileId: scope.profileId,
            businessId: scope.businessId,
            branchId: scope.branchId,
            productId: widget.productId,
            reason: _reason,
            quantity: _amount!,
            note: note,
            idempotencyKey: AppUuid.v7())
        : InventoryAdjustmentRequest.correction(
            profileId: scope.profileId,
            businessId: scope.businessId,
            branchId: scope.branchId,
            productId: widget.productId,
            reason: _reason,
            delta: _delta,
            note: note,
            idempotencyKey: AppUuid.v7());
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(inventoryAdjustmentSubmitProvider)(_attempt!);
      if (mounted) Navigator.of(context).pop(true);
    } on InventoryAdjustmentException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = switch (e.kind) {
          InventoryAdjustmentFailure.insufficientStock =>
            'No hay suficiente stock para realizar este ajuste.',
          InventoryAdjustmentFailure.reservedStockConflict =>
            'Parte del stock está reservado y no puede descontarse.',
          InventoryAdjustmentFailure.permissionDenied =>
            'No tienes permiso para ajustar inventario.',
          InventoryAdjustmentFailure.invalidContext =>
            'El contexto cambió. Cierra el formulario y vuelve a Inventario.',
          InventoryAdjustmentFailure.invalidProduct =>
            'El producto ya no está disponible para ajustes.',
          InventoryAdjustmentFailure.idempotencyConflict =>
            'El ajuste cambió durante un reintento. Revisa los datos e inténtalo nuevamente.',
          InventoryAdjustmentFailure.invalidRequest =>
            'Revisa el motivo y la cantidad del ajuste.',
          InventoryAdjustmentFailure.invalidBalance =>
            'El saldo no permite realizar este ajuste. Revisa el estado del inventario.',
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _ambiguous = true;
        _error =
            'No pudimos confirmar el resultado. Reintenta el mismo ajuste sin cambiar los datos.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = ref
            .watch(inventoryAdjustmentAllowedProvider(widget.scope))
            .asData
            ?.value ==
        true;
    final balance = ref.watch(localProductStockBalanceProvider(
        ProductStockBalanceKey(
            businessId: widget.scope.businessId,
            branchId: widget.scope.branchId,
            productId: widget.productId)));
    final ready = balance is AsyncData<Map<String, dynamic>?>;
    final row = balance.asData?.value;
    final onHand = (row?['quantity_on_hand'] as num?)?.toInt() ?? 0;
    final available = (row?['quantity_available'] as num?)?.toInt() ?? 0;
    final editable = allowed && !_submitting && !_ambiguous;
    return PopScope(
      canPop: !_submitting,
      child: AlertDialog(
        title: const Text('Ajustar inventario'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Form(
              key: _form,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.productName),
                    if (ready) ...[
                      Text('Stock actual: $onHand'),
                      Text('Stock disponible: $available'),
                    ] else
                      const Text('Saldo local no disponible.'),
                    if (!allowed)
                      const Text('No tienes permiso para ajustar inventario.'),
                    DropdownButtonFormField<InventoryAdjustmentReason>(
                      key: const Key('adjustment-reason'),
                      initialValue: _reason,
                      decoration: const InputDecoration(labelText: 'Motivo'),
                      items: InventoryAdjustmentReason.values
                          .map((r) =>
                              DropdownMenuItem(value: r, child: Text(r.label)))
                          .toList(),
                      onChanged: editable
                          ? (r) {
                              if (r != null) {
                                _edit(() {
                                  _reason = r;
                                  _increase = false;
                                });
                              }
                            }
                          : null,
                    ),
                    if (!_reason.isLoss)
                      DropdownButtonFormField<bool>(
                        key: const Key('adjustment-direction'),
                        initialValue: _increase,
                        decoration: const InputDecoration(
                            labelText: 'Tipo de corrección'),
                        items: const [
                          DropdownMenuItem(
                              value: true, child: Text('Aumentar stock')),
                          DropdownMenuItem(
                              value: false, child: Text('Disminuir stock'))
                        ],
                        onChanged: editable
                            ? (v) => _edit(() => _increase = v ?? false)
                            : null,
                      ),
                    TextFormField(
                        key: const Key('adjustment-quantity'),
                        enabled: editable,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Cantidad'),
                        onChanged: (v) => _edit(() => _quantity = v),
                        validator: (_) {
                          if (_amount == null ||
                              _amount! <= 0 ||
                              _amount! > 2147483647) {
                            return 'Usa una cantidad entera mayor a cero.';
                          }
                          if (!ready) {
                            return 'Espera a que el saldo local esté disponible.';
                          }
                          if (_delta < 0 && _amount! > onHand) {
                            return 'No hay suficiente stock para realizar este ajuste.';
                          }
                          if (_delta < 0 && _amount! > available) {
                            return 'Parte del stock está reservado y no puede descontarse.';
                          }
                          return null;
                        }),
                    TextFormField(
                        key: const Key('adjustment-note'),
                        enabled: editable,
                        decoration:
                            const InputDecoration(labelText: 'Nota (opcional)'),
                        maxLength: 500,
                        maxLines: 2,
                        onChanged: (v) => _edit(() => _note = v)),
                    if (ready && (_amount ?? 0) > 0) ...[
                      Text('Stock: $onHand → ${onHand + _delta}'),
                      Text(
                          'El stock ${_delta < 0 ? 'disminuirá' : 'aumentará'} en $_amount unidades.'),
                    ],
                    if (_error != null)
                      Text(_error!, key: const Key('adjustment-error')),
                  ]),
            ))),
        actions: [
          TextButton(
              onPressed: _submitting ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar')),
          FilledButton(
              key: const Key('adjustment-submit'),
              onPressed: allowed && !_submitting && (ready || _ambiguous)
                  ? _submit
                  : null,
              child: Text(_submitting
                  ? 'Registrando…'
                  : _ambiguous
                      ? 'Reintentar ajuste'
                      : 'Registrar ajuste')),
        ],
      ),
    );
  }
}
