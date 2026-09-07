import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/inventory/application/business_product_creation_models.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_product_providers.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_valuation_models.dart';
import 'package:inventario_frontend/features/inventory/application/product_stock_balance_providers.dart';
import 'package:inventario_frontend/features/inventory/presentation/screens/inventory_product_stock_list_screen.dart';

void main() {
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
    expect(find.textContaining('fallo local'), findsOneWidget);
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

    expect(find.byKey(const Key('inventory-product-list')), findsOneWidget);
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
      find.byKey(const Key('inventory-product-list')),
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
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Stream<List<Map<String, dynamic>>> stream, {
  InventoryValuationSummary? summary,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryValuationSummaryProvider.overrideWith(
          (ref, key) =>
              Stream.value(summary ?? InventoryValuationSummary.empty),
        ),
        localProductsWithStockProvider.overrideWith((ref, key) {
          expect(key.businessId, 'business-1');
          expect(key.branchId, 'branch-1');
          expect(key.limit, isNull);
          return stream;
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
}
