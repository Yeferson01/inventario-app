import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/models/product_sale_mode.dart';
import 'package:inventario_frontend/features/inventory/presentation/widgets/product_creation_commercial_fields.dart';

void main() {
  test('shared creation contract keeps UNIT and WEIGHT quantities distinct',
      () {
    final draft = ProductCreationCommercialController();
    addTearDown(draft.dispose);
    draft.salePriceText = '3.500';
    draft.minimumStockText = '3';
    expect(draft.salePriceCents, 350000);
    expect(draft.minimumStock, 3);
    expect(draft.unitForPersistence, 'unidad');

    draft.selectMode(ProductSaleMode.weight);
    expect(draft.minimumStockText, '0');
    expect(draft.unitForPersistence, 'g');
    draft.minimumStockText = '1,5';
    expect(draft.minimumStock, 1500);
    draft.minimumStockText = '8.250';
    expect(draft.minimumStock, 8250);
    draft.minimumStockText = '8,2505';
    expect(draft.minimumStock, isNull);
    expect(draft.validateMinimumStock('8,2505'), contains('3 decimales'));
    draft.selectMode(ProductSaleMode.unit);
    expect(draft.minimumStockText, '0');
    expect(draft.validateMinimumStock('1,5'), isNotNull);
  });
}
