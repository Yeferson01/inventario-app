import 'package:flutter/material.dart';

class ProductiveOpenCashSessionDialog extends StatefulWidget {
  const ProductiveOpenCashSessionDialog({
    required this.suggestedOpeningAmount,
    super.key,
  });

  final double suggestedOpeningAmount;

  @override
  State<ProductiveOpenCashSessionDialog> createState() =>
      _ProductiveOpenCashSessionDialogState();
}

class _ProductiveOpenCashSessionDialogState
    extends State<ProductiveOpenCashSessionDialog> {
  late final TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: widget.suggestedOpeningAmount.toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Abrir caja'),
      content: SingleChildScrollView(
        child: TextField(
          controller: _amountController,
          decoration: const InputDecoration(
            labelText: 'Monto apertura',
            helperText: 'Sugerido desde el último cierre. Puedes cambiarlo.',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Monto de apertura inválido.')),
              );
              return;
            }
            Navigator.of(context).pop(
              ProductiveOpenCashDialogResult(openingAmount: amount),
            );
          },
          child: const Text('Abrir'),
        ),
      ],
    );
  }
}

class ProductiveOpenCashDialogResult {
  const ProductiveOpenCashDialogResult({required this.openingAmount});

  final double openingAmount;
}

double suggestedProductiveOpeningAmount(Map<String, dynamic>? summary) {
  if (summary == null) return 50000;
  final status = summary['status']?.toString();
  if (status == 'closed') {
    for (final key in const [
      'closing_cash_amount',
      'stored_expected_cash_amount',
      'calculated_expected_cash_amount',
    ]) {
      final value = _number(summary[key]);
      if (value > 0) return value;
    }
  }
  final opening = _number(summary['opening_cash_amount']);
  return opening > 0 ? opening : 50000;
}

double _number(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
