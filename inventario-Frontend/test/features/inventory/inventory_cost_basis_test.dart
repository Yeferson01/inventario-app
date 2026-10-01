import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/money/exact_basis_money.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_cost_basis.dart';

BigInt b(int value) => BigInt.from(value);
InventoryCostBasisState state(int quantity, int? cost) =>
    InventoryCostBasisState(
      quantity: b(quantity),
      costBasisCents: cost == null ? null : b(cost),
    );

void main() {
  test('empty receipt, known receipt, and changing purchase costs add bases',
      () {
    final first = applyCostedReceipt(
      before: state(0, 0),
      incomingQuantity: b(3000),
      incomingCostCents: b(480000),
    );
    expect(first.after.quantity, b(3000));
    expect(first.after.costBasisCents, b(480000));
    expect(first.costEffectCents, b(480000));
    final higher = applyCostedReceipt(
      before: first.after,
      incomingQuantity: b(10000),
      incomingCostCents: b(1800000),
    );
    expect(higher.after.quantity, b(13000));
    expect(higher.after.costBasisCents, b(2280000));
    expect(higher.costEffectCents, b(1800000));

    final lower = applyCostedReceipt(
      before: state(2000, 400000),
      incomingQuantity: b(10000),
      incomingCostCents: b(1600000),
    );
    expect(lower.after.quantity, b(12000));
    expect(lower.after.costBasisCents, b(2000000));
  });

  test('successive receipts never round an intermediate average', () {
    var current = state(0, 0);
    for (final (quantity, cost) in [
      (10000, 1800000),
      (5000, 800000),
      (3000, 600000),
    ]) {
      current = applyCostedReceipt(
        before: current,
        incomingQuantity: b(quantity),
        incomingCostCents: b(cost),
      ).after;
    }
    expect(current.quantity, b(18000));
    expect(current.costBasisCents, b(3200000));
  });

  test('partial issue delegates to W2A and conserves quantity and cents', () {
    final before = state(13000, 2280000);
    final result = applyCostedIssue(before: before, quantityOut: b(735));
    final exact = calculateBasisAmountCents(
      baseAmountCents: before.costBasisCents!,
      quantity: b(735),
      basisQuantity: before.quantity,
    );
    expect(result.cogsCents, exact);
    expect(result.cogsCents, b(128908));
    expect(result.after.quantity, b(12265));
    expect(result.after.costBasisCents, b(2151092));
    expect(result.costEffectCents, -exact);
    expect(result.after.quantity + b(735), before.quantity);
    expect(result.after.costBasisCents! + result.cogsCents!,
        before.costBasisCents);
    expect(result.cogsCents! >= BigInt.zero, isTrue);
    expect(result.cogsCents! <= before.costBasisCents!, isTrue);
  });

  test('full depletion takes all remaining cents', () {
    final result = applyCostedIssue(
      before: state(3, 1),
      quantityOut: b(3),
    );
    expect(result.cogsCents, BigInt.one);
    expect(result.after.quantity, BigInt.zero);
    expect(result.after.costBasisCents, BigInt.zero);
    expect(result.costEffectCents, -BigInt.one);
  });

  test('known zero cost stays distinct from unknown cost', () {
    final partial = applyCostedIssue(
      before: state(500, 0),
      quantityOut: b(200),
    );
    expect(partial.cogsCents, BigInt.zero);
    expect(partial.after.costBasisCents, BigInt.zero);
    final full = applyCostedIssue(
      before: state(500, 0),
      quantityOut: b(500),
    );
    expect(full.cogsCents, BigInt.zero);
    expect(full.costEffectCents, BigInt.zero);
  });

  test('unknown partial and full issues never invent historical COGS', () {
    final partial = applyCostedIssue(
      before: state(500, null),
      quantityOut: b(200),
    );
    expect(partial.after.quantity, b(300));
    expect(partial.after.costBasisCents, isNull);
    expect(partial.cogsCents, isNull);
    expect(partial.costEffectCents, isNull);
    final full = applyCostedIssue(
      before: state(500, null),
      quantityOut: b(500),
    );
    expect(full.after.quantity, BigInt.zero);
    expect(full.after.costBasisCents, BigInt.zero);
    expect(full.cogsCents, isNull);
    expect(full.costEffectCents, isNull);
  });

  test('known receipt on unknown stock keeps aggregate unknown', () {
    final receipt = applyCostedReceipt(
      before: state(500, null),
      incomingQuantity: b(100),
      incomingCostCents: b(8000),
    );
    expect(receipt.after.quantity, b(600));
    expect(receipt.after.costBasisCents, isNull);
    expect(receipt.costEffectCents, b(8000));
  });

  test('empty NULL legacy balance becomes valuated by known receipt', () {
    final receipt = applyCostedReceipt(
      before: state(0, null),
      incomingQuantity: b(100),
      incomingCostCents: b(8000),
    );
    expect(receipt.after.quantity, b(100));
    expect(receipt.after.costBasisCents, b(8000));
  });

  test('insufficient stock and invalid states fail closed', () {
    expect(
        () => applyCostedIssue(
              before: state(5, 10),
              quantityOut: b(6),
            ),
        throwsRangeError);
    expect(() => state(-1, 0), throwsArgumentError);
    expect(() => state(1, -1), throwsArgumentError);
    expect(() => state(0, 1), throwsArgumentError);
    expect(
        () => applyCostedReceipt(
              before: state(0, 0),
              incomingQuantity: BigInt.zero,
              incomingCostCents: BigInt.zero,
            ),
        throwsArgumentError);
    expect(
        () => applyCostedReceipt(
              before: state(0, 0),
              incomingQuantity: b(-1),
              incomingCostCents: BigInt.zero,
            ),
        throwsArgumentError);
    expect(
        () => applyCostedReceipt(
              before: state(0, 0),
              incomingQuantity: BigInt.one,
              incomingCostCents: b(-1),
            ),
        throwsArgumentError);
    expect(
        () => applyCostedIssue(
              before: state(5, 10),
              quantityOut: BigInt.zero,
            ),
        throwsArgumentError);
  });

  test('large safe values and both receipt overflows are explicit', () {
    final safe = applyCostedReceipt(
      before: state(0, 0),
      incomingQuantity: signedInt64Max,
      incomingCostCents: signedInt64Max,
    );
    expect(safe.after.quantity, signedInt64Max);
    expect(safe.after.costBasisCents, signedInt64Max);
    expect(
        () => applyCostedReceipt(
              before: InventoryCostBasisState(
                quantity: signedInt64Max,
                costBasisCents: BigInt.zero,
              ),
              incomingQuantity: BigInt.one,
              incomingCostCents: BigInt.zero,
            ),
        throwsRangeError);
    expect(
        () => applyCostedReceipt(
              before: InventoryCostBasisState(
                quantity: BigInt.one,
                costBasisCents: signedInt64Max,
              ),
              incomingQuantity: BigInt.one,
              incomingCostCents: BigInt.one,
            ),
        throwsRangeError);
  });

  test('W2A purchase quote is passed to W2B as exact incoming cost', () {
    final incomingCost = calculateBasisAmountCents(
      baseAmountCents: b(80000),
      quantity: b(10000),
      basisQuantity: b(500),
    );
    expect(incomingCost, b(1600000));
    final receipt = applyCostedReceipt(
      before: state(0, 0),
      incomingQuantity: b(10000),
      incomingCostCents: incomingCost,
    );
    expect(receipt.after.costBasisCents, b(1600000));
  });
}
