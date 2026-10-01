import 'package:flutter/material.dart';

import '../../../../core/models/product_sale_mode.dart';
import '../../../../core/money/cop_price_input.dart';
import '../../../../core/quantity/weight_quantity_input.dart';

/// Shared commercial contract for product creation in Inventory and Purchases.
/// A newly created product has no stock or acquisition cost; those come from
/// the subsequent receipt/purchase, never from its current sale price.
class ProductCreationCommercialController extends ChangeNotifier {
  ProductSaleMode saleMode = ProductSaleMode.unit;
  String salePriceText = '0';
  String minimumStockText = '0';
  String unit = 'unidad';

  void selectMode(ProductSaleMode value) {
    if (saleMode == value) return;
    saleMode = value;
    minimumStockText = '0';
    notifyListeners();
  }

  int? get salePriceCents => parseCopPriceCents(salePriceText);

  String get unitForPersistence =>
      saleMode == ProductSaleMode.weight ? 'g' : unit.trim();

  int? get minimumStock {
    final raw = minimumStockText.trim();
    if (saleMode == ProductSaleMode.unit) {
      final value = int.tryParse(raw);
      return value != null && value >= 0 ? value : null;
    }
    if (raw == '0') return 0;
    return parseWeightQuantity(raw, WeightInputUnit.kilogram);
  }

  String? validateMinimumStock(String? raw) {
    minimumStockText = raw ?? '';
    if (minimumStock != null) return null;
    return saleMode == ProductSaleMode.weight
        ? 'Ingresa kilogramos con hasta 3 decimales.'
        : 'Usa un entero igual o mayor a cero.';
  }
}

class ProductCreationCommercialFields extends StatelessWidget {
  const ProductCreationCommercialFields({
    super.key,
    required this.controller,
    required this.keyPrefix,
  });

  final ProductCreationCommercialController controller;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Forma de venta',
                style: Theme.of(context).textTheme.titleSmall),
            SegmentedButton<ProductSaleMode>(
              key: Key('$keyPrefix-sale-mode'),
              segments: ProductSaleMode.values
                  .map((mode) => ButtonSegment(
                      value: mode, label: Text(mode.displayLabel)))
                  .toList(),
              selected: {controller.saleMode},
              onSelectionChanged: (selection) =>
                  controller.selectMode(selection.single),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: Key('$keyPrefix-sale-price-field'),
              initialValue: controller.salePriceText,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: controller.saleMode == ProductSaleMode.weight
                    ? 'Precio de venta por libra (500 g)'
                    : 'Precio de venta por unidad',
                border: const OutlineInputBorder(),
              ),
              validator: (raw) => parseCopPriceCents(raw ?? '') == null
                  ? 'Ingresa un precio válido en pesos.'
                  : null,
              onChanged: (value) => controller.salePriceText = value,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey(controller.saleMode),
                    child: TextFormField(
                      key: Key('$keyPrefix-minimum-stock-field'),
                      // Reset this field when the quantity interpretation changes.
                      initialValue: controller.minimumStockText,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Stock mínimo',
                        suffixText:
                            controller.saleMode == ProductSaleMode.weight
                                ? 'kg'
                                : null,
                        border: const OutlineInputBorder(),
                      ),
                      validator: controller.validateMinimumStock,
                      onChanged: (value) => controller.minimumStockText = value,
                    ),
                  ),
                ),
                if (controller.saleMode == ProductSaleMode.unit) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      key: Key('$keyPrefix-product-unit-field'),
                      initialValue: controller.unit,
                      decoration: const InputDecoration(
                        labelText: 'Unidad',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value ?? '').trim().isEmpty
                          ? 'La unidad es requerida.'
                          : null,
                      onChanged: (value) => controller.unit = value,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
}
