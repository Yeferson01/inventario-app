import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/database/database_provider.dart';
import 'package:inventario_frontend/core/quantity/weight_quantity_input.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_models.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_provider.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_service.dart';
import 'package:inventario_frontend/features/sales/data/datasources/pos_local_sale_dao.dart';
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
    await tester.tap(find.text('Mostrar recientes'));
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

  testWidgets('tablet POS panels scroll independently with a populated cart',
      (tester) async {
    await _pumpWeightedPos(
      tester,
      viewport: const Size(1280, 800),
      extraUnitProducts: 10,
    );
    final productsPanel = find.byKey(const Key('pos-products-panel-scroll'));
    final cartPanel = find.byKey(const Key('pos-cart-panel-scroll'));
    expect(productsPanel, findsOneWidget);
    expect(cartPanel, findsOneWidget);
    expect(tester.takeException(), null);

    for (var index = 0; index < 10; index++) {
      await _tapProduct(tester, 'Unidad extra $index');
    }
    final productsScrollable = tester.state<ScrollableState>(
      find.descendant(of: productsPanel, matching: find.byType(Scrollable)),
    );
    final cartScrollable = tester.state<ScrollableState>(
      find.descendant(of: cartPanel, matching: find.byType(Scrollable)),
    );
    expect(productsScrollable.position.maxScrollExtent, greaterThan(0));
    expect(cartScrollable.position.maxScrollExtent, greaterThan(0));

    final productOffset = productsScrollable.position.pixels;
    await tester.drag(cartPanel, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(cartScrollable.position.pixels, greaterThan(0));
    expect(productsScrollable.position.pixels, productOffset);
    await tester.dragUntilVisible(
      find.text('Cobrar venta'),
      cartPanel,
      const Offset(0, -350),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cobrar venta'), findsOneWidget);
    expect(tester.takeException(), null);
    await _disposeWeightedPos(tester);
  });

  testWidgets('portrait tablet keeps the compact POS flow usable',
      (tester) async {
    await _pumpWeightedPos(tester,
        viewport: const Size(800, 1280), extraUnitProducts: 10);
    expect(find.byKey(const Key('pos-products-panel-scroll')), findsNothing);
    expect(find.byKey(const Key('pos-cart-panel-scroll')), findsNothing);
    expect(find.text('Mostrar recientes'), findsOneWidget);
    expect(find.byKey(const Key('pos-recent-products-scroll')), findsNothing);
    expect(find.text('Carne'), findsNothing);
    await tester.tap(find.text('Mostrar recientes'));
    await tester.pumpAndSettle();
    final recents = find.byKey(const Key('pos-recent-products-scroll'));
    expect(find.text('Ocultar recientes'), findsOneWidget);
    expect(recents, findsOneWidget);
    expect(tester.getSize(recents).height, lessThanOrEqualTo(280));
    final recentsScroll = tester.state<ScrollableState>(
      find.descendant(of: recents, matching: find.byType(Scrollable)),
    );
    expect(recentsScroll.position.maxScrollExtent, greaterThan(0));
    await _tapProduct(tester, 'Unidad');
    await tester
        .ensureVisible(find.byKey(const Key('pos-recent-products-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ocultar recientes'));
    await tester.pumpAndSettle();
    expect(recents, findsNothing);
    expect(find.text('Unidad'), findsOneWidget);
    expect(find.text('Cobrar venta'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, 'Nombre o código de barras'),
      'Unidad',
    );
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pos-products-panel-scroll')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(
              find.widgetWithText(TextField, 'Nombre o código de barras'))
          .controller!
          .text,
      'Unidad',
    );
    expect(find.text('1 ítem(s)'), findsOneWidget);
    expect(tester.takeException(), null);
    await _disposeWeightedPos(tester);
  });

  for (final entry in <(WeightInputUnit, String)>[
    (WeightInputUnit.gram, '735'),
    (WeightInputUnit.kilogram, '0,735'),
    (WeightInputUnit.commercialPound, '1,47'),
  ]) {
    testWidgets('WEIGHT selector ${entry.$1.name} quotes 735 g exactly',
        (tester) async {
      await _pumpWeightedPos(tester);
      await _tapProduct(tester, 'Carne');
      await tester.pumpAndSettle();
      expect(find.text('Cantidad por peso'), findsOneWidget);

      if (entry.$1 != WeightInputUnit.gram) {
        await tester.tap(find.byType(DropdownButtonFormField<WeightInputUnit>));
        await tester.pumpAndSettle();
        await tester.tap(find
            .text(entry.$1 == WeightInputUnit.kilogram
                ? 'Kilogramos (kg)'
                : 'Libra comercial (500 g)')
            .last);
        await tester.pumpAndSettle();
      }
      await tester.enterText(find.byType(TextField).last, entry.$2);
      await tester.pumpAndSettle();
      expect(find.textContaining('735 g ·'), findsOneWidget);
      expect(find.textContaining(r'$17.640'), findsWidgets);
      await tester.tap(find.text('Aplicar'));
      await tester.pumpAndSettle();
      expect(find.text('735 g'), findsOneWidget);
      expect(find.text('Cantidad por peso'), findsNothing);
      expect(find.byTooltip('Aumentar'), findsNothing);
      expect(find.byTooltip('Disminuir'), findsNothing);
      await _disposeWeightedPos(tester);
    });
  }

  testWidgets('WEIGHT edit and removal preserve UNIT cart behavior',
      (tester) async {
    await _pumpWeightedPos(tester);
    await _tapProduct(tester, 'Carne');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '735');
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    await _tapProduct(tester, 'Unidad');
    await tester.pumpAndSettle();
    expect(find.byTooltip('Aumentar'), findsOneWidget);
    expect(find.byTooltip('Disminuir'), findsOneWidget);
    expect(find.textContaining(r'$18.640'), findsWidgets);

    await Scrollable.ensureVisible(
      tester.element(find.text('735 g').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('735 g').first);
    await tester.pumpAndSettle();
    expect(find.text('Cantidad por peso'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '500');
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(find.text('500 g'), findsOneWidget);
    expect(find.textContaining(r'$13.000'), findsWidgets);

    await Scrollable.ensureVisible(
      tester.element(find.byTooltip('Eliminar').first),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Eliminar').first);
    await tester.pumpAndSettle();
    expect(find.text('Carne'), findsOneWidget);
    expect(find.text('500 g'), findsNothing);
    await _disposeWeightedPos(tester);
  });

  testWidgets('WEIGHT 3 g quote uses HALF_UP cents, not double',
      (tester) async {
    await _pumpWeightedPos(tester, priceCents: 1200100);
    await _tapProduct(tester, 'Carne');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '3');
    await tester.pumpAndSettle();
    expect(find.textContaining(r'$72,01'), findsOneWidget);
    await _disposeWeightedPos(tester);
  });

  testWidgets('WEIGHT cannot add more grams than local available stock',
      (tester) async {
    await _pumpWeightedPos(tester);
    await _tapProduct(tester, 'Carne');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '13001');
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(find.text('Máximo disponible: 13000 g.'), findsOneWidget);
    expect(find.text('Cantidad por peso'), findsOneWidget);
    expect(find.text('13001 g'), findsNothing);
    await _disposeWeightedPos(tester);
  });

  testWidgets('WEIGHT checkout passes exact cents and grams to sale service',
      (tester) async {
    final service = await _pumpWeightedPos(tester, priceCents: 1200100);
    await _tapProduct(tester, 'Carne');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '3');
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.byTooltip('Autocompletar efectivo')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Autocompletar efectivo'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(
      tester.element(find.text('Cobrar venta')),
      alignment: 0.5,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cobrar venta'));
    await tester.pumpAndSettle();
    expect(service.captured?.items.single.quantity, 3);
    expect(service.captured?.payments.single.amountCents, 7201);
    await _disposeWeightedPos(tester);
  });
}

Future<_CapturingSaleService> _pumpWeightedPos(WidgetTester tester,
    {int priceCents = 1200000,
    Size viewport = const Size(412, 915),
    int extraUnitProducts = 0}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final database = AppDatabase.executor(NativeDatabase.memory());
  addTearDown(database.close);
  await database.customStatement(
      'insert into businesses (id, name) values (?, ?)', ['business', 'Shop']);
  await database.customStatement(
      'insert into branches (id, business_id, name) values (?, ?, ?)',
      ['branch', 'business', 'Main']);
  await database.customStatement(
      'insert into profiles (id, business_id) values (?, ?)',
      ['profile', 'business']);
  await database.customStatement(
      'insert into products (id, business_id, name, sale_mode, sale_price, '
      'sale_price_cents) values (?, ?, ?, ?, ?, ?)',
      [
        'weight-product',
        'business',
        'Carne',
        'weight',
        priceCents / 100,
        priceCents
      ]);
  await database.customStatement(
      'insert into products (id, business_id, name, sale_price) '
      'values (?, ?, ?, ?)',
      ['unit-product', 'business', 'Unidad', 1000]);
  for (var index = 0; index < extraUnitProducts; index++) {
    await database.customStatement(
      'insert into products (id, business_id, name, sale_price) '
      'values (?, ?, ?, ?)',
      ['extra-$index', 'business', 'Unidad extra $index', 1000],
    );
    await database.customStatement(
      'insert into local_product_stock_balances '
      '(id, business_id, branch_id, product_id, quantity_on_hand, '
      'quantity_available) values (?, ?, ?, ?, ?, ?)',
      ['balance-extra-$index', 'business', 'branch', 'extra-$index', 10, 10],
    );
  }
  await database.customStatement(
      'insert into local_product_stock_balances (id, business_id, branch_id, '
      'product_id, quantity_on_hand, quantity_available, cost_basis_cents) '
      'values (?, ?, ?, ?, ?, ?, ?)',
      [
        'weight-balance',
        'business',
        'branch',
        'weight-product',
        13000,
        13000,
        2280000
      ]);
  await database.customStatement(
      'insert into local_product_stock_balances (id, business_id, branch_id, '
      'product_id, quantity_on_hand, quantity_available) '
      'values (?, ?, ?, ?, ?, ?)',
      ['unit-balance', 'business', 'branch', 'unit-product', 10, 10]);
  final saleService = _CapturingSaleService(PosLocalSaleDao(database));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appDatabaseProvider.overrideWithValue(database),
      posLocalSaleServiceProvider.overrideWithValue(saleService),
    ],
    child: const MaterialApp(
        home: PosSaleScreen(
      businessId: 'business',
      branchId: 'branch',
      profileId: 'profile',
      deviceInstallationId: 'installation',
      cashRegisterId: 'register',
      cashSessionId: 'session',
    )),
  ));
  await tester.pumpAndSettle();
  return saleService;
}

Future<void> _tapProduct(WidgetTester tester, String name) async {
  final collapsed = find.text('Mostrar recientes');
  if (collapsed.evaluate().isNotEmpty) {
    await tester.tap(collapsed);
    await tester.pumpAndSettle();
  }
  final compactRecents = find.byKey(const Key('pos-recent-products-scroll'));
  if (compactRecents.evaluate().isNotEmpty) {
    await tester.ensureVisible(compactRecents);
    await tester.pumpAndSettle();
  }
  final tile = find
      .ancestor(
        of: find.text(name),
        matching: find.byType(InkWell),
      )
      .first;
  await Scrollable.ensureVisible(tester.element(tile), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(tile);
  await tester.pumpAndSettle();
}

Future<void> _disposeWeightedPos(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

class _CapturingSaleService extends PosLocalSaleService {
  _CapturingSaleService(PosLocalSaleDao dao) : super(dao: dao);

  CreatePosLocalSaleInput? captured;

  @override
  Future<PosLocalSaleResult> createLocalSale(
      CreatePosLocalSaleInput input) async {
    captured = input;
    return PosLocalSaleResult(
      saleId: 'captured',
      businessId: input.businessId,
      branchId: input.branchId,
      subtotal: 72.01,
      discountTotal: 0,
      taxTotal: 0,
      total: 72.01,
      paymentTotal: 72.01,
      itemCount: input.items.length,
      paymentCount: input.payments.length,
      lines: const [],
      totalCents: 7201,
    );
  }
}
