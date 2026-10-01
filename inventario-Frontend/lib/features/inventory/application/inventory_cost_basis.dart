import '../../../core/money/exact_basis_money.dart';

/// Quantity uses the product's base unit: UNIT counts or WEIGHT grams.
/// Cost basis is the total exact cost of the remaining stock, never an average.
class InventoryCostBasisState {
  InventoryCostBasisState({
    required this.quantity,
    required this.costBasisCents,
  }) {
    _checkNonNegativeInt64(quantity, 'quantity');
    if (costBasisCents != null) {
      _checkNonNegativeInt64(costBasisCents!, 'costBasisCents');
      if (quantity == BigInt.zero && costBasisCents! > BigInt.zero) {
        throw ArgumentError('Empty stock cannot retain a positive cost basis.');
      }
    }
  }

  final BigInt quantity;
  final BigInt? costBasisCents;
}

class InventoryReceiptCostResult {
  const InventoryReceiptCostResult({
    required this.after,
    required this.costEffectCents,
  });

  final InventoryCostBasisState after;
  // The receipt's cost may be known while aggregate stock cost remains unknown.
  final BigInt costEffectCents;
}

class InventoryIssueCostResult {
  const InventoryIssueCostResult({
    required this.after,
    required this.cogsCents,
    required this.costEffectCents,
  });

  final InventoryCostBasisState after;
  final BigInt? cogsCents;
  final BigInt? costEffectCents;
}

InventoryReceiptCostResult applyCostedReceipt({
  required InventoryCostBasisState before,
  required BigInt incomingQuantity,
  required BigInt incomingCostCents,
}) {
  _checkPositiveInt64(incomingQuantity, 'incomingQuantity');
  _checkNonNegativeInt64(incomingCostCents, 'incomingCostCents');

  final quantityAfter = before.quantity + incomingQuantity;
  checkedSignedInt64(quantityAfter);
  final BigInt? costAfter;
  if (before.quantity == BigInt.zero) {
    // An empty NULL balance has no unknown merchandise left to carry forward.
    costAfter = incomingCostCents;
  } else if (before.costBasisCents == null) {
    costAfter = null;
  } else {
    costAfter = before.costBasisCents! + incomingCostCents;
    checkedSignedInt64(costAfter);
  }

  return InventoryReceiptCostResult(
    after: InventoryCostBasisState(
      quantity: quantityAfter,
      costBasisCents: costAfter,
    ),
    costEffectCents: incomingCostCents,
  );
}

InventoryIssueCostResult applyCostedIssue({
  required InventoryCostBasisState before,
  required BigInt quantityOut,
}) {
  _checkPositiveInt64(quantityOut, 'quantityOut');
  if (quantityOut > before.quantity) {
    throw RangeError('Insufficient stock for costed issue.');
  }

  final quantityAfter = before.quantity - quantityOut;
  if (before.costBasisCents == null) {
    // Historical COGS remains unknown, even when the last stock is removed.
    return InventoryIssueCostResult(
      after: InventoryCostBasisState(
        quantity: quantityAfter,
        costBasisCents: quantityAfter == BigInt.zero ? BigInt.zero : null,
      ),
      cogsCents: null,
      costEffectCents: null,
    );
  }

  final cogs = quantityAfter == BigInt.zero
      ? before.costBasisCents!
      : calculateBasisAmountCents(
          baseAmountCents: before.costBasisCents!,
          quantity: quantityOut,
          basisQuantity: before.quantity,
        );
  final costAfter = before.costBasisCents! - cogs;
  return InventoryIssueCostResult(
    after: InventoryCostBasisState(
      quantity: quantityAfter,
      costBasisCents: costAfter,
    ),
    cogsCents: cogs,
    costEffectCents: -cogs,
  );
}

void _checkNonNegativeInt64(BigInt value, String name) {
  if (value < BigInt.zero) {
    throw ArgumentError.value(value, name, 'Must be non-negative.');
  }
  checkedSignedInt64(value);
}

void _checkPositiveInt64(BigInt value, String name) {
  if (value <= BigInt.zero) {
    throw ArgumentError.value(value, name, 'Must be positive.');
  }
  checkedSignedInt64(value);
}
