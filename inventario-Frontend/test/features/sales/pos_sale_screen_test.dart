import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/database/database_provider.dart';
import 'package:inventario_frontend/features/sales/presentation/screens/pos_sale_screen.dart';
import 'package:inventario_frontend/shared/presentation/widgets/product_image.dart';

void main() {
  testWidgets('renders shared product images for valid and missing barcodes', (
    tester,
  ) async {
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
            id: 'product-with-barcode',
            businessId: const Value('business-1'),
            name: 'Producto con código',
            barcode: const Value('7622201764999'),
            salePrice: 6800,
          ),
        );
    await database.into(database.products).insert(
          ProductsCompanion.insert(
            id: 'product-without-barcode',
            businessId: const Value('business-1'),
            name: 'Producto sin código',
            salePrice: 3500,
          ),
        );
    await database.customStatement(
      '''
      insert into local_product_stock_balances (
        id, business_id, branch_id, product_id,
        quantity_on_hand, quantity_available, average_cost
      ) values (?, ?, ?, ?, ?, ?, ?)
      ''',
      const [
        'balance-product-with-barcode',
        'business-1',
        'branch-1',
        'product-with-barcode',
        10,
        10,
        7777,
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(database)],
        child: const MaterialApp(
          home: PosSaleScreen(
            businessId: 'business-1',
            branchId: 'branch-1',
            profileId: 'profile-1',
            deviceInstallationId: 'installation-1',
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
    expect(find.textContaining('Costo'), findsNothing);
    expect(find.textContaining('Margen'), findsNothing);
    expect(find.textContaining('7777'), findsNothing);
    expect(find.text('Agregar'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
