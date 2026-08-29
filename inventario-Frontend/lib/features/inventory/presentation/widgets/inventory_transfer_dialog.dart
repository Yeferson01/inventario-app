import 'package:flutter/material.dart';

import '../../application/inventory_transfer_models.dart';
import '../../../sync/data/models/authorized_operational_context_models.dart';

typedef InventoryTransferSubmit = Future<InventoryTransferResult> Function(
  CreateInventoryTransferInput input,
);

class InventoryTransferDialog extends StatefulWidget {
  const InventoryTransferDialog({
    required this.businessId,
    required this.productId,
    required this.productName,
    required this.availableQuantity,
    required this.sourceContext,
    required this.destinationContexts,
    required this.onSubmit,
    super.key,
  });

  final String businessId;
  final String productId;
  final String productName;
  final int availableQuantity;
  final AuthorizedOperationalContext sourceContext;
  final List<AuthorizedOperationalContext> destinationContexts;
  final InventoryTransferSubmit onSubmit;

  @override
  State<InventoryTransferDialog> createState() =>
      _InventoryTransferDialogState();
}

class _InventoryTransferDialogState extends State<InventoryTransferDialog> {
  final _quantityController = TextEditingController();
  final _identity = InventoryTransferOperationIdentity.create();
  String? _destinationBranchId;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final quantity = int.tryParse(_quantityController.text.trim());
    final destinationBranchId = _destinationBranchId;
    if (quantity == null || quantity <= 0) {
      setState(() => _errorMessage = 'Ingresa una cantidad mayor que cero.');
      return;
    }
    if (quantity > widget.availableQuantity) {
      setState(
        () => _errorMessage =
            'La cantidad supera el stock disponible en la sucursal origen.',
      );
      return;
    }
    if (destinationBranchId == null) {
      setState(() => _errorMessage = 'Selecciona una sucursal destino.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final result = await widget.onSubmit(
        CreateInventoryTransferInput(
          businessId: widget.businessId,
          fromBranchId: widget.sourceContext.branchId,
          toBranchId: destinationBranchId,
          productId: widget.productId,
          quantity: quantity,
          transferId: _identity.transferId,
          transferItemId: _identity.transferItemId,
          idempotencyKey: _identity.idempotencyKey,
          notes: 'Transferencia de inventario desde Flutter',
        ),
      );
      if (mounted) Navigator.of(context).pop(result);
    } on InventoryTransferException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'No fue posible completar la transferencia.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Transferir inventario'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.productName, key: const Key('transfer-product-name')),
            const SizedBox(height: 8),
            Text('Stock disponible: ${widget.availableQuantity}'),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Sucursal origen',
                border: OutlineInputBorder(),
              ),
              child: Text(widget.sourceContext.branchName),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const Key('transfer-destination-selector'),
              initialValue: _destinationBranchId,
              decoration: const InputDecoration(
                labelText: 'Sucursal destino',
                border: OutlineInputBorder(),
              ),
              items: widget.destinationContexts
                  .where(
                    (item) =>
                        item.profileId == widget.sourceContext.profileId &&
                        item.businessId == widget.sourceContext.businessId &&
                        item.branchId != widget.sourceContext.branchId &&
                        item.effectivePermissions
                            .contains('inventory.transfer'),
                  )
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.branchId,
                      child: Text(item.branchName),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _isSubmitting
                  ? null
                  : (value) => setState(() {
                        _destinationBranchId = value;
                        _errorMessage = null;
                      }),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('transfer-quantity-field'),
              controller: _quantityController,
              enabled: !_isSubmitting,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Cantidad',
                border: OutlineInputBorder(),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                key: const Key('transfer-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'La transferencia requiere conexión para confirmar ambos movimientos de forma atómica.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('confirm-inventory-transfer'),
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Transferir'),
        ),
      ],
    );
  }
}
