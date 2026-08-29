import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
          'legacy_stock_quantity': 999,
        },
        {
          'product_id': 'product-2',
          'product_name': 'Café',
          'barcode': null,
          'quantity_on_hand': 0,
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
    expect(find.text('Stock: 999'), findsNothing);
    expect(find.text('Stock: 40'), findsNothing);
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

  testWidgets('branch switch changes the visible scoped stock and context', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        localProductsWithStockProvider.overrideWith((ref, key) {
          final stock = key.branchId == 'branch-principal' ? 8 : 3;
          return Stream.value([
            {
              'product_id': 'product-1',
              'product_name': 'Arroz',
              'quantity_on_hand': stock,
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
    expect(find.text('Stock: 8'), findsOneWidget);

    await pumpBranch('branch-vendemas', 'VendeMás');
    expect(find.text('Sucursal: VendeMás'), findsOneWidget);
    expect(find.text('Stock: 3'), findsOneWidget);
    expect(find.text('Stock: 8'), findsNothing);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  Stream<List<Map<String, dynamic>>> stream,
) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
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
