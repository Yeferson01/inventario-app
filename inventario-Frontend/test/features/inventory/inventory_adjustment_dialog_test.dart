import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_adjustment_models.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_adjustment_provider.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_cost_visibility_provider.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_valuation_models.dart';
import 'package:inventario_frontend/features/inventory/application/product_stock_balance_providers.dart';
import 'package:inventario_frontend/features/inventory/presentation/screens/inventory_product_stock_list_screen.dart';
import 'package:inventario_frontend/features/inventory/presentation/widgets/inventory_adjustment_dialog.dart';

final _stock = StateProvider<int>((ref) => 10);
final _reserved = StateProvider<int>((ref) => 0);
final _allowed = StateProvider<bool>((ref) => true);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Future<InventoryAdjustmentResult> Function(
          InventoryAdjustmentRequest)
      submit,
  Set<String> permissions = const {'inventory.read', 'inventory.adjust'},
  String product = 'product',
  String branch = 'branch',
}) async {
  final container = ProviderContainer(overrides: [
    inventoryAdjustmentAllowedProvider.overrideWith(
      (ref, scope) => Stream.value(ref.watch(_allowed)),
    ),
    inventoryAdjustmentSubmitProvider.overrideWithValue(submit),
    inventoryCostVisibilityProvider.overrideWith(
      (ref, key) => Stream.value(true),
    ),
    localProductsWithStockProvider.overrideWith((ref, key) {
      final quantity = ref.watch(_stock);
      final reserved = ref.watch(_reserved);
      return Stream.value([
        {
          'product_id': product,
          'product_name': 'Arroz',
          'quantity_on_hand': quantity,
          'quantity_available': quantity - reserved,
          'minimum_stock': 3,
          'stock_average_cost': 2,
          'inventory_valuation': InventoryProductValuation.fromStock(
              quantityOnHand: quantity, averageCost: 2),
        }
      ]);
    }),
    localProductStockBalanceProvider.overrideWith((ref, key) {
      final quantity = ref.watch(_stock);
      final reserved = ref.watch(_reserved);
      return Stream.value({
        'quantity_on_hand': quantity,
        'quantity_available': quantity - reserved,
      });
    }),
    inventoryValuationSummaryProvider.overrideWith((ref, key) {
      final quantity = ref.watch(_stock);
      return Stream.value(InventoryValuationSummary(
        knownValueCents: BigInt.from(quantity * 200),
        unknownCostProductCount: 0,
        unknownCostUnitCount: BigInt.zero,
        invalidStockProductCount: 0,
        precisionAnomalyProductCount: 0,
      ));
    }),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
        home: InventoryProductStockListScreen(
      businessId: 'business',
      branchId: branch,
      branchName: 'Principal',
      profileId: 'profile',
      effectivePermissions: permissions,
    )),
  ));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _open(WidgetTester tester, {String product = 'product'}) async {
  await tester.tap(find.byKey(Key('inventory-adjust-$product')));
  await tester.pumpAndSettle();
}

Future<void> _quantityInput(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(const Key('adjustment-quantity')), value);
  await tester.pumpAndSettle();
}

Future<void> _reason(
    WidgetTester tester, InventoryAdjustmentReason value) async {
  await tester.tap(find.byKey(const Key('adjustment-reason')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(value.label).last);
  await tester.pumpAndSettle();
}

InventoryAdjustmentResult _result(InventoryAdjustmentRequest request) =>
    InventoryAdjustmentResult(
        movementId: request.idempotencyKey,
        previousOnHand: 10,
        resultingOnHand: 10 + request.delta,
        unitCost: 2,
        alreadyApplied: false);

void main() {
  testWidgets('access: authorized action visible, read-only action hidden',
      (tester) async {
    await _pump(tester, submit: (request) async => _result(request));
    expect(find.byKey(const Key('inventory-adjust-product')), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester,
        permissions: const {'inventory.read'},
        submit: (request) async => _result(request));
    expect(find.byKey(const Key('inventory-adjust-product')), findsNothing);
  });

  testWidgets('all eight localized reasons are offered without exposing cost',
      (tester) async {
    await _pump(tester, submit: (request) async => _result(request));
    await _open(tester);
    await tester.tap(find.byKey(const Key('adjustment-reason')));
    await tester.pumpAndSettle();
    for (final reason in InventoryAdjustmentReason.values) {
      expect(find.text(reason.label), findsWidgets);
    }
    expect(find.textContaining('Costo'), findsNothing);
    expect(find.textContaining('Valor:'), findsNothing);
  });

  for (final reason in [
    InventoryAdjustmentReason.expired,
    InventoryAdjustmentReason.gift,
    InventoryAdjustmentReason.internalConsumption,
  ]) {
    testWidgets(
        '${reason.code} submits positive quantity as loss -2 with independent note',
        (tester) async {
      InventoryAdjustmentRequest? received;
      await _pump(tester, submit: (request) async {
        received = request;
        return _result(request);
      });
      await _open(tester);
      if (reason != InventoryAdjustmentReason.expired) {
        await _reason(tester, reason);
      }
      await _quantityInput(tester, '2');
      await tester.enterText(
          find.byKey(const Key('adjustment-note')), 'Estante');
      await tester.pumpAndSettle();
      expect(find.text('Stock: 10 → 8'), findsOneWidget);
      expect(find.textContaining('disminuirá en 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('adjustment-submit')));
      await tester.pumpAndSettle();
      expect(received?.reason, reason);
      expect(received?.quantityOrDelta, 2);
      expect(received?.delta, -2);
      expect(received?.note, 'Estante');
      expect(received?.idempotencyKey.isNotEmpty, true);
      expect(find.text('Ajuste registrado en el dispositivo.'), findsOneWidget);
    });
  }

  for (final increase in [true, false]) {
    testWidgets(
        'manual correction ${increase ? 'increase' : 'decrease'} uses safe direction',
        (tester) async {
      InventoryAdjustmentRequest? received;
      await _pump(tester, submit: (request) async {
        received = request;
        return _result(request);
      });
      await _open(tester);
      await _reason(tester, InventoryAdjustmentReason.manualCorrection);
      if (increase) {
        await tester.tap(find.byKey(const Key('adjustment-direction')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Aumentar stock').last);
        await tester.pumpAndSettle();
      }
      await _quantityInput(tester, '3');
      expect(find.text('Stock: 10 → ${increase ? 13 : 7}'), findsOneWidget);
      await tester.tap(find.byKey(const Key('adjustment-submit')));
      await tester.pumpAndSettle();
      expect(received?.reason, InventoryAdjustmentReason.manualCorrection);
      expect(received?.delta, increase ? 3 : -3);
    });
  }

  for (final quantity in ['0', '-2', '11', 'abc']) {
    testWidgets('invalid loss quantity $quantity is rejected locally',
        (tester) async {
      var calls = 0;
      await _pump(tester, submit: (request) async {
        calls++;
        return _result(request);
      });
      await _open(tester);
      await _quantityInput(tester, quantity);
      await tester.tap(find.byKey(const Key('adjustment-submit')));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byKey(const Key('adjustment-submit')), findsOneWidget);
    });
  }

  testWidgets('reserved stock is protected by UI and by typed service error',
      (tester) async {
    var calls = 0;
    final container = await _pump(tester, submit: (request) async {
      calls++;
      throw const InventoryAdjustmentException(
          InventoryAdjustmentFailure.reservedStockConflict);
    });
    container.read(_reserved.notifier).state = 8;
    await tester.pumpAndSettle();
    await _open(tester);
    await _quantityInput(tester, '4');
    await tester.tap(find.byKey(const Key('adjustment-submit')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('reservado'), findsWidgets);
    container.read(_reserved.notifier).state = 0;
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adjustment-submit')));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Parte del stock está reservado y no puede descontarse.'),
        findsOneWidget);
  });

  testWidgets('revocation while dialog is open prevents submit',
      (tester) async {
    var calls = 0;
    final container = await _pump(tester, submit: (request) async {
      calls++;
      return _result(request);
    });
    await _open(tester);
    await _quantityInput(tester, '2');
    container.read(_allowed.notifier).state = false;
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('adjustment-submit')), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('adjustment-submit')))
            .onPressed,
        isNull);
    expect(calls, 0);
  });

  testWidgets('single-flight prevents double tap and retains one key',
      (tester) async {
    final completer = Completer<InventoryAdjustmentResult>();
    final seen = <InventoryAdjustmentRequest>[];
    await _pump(tester, submit: (request) {
      seen.add(request);
      return completer.future;
    });
    await _open(tester);
    await _quantityInput(tester, '2');
    await tester.tap(find.byKey(const Key('adjustment-submit')));
    await tester.pump();
    expect(find.text('Registrando…'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('adjustment-submit')))
            .onPressed,
        isNull);
    expect(seen, hasLength(1));
    await tester.pump();
    expect(seen.single.idempotencyKey, isNotEmpty);
    completer.complete(_result(seen.single));
    await tester.pumpAndSettle();
    expect(seen, hasLength(1));
  });

  testWidgets(
      'ambiguous retry keeps the exact request/key after rebuild and balance change',
      (tester) async {
    final seen = <InventoryAdjustmentRequest>[];
    final container = await _pump(tester, submit: (request) async {
      seen.add(request);
      if (seen.length == 1) throw StateError('unknown result');
      return _result(request);
    });
    await _open(tester);
    await _quantityInput(tester, '2');
    await tester.tap(find.byKey(const Key('adjustment-submit')));
    await tester.pumpAndSettle();
    container.read(_stock.notifier).state = 8;
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('adjustment-quantity')))
            .enabled,
        false);
    await tester.tap(find.byKey(const Key('adjustment-submit')));
    await tester.pumpAndSettle();
    expect(seen, hasLength(2));
    expect(identical(seen.first, seen.last), true);
  });

  testWidgets(
      'definite rejection allows edits as a new intention and next success gets a new key',
      (tester) async {
    final seen = <InventoryAdjustmentRequest>[];
    await _pump(tester, submit: (request) async {
      seen.add(request);
      if (seen.length == 1) {
        throw const InventoryAdjustmentException(
            InventoryAdjustmentFailure.insufficientStock);
      }
      return _result(request);
    });
    await _open(tester);
    await _quantityInput(tester, '2');
    await tester.tap(find.byKey(const Key('adjustment-submit')));
    await tester.pumpAndSettle();
    expect(find.text('No hay suficiente stock para realizar este ajuste.'),
        findsOneWidget);
    await _quantityInput(tester, '1');
    await tester.tap(find.byKey(const Key('adjustment-submit')));
    await tester.pumpAndSettle();
    expect(seen, hasLength(2));
    expect(seen.first.idempotencyKey, isNot(seen.last.idempotencyKey));
    await _open(tester);
    await _quantityInput(tester, '1');
    await tester.tap(find.byKey(const Key('adjustment-submit')));
    await tester.pumpAndSettle();
    expect(seen, hasLength(3));
    expect(seen.last.idempotencyKey, isNot(seen[1].idempotencyKey));
  });

  for (final failure in [
    InventoryAdjustmentFailure.permissionDenied,
    InventoryAdjustmentFailure.invalidProduct,
    InventoryAdjustmentFailure.idempotencyConflict,
  ]) {
    testWidgets('typed $failure maps to a safe Spanish message',
        (tester) async {
      await _pump(tester,
          submit: (_) async => throw InventoryAdjustmentException(failure));
      await _open(tester);
      await _quantityInput(tester, '2');
      await tester.tap(find.byKey(const Key('adjustment-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('adjustment-error')), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });
  }

  testWidgets('context switch and different product do not submit old scope',
      (tester) async {
    var calls = 0;
    await _pump(tester, submit: (request) async {
      calls++;
      return _result(request);
    });
    await _open(tester);
    await _quantityInput(tester, '2');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(calls, 0);
    await _pump(tester, product: 'another', branch: 'other',
        submit: (request) async {
      calls++;
      return _result(request);
    });
    expect(find.byKey(const Key('inventory-adjust-product')), findsNothing);
    await _open(tester, product: 'another');
    expect(find.byKey(const Key('adjustment-quantity')), findsOneWidget);
    expect(find.text('Stock: 10 → 8'), findsNothing);
  });

  testWidgets('switching branch while the dialog is open rejects its old scope',
      (tester) async {
    var calls = 0;
    final container = await _pump(tester, submit: (request) async {
      calls++;
      return _result(request);
    });
    await _open(tester);
    await _quantityInput(tester, '2');
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: InventoryProductStockListScreen(
          businessId: 'business',
          branchId: 'other',
          branchName: 'Otra',
          profileId: 'profile',
          effectivePermissions: {'inventory.read', 'inventory.adjust'},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('adjustment-submit')));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('este contexto'), findsOneWidget);
  });

  testWidgets(
      'offline success reacts to stock and low/out alert without cost disclosure',
      (tester) async {
    late ProviderContainer container;
    container = await _pump(tester, submit: (request) async {
      container.read(_stock.notifier).state += request.delta;
      return _result(request);
    });
    await _open(tester);
    await _quantityInput(tester, '7');
    await tester.tap(find.byKey(const Key('adjustment-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Stock: 3'), findsOneWidget);
    expect(
        find.byKey(const Key('inventory-low-stock-product')), findsOneWidget);
    await _open(tester);
    await _quantityInput(tester, '3');
    await tester.tap(find.byKey(const Key('adjustment-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Stock: 0'), findsOneWidget);
    expect(find.byKey(const Key('inventory-out-of-stock-product')),
        findsOneWidget);
    expect(find.textContaining('Costo'), findsNothing);
    expect(find.textContaining('Se requiere conexión'), findsNothing);
  });

  testWidgets('authorized valuation reacts to the same local stock update',
      (tester) async {
    late ProviderContainer container;
    container = await _pump(tester, permissions: const {
      'inventory.read',
      'inventory.adjust',
      'inventory.view_costs'
    }, submit: (request) async {
      container.read(_stock.notifier).state += request.delta;
      return _result(request);
    });
    expect(find.text(r'Valor: $20.00'), findsOneWidget);
    await _open(tester);
    await _quantityInput(tester, '2');
    await tester.tap(find.byKey(const Key('adjustment-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Stock: 8'), findsOneWidget);
    expect(find.text(r'Valor: $16.00'), findsOneWidget);
  });
}
