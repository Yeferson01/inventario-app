import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/cash/application/cash_movement_models.dart';
import 'package:inventario_frontend/features/cash/presentation/widgets/cash_movement_dialog.dart';

void main() {
  test('COP parsing is exact and rejects decimals, zero and ambiguity', () {
    for (final input in ['50000', '50.000', '50,000']) {
      expect(parseCashMovementCopCents(input), BigInt.from(5000000));
    }
    for (final input in ['', '0', '-1', '1.50', '1,50', 'NaN', '50.00.0']) {
      expect(parseCashMovementCopCents(input), isNull, reason: input);
    }
    expect(formatCashMovementCopCents(BigInt.from(5000025)), r'$ 50.000,25');
    expect(formatCashMovementCopCents(BigInt.from(-100)), r'-$ 1');
  });

  test('cash movement errors use safe, actionable Spanish copy', () {
    expect(
      cashMovementErrorMessage(
        const CashMovementException(CashMovementFailure.invalidSession),
        CashMovementDirection.inflow,
      ),
      'La sesión de caja ya no está abierta.',
    );
    expect(
      cashMovementErrorMessage(
        const CashMovementException(CashMovementFailure.idempotencyConflict),
        CashMovementDirection.outflow,
      ),
      contains('Revisa los datos'),
    );
    expect(
      cashMovementErrorMessage(
        const CashMovementException(CashMovementFailure.insufficientCash),
        CashMovementDirection.outflow,
      ),
      contains('Registra primero una entrada'),
    );
    expect(
      cashMovementErrorMessage(
          StateError('internal SQL detail'), CashMovementDirection.inflow),
      isNot(contains('internal SQL detail')),
    );
  });

  testWidgets('direction only offers compatible C2 categories', (tester) async {
    await _openDialog(tester, CashMovementDirection.outflow);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Compra a proveedor'), findsOneWidget);
    expect(find.text('Retiro del propietario'), findsOneWidget);
    expect(find.text('Otro'), findsOneWidget);
    expect(find.text('Aporte del propietario'), findsNothing);
    await tester.tap(find.text('Otro').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await _openDialog(tester, CashMovementDirection.inflow);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Aporte del propietario'), findsOneWidget);
    expect(find.text('Otro ingreso'), findsOneWidget);
    expect(find.text('Otro'), findsOneWidget);
    expect(find.text('Compra a proveedor'), findsNothing);
    expect(find.text('Retiro del propietario'), findsNothing);
  });

  testWidgets('outflow preview, confirmation and single-flight use one key',
      (tester) async {
    final pending = Completer<CashMovementResult>();
    final requests = <CashMovementRequest>[];
    await _openDialog(
      tester,
      CashMovementDirection.outflow,
      expected: () async => BigInt.from(10000000),
      submit: (request) {
        requests.add(request);
        return pending.future;
      },
    );
    await _enterMovement(tester, amount: '20.000', category: 'Otro');
    expect(find.text('Después del movimiento: \$ 80.000'), findsOneWidget);
    await tester.tap(find.text('Registrar movimiento'));
    await tester.pumpAndSettle();
    expect(find.textContaining('¿Registrar movimiento?'), findsOneWidget);
    expect(find.textContaining(r'$ 100.000 → $ 80.000'), findsOneWidget);
    await tester.tap(find.text('Confirmar'));
    await tester.pump();
    expect(requests, hasLength(1));
    expect(requests.single.amountCents, BigInt.from(2000000));
    expect(requests.single.direction, CashMovementDirection.outflow);
    expect(requests.single.category, 'other');
    expect(requests.single.sourceType, 'manual');
    expect(requests.single.sourceId, isNull);
    expect(requests.single.idempotencyKey, isNotEmpty);
    expect(find.text('Registrando movimiento…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Registrar movimiento'),
          )
          .onPressed,
      isNull,
    );
    pending.complete(
        const CashMovementResult(id: 'movement-a', alreadyRecorded: false));
    await tester.pumpAndSettle();
    expect(requests, hasLength(1));
    expect(find.byType(CashMovementDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ambiguous retry keeps key; semantic edit creates new intent',
      (tester) async {
    final requests = <CashMovementRequest>[];
    await _openDialog(
      tester,
      CashMovementDirection.inflow,
      submit: (request) async {
        requests.add(request);
        throw StateError('ambiguous local completion');
      },
    );
    await _enterMovement(tester, amount: '5.000', category: 'Otro');
    await _confirm(tester);
    expect(requests, hasLength(1));
    expect(find.textContaining('No se pudo registrar'), findsOneWidget);
    await _confirm(tester);
    expect(requests, hasLength(2));
    expect(requests[1].idempotencyKey, requests[0].idempotencyKey);
    await tester.enterText(find.byType(TextField).first, '6.000');
    await tester.pumpAndSettle();
    await _confirm(tester);
    expect(requests, hasLength(3));
    expect(requests[2].idempotencyKey, isNot(requests[0].idempotencyKey));
    expect(requests[2].amountCents, BigInt.from(600000));
  });

  testWidgets('new form after success creates a new intention key',
      (tester) async {
    final keys = <String>[];
    Future<CashMovementResult> save(CashMovementRequest request) async {
      keys.add(request.idempotencyKey);
      return CashMovementResult(
          id: 'movement-${keys.length}', alreadyRecorded: false);
    }

    await _openDialog(tester, CashMovementDirection.inflow, submit: save);
    await _enterMovement(tester, amount: '1.000', category: 'Otro');
    await _confirm(tester);
    expect(find.byType(CashMovementDialog), findsNothing);
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await _enterMovement(tester, amount: '1.000', category: 'Otro');
    await _confirm(tester);
    expect(keys, hasLength(2));
    expect(keys[1], isNot(keys[0]));
  });

  testWidgets('permission revoked while open blocks submit with human error',
      (tester) async {
    var reads = 0;
    var submissions = 0;
    await _openDialog(
      tester,
      CashMovementDirection.outflow,
      expected: () async {
        reads++;
        if (reads > 1) {
          throw const CashMovementException(
              CashMovementFailure.permissionDenied);
        }
        return BigInt.from(10000000);
      },
      submit: (_) async {
        submissions++;
        return const CashMovementResult(id: 'wrong', alreadyRecorded: false);
      },
    );
    await _enterMovement(tester, amount: '1.000', category: 'Otro');
    await tester.tap(find.text('Registrar movimiento'));
    await tester.pumpAndSettle();
    expect(submissions, 0);
    expect(
        find.text('No tienes permiso para registrar esta salida de efectivo.'),
        findsOneWidget);
  });

  testWidgets('changed session is rejected before submission', (tester) async {
    var reads = 0;
    var submissions = 0;
    await _openDialog(
      tester,
      CashMovementDirection.inflow,
      expected: () async {
        reads++;
        if (reads > 1) {
          throw const CashMovementException(CashMovementFailure.invalidContext);
        }
        return BigInt.from(10000000);
      },
      submit: (_) async {
        submissions++;
        return const CashMovementResult(id: 'wrong', alreadyRecorded: false);
      },
    );
    await _enterMovement(tester, amount: '1.000', category: 'Otro');
    await tester.tap(find.text('Registrar movimiento'));
    await tester.pumpAndSettle();
    expect(submissions, 0);
    expect(
        find.text(
            'La caja activa cambió. Cierra este formulario y vuelve a intentarlo.'),
        findsOneWidget);
  });

  testWidgets('outflow above expected is blocked before confirmation',
      (tester) async {
    await _openDialog(
      tester,
      CashMovementDirection.outflow,
      expected: () async => BigInt.from(100000),
    );
    await _enterMovement(tester, amount: '1.001', category: 'Otro');
    expect(find.text('Después del movimiento: -\$ 1'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Registrar movimiento'),
          )
          .onPressed,
      isNull,
    );
  });
}

Future<void> _openDialog(
  WidgetTester tester,
  CashMovementDirection direction, {
  Future<BigInt> Function()? expected,
  Future<CashMovementResult> Function(CashMovementRequest)? submit,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      return Scaffold(
        body: TextButton(
          onPressed: () => showDialog<bool>(
            context: context,
            builder: (_) => CashMovementDialog(
              profileId: 'profile-a',
              businessId: 'business-a',
              branchId: 'branch-a',
              cashRegisterId: 'register-a',
              cashSessionId: 'session-a',
              direction: direction,
              loadExpectedCashCents:
                  expected ?? () async => BigInt.from(10000000),
              submit: submit ??
                  (_) async => const CashMovementResult(
                        id: 'movement-a',
                        alreadyRecorded: false,
                      ),
            ),
          ),
          child: const Text('Abrir'),
        ),
      );
    }),
  ));
  await tester.tap(find.text('Abrir'));
  await tester.pumpAndSettle();
}

Future<void> _enterMovement(
  WidgetTester tester, {
  required String amount,
  required String category,
}) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(category).last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, amount);
  await tester.pumpAndSettle();
}

Future<void> _confirm(WidgetTester tester) async {
  await tester.tap(find.text('Registrar movimiento'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirmar'));
  await tester.pumpAndSettle();
}
