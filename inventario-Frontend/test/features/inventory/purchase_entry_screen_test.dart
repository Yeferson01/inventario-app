import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/database/database_provider.dart';
import 'package:inventario_frontend/features/inventory/presentation/screens/purchase_entry_screen.dart';
import 'package:inventario_frontend/shared/presentation/widgets/product_image.dart';

void main() {
  testWidgets(
    'edits the visible unit cost and persists it in the purchase impact',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final database = AppDatabase.executor(NativeDatabase.memory());
      addTearDown(database.close);

      await database.into(database.businesses).insert(
            BusinessesCompanion.insert(id: 'business-1', name: 'Negocio'),
          );
      await database.into(database.branches).insert(
            BranchesCompanion.insert(
              id: 'branch-1',
              businessId: 'business-1',
              name: 'Principal',
            ),
          );
      await database.into(database.profiles).insert(
            ProfilesCompanion.insert(
              id: 'profile-1',
              businessId: const Value('business-1'),
            ),
          );
      await database.into(database.products).insert(
            ProductsCompanion.insert(
              id: 'product-1',
              businessId: const Value('business-1'),
              name: 'Coca-Cola 1.75',
              barcode: const Value('7622201764999'),
              purchasePrice: const Value(6000),
              salePrice: 6800,
            ),
          );
      await database.into(database.products).insert(
            ProductsCompanion.insert(
              id: 'product-2',
              businessId: const Value('business-1'),
              name: 'Producto sin código',
              purchasePrice: const Value(3000),
              salePrice: 3500,
            ),
          );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [appDatabaseProvider.overrideWithValue(database)],
          child: const MaterialApp(
            home: PurchaseEntryScreen(
              businessId: 'business-1',
              branchId: 'branch-1',
              profileId: 'profile-1',
              appDeviceId: 'device-1',
              deviceInstallationId: 'installation-1',
              effectivePermissions: {'inventory.purchase'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final productImages = tester
          .widgetList<ProductImage>(find.byType(ProductImage))
          .map((widget) => widget.barcode)
          .toList();
      expect(productImages, contains('7622201764999'));
      expect(productImages, contains(null));

      await tester.scrollUntilVisible(
        find.text('Coca-Cola 1.75'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Coca-Cola 1.75'));
      await tester.pumpAndSettle();

      final costButton = find.byKey(
        const ValueKey('purchase-unit-cost-product-1'),
      );
      await tester.ensureVisible(costButton);
      await tester.pumpAndSettle();
      expect(costButton, findsOneWidget);
      expect(find.text('Costo unitario: \$6000 · Editar'), findsOneWidget);

      await tester.tap(costButton);
      await tester.pumpAndSettle();
      final costField = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(costField, '6200');
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Costo unitario: \$6200 · Editar'), findsOneWidget);

      final saveButton = find.widgetWithText(FilledButton, 'Registrar compra');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Compra registrada'), findsOneWidget);

      final item = await database
          .customSelect(
            'select unit_cost from purchase_items limit 1',
          )
          .getSingle();
      final movement = await database
          .customSelect(
            'select unit_cost from local_inventory_movements limit 1',
          )
          .getSingle();
      final balance = await database.customSelect(
        '''
        select quantity_on_hand, quantity_available, average_cost
        from local_product_stock_balances
        limit 1
        ''',
      ).getSingle();
      final product = await database.customSelect(
        'select purchase_price from products where id = ?',
        variables: const [Variable<String>('product-1')],
      ).getSingle();

      expect(item.read<double>('unit_cost'), 6200);
      expect(movement.read<double>('unit_cost'), 6200);
      expect(balance.read<int>('quantity_on_hand'), 1);
      expect(balance.read<int>('quantity_available'), 1);
      expect(balance.read<double>('average_cost'), 6200);
      expect(product.read<double>('purchase_price'), 6000);

      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}
