import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/database/database_provider.dart';
import 'package:inventario_frontend/core/models/product_sale_mode.dart';
import 'package:inventario_frontend/features/catalog/application/catalog_local_providers.dart';
import 'package:inventario_frontend/features/inventory/application/business_product_creation_models.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_providers.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_valuation_models.dart';
import 'package:inventario_frontend/features/inventory/application/product_stock_balance_providers.dart';
import 'package:inventario_frontend/features/inventory/presentation/screens/inventory_product_stock_list_screen.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';
import 'package:inventario_frontend/shared/presentation/widgets/product_image.dart';

void main() {
  final catalogMatches = List<Map<String, dynamic>>.generate(
    5,
    (index) => {
      'master_product_id': 'master-$index',
      'master_product_name': 'Cafe $index',
      'master_brand': 'Marca',
      'barcode': '77012345678$index',
      'existing_product_id': null,
    },
  );

  testWidgets('tablet picker shows three catalog matches and both actions',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpScreen(tester, Stream.value(const []),
        effectivePermissions: const {'products.create'},
        enableCreation: true,
        masterMatches: catalogMatches,
        productsStreamFactory: () => Stream.value(const []));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-add-product')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('inventory-add-product-search')), 'cafe');
    await tester.pumpAndSettle();

    final dialog = find.byKey(const Key('inventory-product-picker-scroll'));
    final results = find.byKey(const Key('inventory-add-product-results'));
    final third = find.byKey(const Key('inventory-master-product-master-2'));
    expect(dialog, findsOneWidget);
    expect(tester.getSize(dialog).width, lessThanOrEqualTo(640));
    expect(tester.getSize(dialog).height, lessThanOrEqualTo(640));
    expect(third, findsOneWidget);
    final resultsBounds = tester.getRect(results);
    for (var index = 0; index < 3; index++) {
      final match = find.byKey(Key('inventory-master-product-master-$index'));
      expect(match, findsOneWidget);
      expect(
          tester.getRect(match).top, greaterThanOrEqualTo(resultsBounds.top));
      expect(tester.getRect(match).bottom,
          lessThanOrEqualTo(resultsBounds.bottom));
    }
    expect(find.byKey(const Key('inventory-create-product-manually')),
        findsOneWidget);
    expect(find.text('Cancelar'), findsOneWidget);
    final pickerBounds = tester.getRect(dialog);
    final manual = find.byKey(const Key('inventory-create-product-manually'));
    final cancel = find.text('Cancelar');
    final search = find.byKey(const Key('inventory-add-product-search'));
    expect(tester.getRect(search).top, greaterThanOrEqualTo(pickerBounds.top));
    expect(
        tester.getRect(search).bottom, lessThanOrEqualTo(pickerBounds.bottom));
    expect(
        tester.getRect(manual).bottom, lessThanOrEqualTo(pickerBounds.bottom));
    expect(
        tester.getRect(cancel).bottom, lessThanOrEqualTo(pickerBounds.bottom));
    final resultScroll = tester.state<ScrollableState>(
        find.descendant(of: results, matching: find.byType(Scrollable)).first);
    expect(resultScroll.position.maxScrollExtent, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.tap(manual);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('inventory-product-name-field')), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-add-product')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('inventory-add-product-search')), 'cafe');
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(dialog, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picker actions and matches survive a keyboard-height viewport',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpScreen(tester, Stream.value(const []),
        effectivePermissions: const {'products.create'},
        enableCreation: true,
        masterMatches: catalogMatches,
        productsStreamFactory: () => Stream.value(const []));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-add-product')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('inventory-add-product-search')), 'cafe');
    tester.view.physicalSize = const Size(1280, 260);
    await tester.pumpAndSettle();

    final results = find.byKey(const Key('inventory-add-product-results'));
    final third = find.byKey(const Key('inventory-master-product-master-2'));
    expect(
        tester
            .widget<TextField>(
                find.byKey(const Key('inventory-add-product-search')))
            .controller!
            .text,
        'cafe');
    await tester.dragUntilVisible(third, results, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(third, findsOneWidget);
    final manual = find.byKey(const Key('inventory-create-product-manually'));
    await Scrollable.ensureVisible(tester.element(manual), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(manual).dy, lessThanOrEqualTo(260));
    await Scrollable.ensureVisible(tester.element(find.text('Cancelar')),
        alignment: 0.5);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(find.text('Cancelar')).dy,
        lessThanOrEqualTo(260));
    await tester.tap(find.text('Cancelar'));
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('inventory-product-picker-dialog')), findsNothing);
    await tester.tap(find.byKey(const Key('inventory-add-product')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('inventory-add-product-search')), 'cafe');
    tester.view.physicalSize = const Size(1280, 260);
    await tester.pumpAndSettle();
    await tester.tap(manual);
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('inventory-product-name-field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile picker keeps search results and actions scrollable',
      (tester) async {
    tester.view.physicalSize = const Size(412, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpScreen(tester, Stream.value(const []),
        effectivePermissions: const {'products.create'},
        enableCreation: true,
        masterMatches: catalogMatches,
        productsStreamFactory: () => Stream.value(const []));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-add-product')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('inventory-add-product-search')), 'cafe');
    tester.view.physicalSize = const Size(412, 300);
    await tester.pumpAndSettle();

    final results = find.byKey(const Key('inventory-add-product-results'));
    await tester.dragUntilVisible(
      find.byKey(const Key('inventory-add-master-master-2')),
      results,
      const Offset(0, -80),
    );
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('inventory-add-master-master-2')), findsOneWidget);
    final manual = find.byKey(const Key('inventory-create-product-manually'));
    await Scrollable.ensureVisible(tester.element(manual), alignment: 0.5);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(manual).dy, lessThanOrEqualTo(300));
    await Scrollable.ensureVisible(tester.element(find.text('Cancelar')),
        alignment: 0.5);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(find.text('Cancelar')).dy,
        lessThanOrEqualTo(300));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'tablet product dialogs remain usable at keyboard-height viewport',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpScreen(tester, Stream.value(const []),
        effectivePermissions: const {'products.create'}, enableCreation: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-add-product')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.byKey(const Key('inventory-create-product-manually')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('inventory-create-product-manually')));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const Key('inventory-product-name-field')), findsOneWidget);
    await tester.tap(find.byKey(const Key('inventory-product-name-field')));
    tester.view.physicalSize = const Size(1280, 220);
    await tester.pumpAndSettle();
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.byKey(const Key('inventory-product-create-confirm')),
        findsOneWidget);
    final save = find.byKey(const Key('inventory-product-create-confirm'));
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(220));
    expect(tester.takeException(), null);
  });

  testWidgets('mobile product form actions scroll into a reduced viewport',
      (tester) async {
    tester.view.physicalSize = const Size(412, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpScreen(tester, Stream.value(const []),
        effectivePermissions: const {'products.create'}, enableCreation: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('inventory-add-product')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
        find.byKey(const Key('inventory-create-product-manually')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('inventory-create-product-manually')));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(412, 260);
    await tester.pumpAndSettle();
    final save = find.byKey(const Key('inventory-product-create-confirm'));
    expect(find.text('Cancelar'), findsOneWidget);
    expect(save, findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsWidgets);
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    expect(tester.getBottomRight(save).dy, lessThanOrEqualTo(260));
    expect(tester.takeException(), isNull);
  });

  testWidgets('landscape uses one scroll and preserves name and barcode width',
      (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const name = 'Papa criolla seleccionada de cosecha local';
    const code = '77012345678901234567890';
    await _pumpScreen(
        tester,
        Stream.value([
          {
            'product_id': 'long-product',
            'product_name': name,
            'barcode': code,
            'quantity_on_hand': 13000,
            'sale_mode': 'weight',
            'sale_price_cents': 80000,
            'minimum_stock': 1500,
          },
        ]),
        effectivePermissions: const {});
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('inventory-content-scroll')), findsOneWidget);
    expect(
        tester
            .widget<CustomScrollView>(
                find.byKey(const Key('inventory-content-scroll')))
            .scrollCacheExtent,
        const ScrollCacheExtent.pixels(0));
    await tester.drag(
        find.byKey(const Key('inventory-filter-all')), const Offset(0, -240));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find
        .descendant(
            of: find.byKey(const Key('inventory-content-scroll')),
            matching: find.byType(Scrollable))
        .first);
    expect(scroll.position.pixels, greaterThan(0));
    final nameWidget = tester.widget<Text>(find.text(name));
    expect(nameWidget.maxLines, 2);
    expect(tester.getSize(find.text(name)).width, greaterThan(150));
    expect(tester.getSize(find.text(code)).width, greaterThan(150));
    expect(find.text('Stock: 13 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows loading while the local stock stream has not emitted', (
    tester,
  ) async {
    final controller = StreamController<List<Map<String, dynamic>>>();
    addTearDown(controller.close);

    await _pumpScreen(tester, controller.stream);

    expect(find.byKey(const Key('inventory-loading')), findsOneWidget);
  });

  testWidgets('shows the local stream error state', (tester) async {
    await _pumpScreen(
      tester,
      Stream<List<Map<String, dynamic>>>.error(
        StateError('fallo local'),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('inventory-error')), findsOneWidget);
    expect(find.text('No se pudo cargar el inventario'), findsOneWidget);
    expect(find.textContaining('fallo local'), findsNothing);
    expect(find.textContaining('Vuelve a intentarlo'), findsOneWidget);
  });

  testWidgets('shows empty state only when there are no visible products', (
    tester,
  ) async {
    await _pumpScreen(tester, Stream.value(const []));
    await tester.pump();

    expect(find.byKey(const Key('inventory-empty')), findsOneWidget);
    expect(find.text('Sin productos'), findsOneWidget);
  });

  testWidgets(
      'shows name, optional barcode and quantity on hand including zero', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      Stream.value([
        {
          'product_id': 'product-1',
          'product_name': 'Arroz',
          'barcode': '7701234567890',
          'quantity_on_hand': 15,
          'stock_average_cost': 2.67,
          'minimum_stock': 5,
          'legacy_stock_quantity': 999,
        },
        {
          'product_id': 'product-2',
          'product_name': 'Café',
          'barcode': null,
          'quantity_on_hand': 0,
          'stock_average_cost': 12.5,
          'minimum_stock': 0,
          'legacy_stock_quantity': 40,
        },
      ]),
    );
    await tester.pump();

    expect(find.byKey(const Key('inventory-product-grid')), findsOneWidget);
    expect(find.byKey(const Key('inventory-content-scroll')), findsOneWidget);
    expect(
      tester
          .getTopLeft(find.byKey(const Key('inventory-product-product-1')))
          .dy,
      tester
          .getTopLeft(find.byKey(const Key('inventory-product-product-2')))
          .dy,
    );
    expect(
      tester
          .widget<ProductImage>(
            find.byKey(const Key('inventory-product-image-product-1')),
          )
          .size,
      80,
    );
    expect(
      find.byKey(const Key('inventory-product-image-product-1')),
      findsOneWidget,
    );
    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Café'), findsOneWidget);
    expect(find.text('7701234567890'), findsOneWidget);
    expect(find.text('Stock: 15'), findsOneWidget);
    expect(find.text('Stock: 0'), findsOneWidget);
    expect(find.text(r'Costo prom.: $2.67'), findsOneWidget);
    expect(find.text(r'Costo prom.: $12.50'), findsOneWidget);
    expect(find.text('Mínimo: 5'), findsOneWidget);
    expect(find.text('Mínimo: 0'), findsOneWidget);
    expect(find.text('Stock: 999'), findsNothing);
    expect(find.text('Stock: 40'), findsNothing);
  });

  testWidgets('distinguishes zero average cost from an unknown cost', (
    tester,
  ) async {
    await _pumpScreen(
      tester,
      Stream.value([
        {
          'product_id': 'zero-cost',
          'product_name': 'Costo cero',
          'quantity_on_hand': 1,
          'stock_average_cost': 0,
        },
        {
          'product_id': 'unknown-cost',
          'product_name': 'Costo desconocido',
          'quantity_on_hand': 0,
          'stock_average_cost': null,
        },
      ]),
    );
    await tester.pump();

    expect(find.text(r'Costo prom.: $0.00'), findsOneWidget);
    expect(find.text('Costo prom.: —'), findsOneWidget);
  });

  testWidgets('shows exact row values and an honest partial branch summary', (
    tester,
  ) async {
    final summary = InventoryValuationSummary(
      knownValueCents: BigInt.from(5000),
      unknownCostProductCount: 1,
      unknownCostUnitCount: BigInt.from(3),
      invalidStockProductCount: 1,
      precisionAnomalyProductCount: 0,
    );
    await _pumpScreen(
      tester,
      Stream.value([
        {
          'product_id': 'known',
          'product_name': 'Con valor',
          'quantity_on_hand': 10,
          'stock_average_cost': 5,
          'inventory_valuation': InventoryProductValuation.fromStock(
            quantityOnHand: 10,
            averageCost: 5,
          ),
        },
        {
          'product_id': 'unknown',
          'product_name': 'Sin costo',
          'quantity_on_hand': 3,
          'stock_average_cost': null,
          'inventory_valuation': InventoryProductValuation.fromStock(
            quantityOnHand: 3,
            averageCost: null,
          ),
        },
        {
          'product_id': 'invalid',
          'product_name': 'Stock inválido',
          'quantity_on_hand': -1,
          'stock_average_cost': 5,
          'inventory_valuation': InventoryProductValuation.fromStock(
            quantityOnHand: -1,
            averageCost: 5,
          ),
        },
      ]),
      summary: summary,
    );
    await tester.pump();

    expect(find.text('Valor conocido'), findsOneWidget);
    expect(find.text(r'$50.00'), findsOneWidget);
    expect(find.text('Sin costo conocido: 1 producto(s) / 3 unidad(es)'),
        findsOneWidget);
    expect(find.text('Stock inválido: 1 producto(s)'), findsOneWidget);
    expect(find.text(r'Valor: $50.00'), findsOneWidget);
    expect(find.text('Valor: sin costo conocido'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('inventory-content-scroll')),
      const Offset(0, -400),
    );
    await tester.pump();
    expect(find.text('Valor: no disponible'), findsOneWidget);
    expect(find.text('Valor inventario'), findsNothing);
  });

  testWidgets('searches through the application provider and clears results', (
    tester,
  ) async {
    final products = [
      {
        'product_id': 'product-1',
        'product_name': 'Arroz',
        'barcode': '7701234567890',
        'quantity_on_hand': 15,
      },
      {
        'product_id': 'product-2',
        'product_name': 'Cafe',
        'barcode': null,
        'quantity_on_hand': 0,
      },
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryValuationSummaryProvider.overrideWith(
            (ref, key) => Stream.value(InventoryValuationSummary.empty),
          ),
          localProductsWithStockProvider.overrideWith((ref, key) {
            final term = key.searchTerm.trim().toLowerCase();
            if (term.isEmpty) {
              return Stream.value(products);
            }
            if (term == 'arr') {
              return Stream.value([products.first]);
            }
            return Stream.value(const <Map<String, dynamic>>[]);
          }),
        ],
        child: const MaterialApp(
          home: InventoryProductStockListScreen(
            businessId: 'business-1',
            branchId: 'branch-1',
            branchName: 'Principal',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Buscar por nombre o código'), findsOneWidget);
    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Cafe'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('inventory-search-field')),
      'arr',
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Cafe'), findsNothing);
    expect(find.byKey(const Key('inventory-search-clear')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('inventory-search-field')),
      'sin coincidencias',
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('inventory-search-empty')), findsOneWidget);
    expect(find.text('No se encontraron productos'), findsOneWidget);

    await tester.tap(find.byKey(const Key('inventory-search-clear')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Arroz'), findsOneWidget);
    expect(find.text('Cafe'), findsOneWidget);
    expect(find.byKey(const Key('inventory-search-clear')), findsNothing);
  });

  testWidgets('adds a WEIGHT product from master with an exact price per 500 g',
      (tester) async {
    var products = <Map<String, dynamic>>[];
    BusinessProductCreationContext? receivedContext;
    String? receivedCode;
    BusinessProductOwnedFields? receivedFields;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryValuationSummaryProvider.overrideWith(
            (ref, key) => Stream.value(InventoryValuationSummary.empty),
          ),
          localProductsWithStockProvider.overrideWith((ref, key) {
            final term = key.searchTerm.trim().toLowerCase();
            return Stream.value(
              products
                  .where(
                    (product) =>
                        term.isEmpty ||
                        product['product_name']
                            .toString()
                            .toLowerCase()
                            .contains(term),
                  )
                  .toList(growable: false),
            );
          }),
          localMasterProductSearchProvider.overrideWith((ref, key) async {
            if (!key.query.toLowerCase().contains('cafe')) return const [];
            return const [
              {
                'master_product_id': 'master-cafe',
                'master_product_name': 'Cafe master',
                'master_brand': 'Marca global',
                'master_package_unit': 'bolsa',
                'barcode': '7701234567890',
                'barcode_normalized': '7701234567890',
                'barcode_type': 'ean13',
                'existing_product_id': null,
              },
            ];
          }),
          businessProductCreateOrUseProvider.overrideWithValue(({
            required context,
            required fields,
            code,
          }) async {
            receivedContext = context;
            receivedCode = code;
            receivedFields = fields;
            products = [
              {
                'product_id': 'product-cafe',
                'product_name': fields.name,
                'barcode': code,
                'quantity_on_hand': 0,
                'quantity_available': 0,
                'minimum_stock': fields.minimumStock,
                'sale_mode': fields.saleMode.wireValue,
                'sale_price_cents': fields.salePriceCents,
              },
            ];
            return BusinessProductCreationResult(
              outcome: BusinessProductCreationOutcome.createdFromMaster,
              message: 'Producto creado localmente desde el catálogo maestro.',
              productId: 'product-cafe',
              product: {
                'id': 'product-cafe',
                'name': fields.name,
                'master_product_id': 'master-cafe',
              },
              masterProductId: 'master-cafe',
              barcode: code,
              outboxMutationCount: 2,
            );
          }),
        ],
        child: const MaterialApp(
          home: InventoryProductStockListScreen(
            businessId: 'business-1',
            branchId: 'branch-1',
            branchName: 'Principal',
            profileId: 'profile-1',
            appDeviceId: 'device-1',
            deviceInstallationId: 'installation-1',
            effectivePermissions: {'products.create'},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('inventory-add-product')), findsOneWidget);
    await tester.tap(find.byKey(const Key('inventory-add-product')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('inventory-add-product-search')),
      'cafe',
    );
    await tester.pumpAndSettle();

    expect(find.text('Catálogo maestro'), findsOneWidget);
    expect(
      find.textContaining('aún no está en tu inventario'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('inventory-add-master-master-cafe')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Por peso'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('inventory-product-sale-price-field')), '800');
    await tester.pumpAndSettle();
    expect(find.text('Precio de venta por libra (500 g)'), findsOneWidget);
    expect(find.byKey(const Key('inventory-product-product-unit-field')),
        findsNothing);
    await tester.enterText(
        find.byKey(const Key('inventory-product-minimum-stock-field')),
        '1,2345');
    await tester.tap(find.byKey(const Key('inventory-product-create-confirm')));
    await tester.pumpAndSettle();
    expect(
        find.text('Ingresa kilogramos con hasta 3 decimales.'), findsOneWidget);
    await tester.enterText(
        find.byKey(const Key('inventory-product-minimum-stock-field')), '1,5');
    await tester.tap(
      find.byKey(const Key('inventory-product-create-confirm')),
    );
    await tester.pumpAndSettle();

    expect(receivedContext?.businessId, 'business-1');
    expect(receivedContext?.branchId, 'branch-1');
    expect(receivedContext?.profileId, 'profile-1');
    expect(receivedContext?.appDeviceId, 'device-1');
    expect(receivedCode, '7701234567890');
    expect(receivedFields?.saleMode, ProductSaleMode.weight);
    expect(receivedFields?.salePriceCents, 80000);
    expect(receivedFields?.minimumStock, 1500);
    expect(
      find.byKey(const Key('inventory-product-product-cafe')),
      findsOneWidget,
    );
    expect(find.text('Stock: 0 kg'), findsOneWidget);
    expect(find.text(r'$800 / libra'), findsOneWidget);
  });

  testWidgets('edits exact price without offering a mode change',
      (tester) async {
    final controller = StreamController<List<Map<String, dynamic>>>();
    addTearDown(controller.close);
    var product = <String, dynamic>{
      'product_id': 'product-1',
      'product_name': 'Papa',
      'sale_mode': 'unit',
      'sale_price': 800.0,
      'sale_price_cents': 80000,
      'quantity_on_hand': 0,
      'minimum_stock': 0,
    };
    BusinessProductSaleConfigurationUpdateInput? received;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        inventoryValuationSummaryProvider.overrideWith(
          (ref, key) => Stream.value(InventoryValuationSummary.empty),
        ),
        localProductsWithStockProvider
            .overrideWith((ref, key) => controller.stream),
        businessProductSaleConfigurationUpdaterProvider.overrideWithValue(
          (input) async {
            received = input;
            product = {
              ...product,
              'sale_mode': input.saleMode.wireValue,
              'sale_price_cents': input.salePriceCents,
            };
            controller.add([product]);
            return const BusinessProductSaleConfigurationUpdateResult(
              succeeded: true,
              changed: true,
              message: 'Guardado.',
            );
          },
        ),
      ],
      child: const MaterialApp(
          home: InventoryProductStockListScreen(
        businessId: 'business-1',
        branchId: 'branch-1',
        branchName: 'Principal',
        profileId: 'profile-1',
        appDeviceId: 'device-1',
        deviceInstallationId: 'installation-1',
        effectivePermissions: {'products.update'},
      )),
    ));
    controller.add([product]);
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const Key('inventory-edit-sale-config-product-1')));
    await tester.pumpAndSettle();
    expect(find.text('Cambiar precio'), findsWidgets);
    expect(find.byKey(const Key('inventory-edit-sale-mode')), findsNothing);
    await tester.enterText(
        find.byKey(const Key('inventory-edit-sale-price')), '12.000,50');
    await tester.tap(find.byKey(const Key('inventory-edit-sale-save')));
    await tester.pumpAndSettle();
    expect(received?.saleMode, ProductSaleMode.unit);
    expect(received?.salePriceCents, 1200050);
    expect(received?.context.businessId, 'business-1');
    expect(find.text(r'$12.000,50 / unidad'), findsOneWidget);
  });

  testWidgets('marks exhausted products and combines stock filter with search',
      (
    tester,
  ) async {
    final products = <Map<String, dynamic>>[
      {
        'product_id': 'rice-positive',
        'product_name': 'Arroz disponible',
        'quantity_on_hand': 2,
        'quantity_available': 2,
        'minimum_stock': 5,
      },
      {
        'product_id': 'coffee-exhausted',
        'product_name': 'Café agotado',
        'quantity_on_hand': 0,
        'quantity_available': 0,
        'minimum_stock': 0,
      },
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryValuationSummaryProvider.overrideWith(
            (ref, key) => Stream.value(InventoryValuationSummary.empty),
          ),
          localProductsWithStockProvider.overrideWith((ref, key) {
            final term = key.searchTerm.trim().toLowerCase();
            final filtered = products.where((product) {
              final matchesSearch = term.isEmpty ||
                  product['product_name'].toString().toLowerCase().contains(
                        term,
                      );
              final matchesStock =
                  key.stockFilter == InventoryProductStockFilter.all ||
                      (product['quantity_on_hand'] as int) <= 0;
              return matchesSearch && matchesStock;
            }).toList(growable: false);
            return Stream.value(filtered);
          }),
        ],
        child: const MaterialApp(
          home: InventoryProductStockListScreen(
            businessId: 'business-1',
            branchId: 'branch-1',
            branchName: 'Principal',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('inventory-out-of-stock-coffee-exhausted')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('inventory-out-of-stock-rice-positive')),
      findsNothing,
    );
    expect(find.text('Arroz disponible'), findsOneWidget);

    await tester.tap(find.byKey(const Key('inventory-filter-out-of-stock')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Café agotado'), findsOneWidget);
    expect(find.text('Arroz disponible'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('inventory-search-field')),
      'arroz',
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('inventory-search-empty')), findsOneWidget);
    expect(find.text('Café agotado'), findsNothing);
  });

  testWidgets('marks low stock exclusively and combines its filter with search',
      (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final products = <Map<String, dynamic>>[
      {
        'product_id': 'rice-normal',
        'product_name': 'Arroz normal',
        'quantity_on_hand': 6,
        'minimum_stock': 5,
      },
      {
        'product_id': 'coffee-low',
        'product_name': 'Café bajo',
        'quantity_on_hand': 5,
        'minimum_stock': 5,
      },
      {
        'product_id': 'sugar-exhausted',
        'product_name': 'Azúcar agotada',
        'quantity_on_hand': 0,
        'minimum_stock': 5,
      },
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryValuationSummaryProvider.overrideWith(
            (ref, key) => Stream.value(InventoryValuationSummary.empty),
          ),
          localProductsWithStockProvider.overrideWith((ref, key) {
            final term = key.searchTerm.trim().toLowerCase();
            final filtered = products.where((product) {
              final stock = product['quantity_on_hand'] as int;
              final minimum = product['minimum_stock'] as int;
              final matchesSearch = term.isEmpty ||
                  product['product_name'].toString().toLowerCase().contains(
                        term,
                      );
              final matchesStock = switch (key.stockFilter) {
                InventoryProductStockFilter.all => true,
                InventoryProductStockFilter.outOfStock => stock <= 0,
                InventoryProductStockFilter.lowStock =>
                  stock > 0 && stock <= minimum,
              };
              return matchesSearch && matchesStock;
            }).toList(growable: false);
            return Stream.value(filtered);
          }),
        ],
        child: const MaterialApp(
          home: InventoryProductStockListScreen(
            businessId: 'business-1',
            branchId: 'branch-1',
            branchName: 'Principal',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const Key('inventory-low-stock-coffee-low')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('inventory-low-stock-rice-normal')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('inventory-low-stock-sugar-exhausted')),
      findsNothing,
    );
    expect(
      find.byKey(const Key('inventory-out-of-stock-sugar-exhausted')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('inventory-filter-low-stock')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Café bajo'), findsOneWidget);
    expect(find.text('Arroz normal'), findsNothing);
    expect(find.text('Azúcar agotada'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('inventory-search-field')),
      'arroz',
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('inventory-search-empty')), findsOneWidget);
  });

  testWidgets('branch switch changes the visible scoped stock and context', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        inventoryValuationSummaryProvider.overrideWith((ref, key) {
          final cents = key.branchId == 'branch-principal' ? 4005 : 1260;
          return Stream.value(InventoryValuationSummary(
            knownValueCents: BigInt.from(cents),
            unknownCostProductCount: 0,
            unknownCostUnitCount: BigInt.zero,
            invalidStockProductCount: 0,
            precisionAnomalyProductCount: 0,
          ));
        }),
        localProductsWithStockProvider.overrideWith((ref, key) {
          final stock = key.branchId == 'branch-principal' ? 15 : 3;
          final averageCost = key.branchId == 'branch-principal' ? 2.67 : 4.2;
          return Stream.value([
            {
              'product_id': 'product-1',
              'product_name': 'Arroz',
              'quantity_on_hand': stock,
              'stock_average_cost': averageCost,
              'minimum_stock': 5,
            },
          ]);
        }),
      ],
    );
    addTearDown(container.dispose);

    Future<void> pumpBranch(String branchId, String branchName) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: InventoryProductStockListScreen(
              businessId: 'business-1',
              branchId: branchId,
              branchName: branchName,
              effectivePermissions: const {'inventory.view_costs'},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpBranch('branch-principal', 'Principal');
    expect(find.text('Sucursal: Principal'), findsOneWidget);
    expect(find.text('Stock: 15'), findsOneWidget);
    expect(
      find.byKey(const Key('inventory-low-stock-product-1')),
      findsNothing,
    );
    expect(find.text(r'Costo prom.: $2.67'), findsOneWidget);
    expect(find.text('Mínimo: 5'), findsOneWidget);
    expect(find.text(r'$40.05'), findsOneWidget);

    await pumpBranch('branch-vendemas', 'VendeMás');
    expect(find.text('Sucursal: VendeMás'), findsOneWidget);
    expect(find.text('Stock: 3'), findsOneWidget);
    expect(
      find.byKey(const Key('inventory-low-stock-product-1')),
      findsOneWidget,
    );
    expect(find.text(r'Costo prom.: $4.20'), findsOneWidget);
    expect(find.text('Mínimo: 5'), findsOneWidget);
    expect(find.text(r'$12.60'), findsOneWidget);
    expect(find.text(r'$40.05'), findsNothing);
    expect(find.text('Stock: 15'), findsNothing);
    expect(find.text(r'Costo prom.: $2.67'), findsNothing);
  });

  testWidgets('offline minimum-stock edit updates the local stream immediately',
      (
    tester,
  ) async {
    final controller = StreamController<List<Map<String, dynamic>>>();
    addTearDown(controller.close);
    var product = <String, dynamic>{
      'product_id': 'product-1',
      'product_name': 'Arroz',
      'quantity_on_hand': 10,
      'stock_average_cost': 2.67,
      'minimum_stock': 3,
    };

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          inventoryValuationSummaryProvider.overrideWith(
            (ref, key) => Stream.value(InventoryValuationSummary.empty),
          ),
          localProductsWithStockProvider.overrideWith((ref, key) {
            expect(key.businessId, 'business-1');
            expect(key.branchId, 'branch-1');
            return controller.stream;
          }),
          businessProductMinimumStockUpdaterProvider.overrideWithValue((
            input,
          ) async {
            expect(input.context.businessId, 'business-1');
            expect(input.context.branchId, 'branch-1');
            expect(input.context.profileId, 'profile-1');
            expect(input.context.appDeviceId, 'device-1');
            expect(input.context.deviceInstallationId, 'installation-1');
            expect(input.productId, 'product-1');
            expect(input.minimumStock, 5);
            product = {...product, 'minimum_stock': input.minimumStock};
            controller.add([product]);
            return const BusinessProductMinimumStockUpdateResult(
              outcome: BusinessProductMinimumStockUpdateOutcome.updated,
              message: 'Stock mínimo actualizado localmente.',
              minimumStock: 5,
              outboxMutationCount: 1,
            );
          }),
        ],
        child: const MaterialApp(
          home: InventoryProductStockListScreen(
            businessId: 'business-1',
            branchId: 'branch-1',
            branchName: 'Principal',
            profileId: 'profile-1',
            appDeviceId: 'device-1',
            deviceInstallationId: 'installation-1',
            effectivePermissions: {'products.update'},
          ),
        ),
      ),
    );
    controller.add([product]);
    await tester.pump();

    expect(find.text('Mínimo: 3'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('inventory-edit-minimum-stock-product-1')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('inventory-minimum-stock-field')),
      '5',
    );
    await tester.tap(find.byKey(const Key('inventory-minimum-stock-save')));
    await tester.pumpAndSettle();

    expect(find.text('Mínimo: 5'), findsOneWidget);
    expect(find.text('Mínimo: 3'), findsNothing);
    expect(find.text('Stock mínimo actualizado localmente.'), findsOneWidget);
  });

  testWidgets('updates when the local stream emits only a new average cost', (
    tester,
  ) async {
    final controller = StreamController<List<Map<String, dynamic>>>();
    addTearDown(controller.close);

    await _pumpScreen(tester, controller.stream);
    controller.add([
      {
        'product_id': 'product-1',
        'product_name': 'Arroz',
        'quantity_on_hand': 15,
        'stock_average_cost': 2.67,
        'inventory_valuation': InventoryProductValuation.fromStock(
          quantityOnHand: 15,
          averageCost: 2.67,
        ),
      },
    ]);
    await tester.pump();

    expect(find.text('Stock: 15'), findsOneWidget);
    expect(find.text(r'Costo prom.: $2.67'), findsOneWidget);
    expect(find.text(r'Valor: $40.05'), findsOneWidget);

    controller.add([
      {
        'product_id': 'product-1',
        'product_name': 'Arroz',
        'quantity_on_hand': 15,
        'stock_average_cost': 4.5,
        'inventory_valuation': InventoryProductValuation.fromStock(
          quantityOnHand: 15,
          averageCost: 4.5,
        ),
      },
    ]);
    await tester.pump();

    expect(find.text('Stock: 15'), findsOneWidget);
    expect(find.text(r'Costo prom.: $4.50'), findsOneWidget);
    expect(find.text(r'Valor: $67.50'), findsOneWidget);
    expect(find.text(r'Costo prom.: $2.67'), findsNothing);
    expect(find.text(r'Valor: $40.05'), findsNothing);
  });

  testWidgets(
    'cost capability removal hides valuation immediately and preserves stock',
    (tester) async {
      final database = AppDatabase.executor(NativeDatabase.memory());
      addTearDown(database.close);
      final authorizationDao = AuthorizedOperationalContextLocalDao(database);
      final now = DateTime.utc(2026, 9, 23);

      await authorizationDao.replaceContext(
        AuthorizedOperationalContextProjection(
          profileId: 'profile-1',
          businessId: 'business-1',
          branchId: 'branch-1',
          effectivePermissions: const [
            'inventory.read',
            'inventory.view_costs',
          ],
          effectiveRoles: const ['owner'],
          applicableMembershipIds: const ['membership-1'],
          authorizationValidatedAt: now,
          snapshotId: 'snapshot-owner',
        ),
      );

      final product = <String, dynamic>{
        'product_id': 'product-1',
        'product_name': 'Producto protegido',
        'quantity_on_hand': 2,
        'stock_average_cost': 0,
        'inventory_valuation': InventoryProductValuation.fromStock(
          quantityOnHand: 2,
          averageCost: 0,
        ),
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appDatabaseProvider.overrideWithValue(database),
            inventoryValuationSummaryProvider.overrideWith(
              (ref, key) => Stream.value(
                InventoryValuationSummary(
                  knownValueCents: BigInt.zero,
                  unknownCostProductCount: 0,
                  unknownCostUnitCount: BigInt.zero,
                  invalidStockProductCount: 0,
                  precisionAnomalyProductCount: 0,
                ),
              ),
            ),
            localProductsWithStockProvider.overrideWith(
              (ref, key) => Stream.value([product]),
            ),
          ],
          child: const MaterialApp(
            home: InventoryProductStockListScreen(
              businessId: 'business-1',
              branchId: 'branch-1',
              branchName: 'Principal',
              profileId: 'profile-1',
              effectivePermissions: {
                'inventory.read',
                'inventory.view_costs',
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('inventory-valuation-summary')), findsOneWidget);
      expect(find.text(r'Costo prom.: $0.00'), findsOneWidget);
      expect(find.text(r'Valor: $0.00'), findsOneWidget);

      await authorizationDao.replaceContext(
        AuthorizedOperationalContextProjection(
          profileId: 'profile-1',
          businessId: 'business-1',
          branchId: 'branch-1',
          effectivePermissions: const [
            'inventory.read',
            'reports.inventory',
          ],
          effectiveRoles: const ['warehouse'],
          applicableMembershipIds: const ['membership-1'],
          authorizationValidatedAt: now.add(const Duration(minutes: 1)),
          snapshotId: 'snapshot-warehouse',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stock: 2'), findsOneWidget);
      expect(
          find.byKey(const Key('inventory-valuation-summary')), findsNothing);
      expect(
        find.byKey(const Key('inventory-average-cost-product-1')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('inventory-value-product-1')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
    },
  );
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Stream<List<Map<String, dynamic>>> stream, {
  InventoryValuationSummary? summary,
  Set<String> effectivePermissions = const {'inventory.view_costs'},
  bool enableCreation = false,
  List<Map<String, dynamic>> masterMatches = const [],
  Stream<List<Map<String, dynamic>>> Function()? productsStreamFactory,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (enableCreation)
          localMasterProductSearchProvider.overrideWith(
            (ref, key) async => key.query.isEmpty ? const [] : masterMatches,
          ),
        inventoryValuationSummaryProvider.overrideWith(
          (ref, key) =>
              Stream.value(summary ?? InventoryValuationSummary.empty),
        ),
        localProductsWithStockProvider.overrideWith((ref, key) {
          expect(key.businessId, 'business-1');
          expect(key.branchId, 'branch-1');
          expect(key.limit, anyOf(isNull, 20));
          return productsStreamFactory?.call() ?? stream;
        }),
      ],
      child: MaterialApp(
        home: InventoryProductStockListScreen(
          businessId: 'business-1',
          branchId: 'branch-1',
          branchName: 'Principal',
          profileId: enableCreation ? 'profile-1' : null,
          appDeviceId: enableCreation ? 'device-1' : null,
          deviceInstallationId: enableCreation ? 'installation-1' : null,
          effectivePermissions: effectivePermissions,
        ),
      ),
    ),
  );
}
