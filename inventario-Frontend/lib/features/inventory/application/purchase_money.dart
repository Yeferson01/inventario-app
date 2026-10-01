import '../../../core/money/exact_basis_money.dart';

/// Exact documentary purchase money. The current Hosted numeric(12,2)
/// contract permits at most 9,999,999,999.99 in each monetary field.
const int purchaseMoneyMaxCents = 999999999999;

BigInt? parsePurchaseMoneyCents(String input) {
  final match = RegExp(r'^(0|[1-9][0-9]*)(?:[.,]([0-9]{1,2}))?$')
      .firstMatch(input.trim());
  if (match == null) return null;
  final whole = BigInt.parse(match.group(1)!);
  final fractionText = match.group(2);
  final fraction =
      BigInt.parse(fractionText == null ? '0' : fractionText.padRight(2, '0'));
  final cents = whole * BigInt.from(100) + fraction;
  return cents <= BigInt.from(purchaseMoneyMaxCents) ? cents : null;
}

String formatPurchaseMoneyCents(BigInt cents) {
  final whole = cents ~/ BigInt.from(100);
  final fraction = (cents % BigInt.from(100)).toString().padLeft(2, '0');
  return '$whole.$fraction';
}

BigInt purchaseLineTotalCents(BigInt unitCostCents, int quantity) {
  return purchaseBasisLineTotalCents(
    quotedCostCents: unitCostCents,
    quantity: quantity,
    costBasisQuantity: 1,
  );
}

/// [quotedCostCents] is per [costBasisQuantity] base units: one UNIT, or
/// 500/1000 grams for WEIGHT. It is never a rounded per-gram cost.
BigInt purchaseBasisLineTotalCents({
  required BigInt quotedCostCents,
  required int quantity,
  required int costBasisQuantity,
}) {
  if (quantity <= 0 ||
      quotedCostCents < BigInt.zero ||
      quotedCostCents > BigInt.from(purchaseMoneyMaxCents) ||
      costBasisQuantity <= 0) {
    throw ArgumentError('Invalid purchase quantity, basis or quoted cost.');
  }
  final total = calculateBasisAmountCents(
    baseAmountCents: quotedCostCents,
    quantity: BigInt.from(quantity),
    basisQuantity: BigInt.from(costBasisQuantity),
  );
  if (total > BigInt.from(purchaseMoneyMaxCents)) {
    throw RangeError('Purchase line exceeds numeric(12,2) range.');
  }
  return total;
}
