import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/database/database_provider.dart';
import 'package:inventario_frontend/core/quantity/weight_quantity_input.dart';
import 'package:inventario_frontend/features/inventory/presentation/screens/purchase_entry_screen.dart';

void main() {
  testWidgets(
      'tablet panels scroll separately and quick form fits short height',
      (tester) async {
    await _pumpFixture(tester,
        allowProductCreation: true, viewport: const Size(1280, 700));
    expect(find.byKey(const Key('purchase-products-scroll')), findsOneWidget);
    expect(find.byKey(const Key('purchase-cart-scroll')), findsOneWidget);
    await tester.tap(find.text('Crear producto rápido'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1280, 400);
    await tester.pumpAndSettle();
    expect(find.text('Crear producto rápido'), findsWidgets);
    expect(find.text('Continuar'), findsOneWidget);
    expect(tester.takeException(), null);
    await _dispose(tester);
  });

  testWidgets('Purchases creates UNIT with integer minimum and unit label',
      (tester) async {
    final db = await _pumpFixture(tester, allowProductCreation: true);
    final create = find.text('Crear producto rápido');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre del producto'), 'Agua');
    expect(find.text('Unidad'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('purchase-product-sale-price-field')), '3500');
    await tester.enterText(
        find.byKey(const Key('purchase-product-minimum-stock-field')), '3');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    final row = await db
        .customSelect(
            "select sale_mode, sale_price_cents, minimum_stock from products where name='Agua'")
        .getSingle();
    expect(row.read<String>('sale_mode'), 'unit');
    expect(row.read<int>('sale_price_cents'), 350000);
    expect(row.read<int>('minimum_stock'), 3);
    await _dispose(tester);
  });

  testWidgets('Purchases creates WEIGHT with the same exact commercial fields',
      (tester) async {
    final db = await _pumpFixture(tester, allowProductCreation: true);
    final create = find.text('Crear producto rápido');
    await tester.ensureVisible(create);
    await tester.tap(create);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Nombre del producto'), 'Tomate');
    await tester.tap(find.text('Por peso'));
    await tester.pumpAndSettle();
    expect(find.text('Unidad'), findsNothing);
    expect(find.text('Precio de venta por libra (500 g)'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('purchase-product-sale-price-field')), '800');
    await tester.enterText(
        find.byKey(const Key('purchase-product-minimum-stock-field')), '1,5');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    final row = await db
        .customSelect(
            "select sale_mode, sale_price_cents, minimum_stock from products where name='Tomate'")
        .getSingle();
    expect(row.read<String>('sale_mode'), 'weight');
    expect(row.read<int>('sale_price_cents'), 80000);
    expect(row.read<int>('minimum_stock'), 1500);
    expect(
        find.byKey(ValueKey(
            'purchase-weight-quantity-${(await db.customSelect("select id from products where name='Tomate'").getSingle()).read<String>('id')}')),
        findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('WEIGHT defaults and exact live totals for kg, pound and grams',
      (tester) async {
    final db = await _pumpFixture(tester);
    await _add(tester, 'Papa');

    expect(find.byKey(const ValueKey('purchase-weight-quantity-weight')),
        findsOneWidget);
    expect(find.text('kg'), findsOneWidget);
    expect(find.text('por libra'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('purchase-unit-cost-weight')), findsNothing);

    await _enter(tester, 'purchase-weight-quantity-weight', '10');
    await _enter(tester, 'purchase-weight-cost-weight', '800');
    expect(find.text('Total: \$16.000'), findsOneWidget);
    await _add(tester, 'Papa');
    expect(find.text('Total: \$16.000'), findsOneWidget);

    await _select<int>(tester, 'purchase-weight-basis-weight', 'por kg');
    await _enter(tester, 'purchase-weight-cost-weight', '1.600');
    expect(find.text('Total: \$16.000'), findsOneWidget);

    await _select<WeightInputUnit>(
        tester, 'purchase-weight-unit-weight', 'libra (500 g)');
    await _select<int>(tester, 'purchase-weight-basis-weight', 'por libra');
    await _enter(tester, 'purchase-weight-quantity-weight', '1,5');
    await _enter(tester, 'purchase-weight-cost-weight', '800');
    expect(find.text('Total: \$1.200'), findsOneWidget);
    await _enter(tester, 'purchase-weight-quantity-weight', '1.5');
    expect(find.text('Total: \$1.200'), findsOneWidget);

    await _select<WeightInputUnit>(tester, 'purchase-weight-unit-weight', 'kg');
    await _enter(tester, 'purchase-weight-quantity-weight', '8,250');
    expect(find.text('Total: \$13.200'), findsOneWidget);
    await _enter(tester, 'purchase-weight-quantity-weight', '8,2505');
    expect(
        find.text('Los kilogramos admiten hasta 3 decimales.'), findsOneWidget);
    expect(find.text('Total: —'), findsOneWidget);

    await _select<WeightInputUnit>(tester, 'purchase-weight-unit-weight', 'g');
    await _enter(tester, 'purchase-weight-quantity-weight', '750');
    expect(find.text('Total: \$1.200'), findsOneWidget);
    await _enter(tester, 'purchase-weight-quantity-weight', '750,5');
    expect(find.text('Ingresa gramos enteros.'), findsOneWidget);
    final save = find.widgetWithText(FilledButton, 'Registrar compra');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Ingresa gramos enteros.'), findsWidgets);
    await _enter(tester, 'purchase-weight-quantity-weight', '750');
    await _enter(tester, 'purchase-weight-cost-weight', '8,');
    expect(
        find.text('Ingresa un costo válido mayor que cero.'), findsOneWidget);
    expect(
        (await db
                .customSelect('select count(*) as n from purchases')
                .getSingle())
            .read<int>('n'),
        0);
    await _dispose(tester);
  });

  testWidgets(
      'offline WEIGHT purchase commits grams, cost pool and versioned outbox',
      (tester) async {
    final db = await _pumpFixture(tester);
    await _add(tester, 'Papa');
    await _enter(tester, 'purchase-weight-quantity-weight', '10');
    await _enter(tester, 'purchase-weight-cost-weight', '800');
    final save = find.widgetWithText(FilledButton, 'Registrar compra');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    final item =
        (await db.customSelect('select * from purchase_items').getSingle())
            .data;
    expect(item['quantity'], 10000);
    expect(item['sale_mode_snapshot'], 'weight');
    expect(item['cost_basis_quantity_snapshot'], 500);
    expect(item['unit_cost_cents'], 80000);
    expect(item['subtotal_cents'], 1600000);
    final movement = (await db
            .customSelect('select * from local_inventory_movements')
            .getSingle())
        .data;
    expect(movement['quantity_change'], 10000);
    expect(movement['cost_effect_cents'], 1600000);
    final balance = (await db
            .customSelect(
                "select * from local_product_stock_balances where product_id='weight'")
            .getSingle())
        .data;
    expect(balance['quantity_on_hand'], 13000);
    expect(balance['cost_basis_cents'], 2080000);
    final payload = (await db.customSelect('''
      select payload_json from local_sync_mutations
      where entity_table='purchase_items'
    ''').getSingle()).read<String>('payload_json');
    final decoded = jsonDecode(payload) as Map<String, dynamic>;
    expect(decoded['contract_version'], 'weighted_purchase_v1');
    expect(decoded['quantity'], 10000);
    expect(decoded['cost_basis_quantity'], 500);
    expect(decoded['subtotal_cents'], 1600000);
    expect(
        (await db
                .customSelect('select count(*) as n from local_sync_batches')
                .getSingle())
            .read<int>('n'),
        1);
    await _dispose(tester);
  });

  testWidgets(
      'UNIT controls remain and one purchase can contain UNIT and WEIGHT',
      (tester) async {
    final db = await _pumpFixture(tester);
    await _add(tester, 'Gaseosa');
    expect(
        find.byKey(const ValueKey('purchase-unit-cost-unit')), findsOneWidget);
    expect(find.text('Cantidad: 1'), findsOneWidget);
    final unitCost = find.byKey(const ValueKey('purchase-unit-cost-unit'));
    await tester.ensureVisible(unitCost);
    await tester.pumpAndSettle();
    await tester.tap(unitCost);
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(TextFormField)),
        '2000');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    await _add(tester, 'Papa');
    expect(find.byKey(const ValueKey('purchase-weight-unit-weight')),
        findsOneWidget);
    await _enter(tester, 'purchase-weight-quantity-weight', '5');
    await _enter(tester, 'purchase-weight-cost-weight', '800');
    final save = find.widgetWithText(FilledButton, 'Registrar compra');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    final rows = await db
        .customSelect(
            'select product_id, quantity, sale_mode_snapshot, cost_basis_quantity_snapshot from purchase_items order by product_id')
        .get();
    expect(rows, hasLength(2));
    expect(rows[0].data['product_id'], 'unit');
    expect(rows[0].data['quantity'], 1);
    expect(rows[0].data['cost_basis_quantity_snapshot'], 1);
    expect(rows[1].data['product_id'], 'weight');
    expect(rows[1].data['quantity'], 5000);
    expect(rows[1].data['cost_basis_quantity_snapshot'], 500);
    expect(
        (await db
                .customSelect('select count(*) as n from purchases')
                .getSingle())
            .read<int>('n'),
        1);
    await _dispose(tester);
  });

  testWidgets('changing product mode resets quantity and cost semantics',
      (tester) async {
    final db = await _pumpFixture(tester);
    await _add(tester, 'Gaseosa');
    expect(find.text('Cantidad: 1'), findsOneWidget);
    await db.customUpdate(
        "update products set sale_mode='weight' where id='unit'",
        updates: {db.products});
    await tester.tap(find.byTooltip('Actualizar'));
    await tester.pumpAndSettle();
    await _add(tester, 'Gaseosa');
    expect(find.byKey(const ValueKey('purchase-weight-quantity-unit')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('purchase-unit-cost-unit')), findsNothing);
    expect(find.text('Total: —'), findsOneWidget);
    await _enter(tester, 'purchase-weight-quantity-unit', '5');
    await _enter(tester, 'purchase-weight-cost-unit', '800');
    expect(find.text('Total: \$8.000'), findsOneWidget);
    await db.customUpdate(
        "update products set sale_mode='unit' where id='unit'",
        updates: {db.products});
    await tester.tap(find.byTooltip('Actualizar'));
    await tester.pumpAndSettle();
    await _add(tester, 'Gaseosa');
    expect(find.byKey(const ValueKey('purchase-weight-quantity-unit')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('purchase-unit-cost-unit')), findsOneWidget);
    expect(find.text('Cantidad: 1'), findsOneWidget);
    await _dispose(tester);
  });
}

Future<AppDatabase> _pumpFixture(WidgetTester tester,
    {bool allowProductCreation = false,
    Size viewport = const Size(412, 915)}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final db = AppDatabase.executor(NativeDatabase.memory());
  addTearDown(db.close);
  await db
      .into(db.businesses)
      .insert(BusinessesCompanion.insert(id: 'business', name: 'Negocio'));
  await db.into(db.branches).insert(BranchesCompanion.insert(
      id: 'branch', businessId: 'business', name: 'Principal'));
  await db.into(db.profiles).insert(ProfilesCompanion.insert(
      id: 'profile', businessId: const Value('business')));
  await db.into(db.products).insert(ProductsCompanion.insert(
      id: 'weight',
      businessId: const Value('business'),
      name: 'Papa',
      salePrice: 1000,
      saleMode: const Value('weight')));
  await db.into(db.products).insert(ProductsCompanion.insert(
      id: 'unit',
      businessId: const Value('business'),
      name: 'Gaseosa',
      salePrice: 3000));
  await db.customStatement('''
    insert into local_product_stock_balances
      (id,business_id,branch_id,product_id,quantity_on_hand,quantity_available,cost_basis_cents)
    values ('balance','business','branch','weight',3000,3000,480000)
  ''');
  await tester.pumpWidget(ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
      child: MaterialApp(
          home: PurchaseEntryScreen(
        businessId: 'business',
        branchId: 'branch',
        profileId: 'profile',
        appDeviceId: 'device',
        deviceInstallationId: 'installation',
        effectivePermissions: {
          'inventory.purchase',
          if (allowProductCreation) 'products.create',
        },
      ))));
  await tester.pumpAndSettle();
  return db;
}

Future<void> _add(WidgetTester tester, String name) async {
  final productName = find.text(name).last;
  await tester.scrollUntilVisible(productName, 300,
      scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(productName);
  await tester.pumpAndSettle();
  await tester.tap(productName);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final field = find.byKey(ValueKey(key));
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

Future<void> _select<T>(WidgetTester tester, String key, String label) async {
  final dropdown = find.byKey(ValueKey(key));
  tester.testTextInput.hide();
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}
