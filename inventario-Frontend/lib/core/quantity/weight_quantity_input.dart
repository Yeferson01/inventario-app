import '../money/exact_basis_money.dart';

/// Input units only. Inventory always stores a WEIGHT quantity as whole grams.
enum WeightInputUnit { gram, kilogram, commercialPound }

/// Parses a positive weight without floating point or implicit rounding.
/// A dot or comma is a decimal separator, never a thousands separator.
int? parseWeightQuantity(String text, WeightInputUnit unit) {
  final input = text.trim();
  final decimalPlaces = switch (unit) {
    WeightInputUnit.gram => 0,
    WeightInputUnit.kilogram => 3,
    WeightInputUnit.commercialPound => 2,
  };
  final pattern = decimalPlaces == 0
      ? RegExp(r'^[0-9]+$')
      : RegExp('^[0-9]+(?:[.,][0-9]{1,$decimalPlaces})?\$');
  if (!pattern.hasMatch(input)) return null;

  final parts = input.replaceAll(',', '.').split('.');
  final whole = BigInt.parse(parts.first);
  final fraction = parts.length == 1
      ? BigInt.zero
      : BigInt.parse(parts.last.padRight(decimalPlaces, '0'));
  final grams = switch (unit) {
    WeightInputUnit.gram => whole,
    WeightInputUnit.kilogram => whole * BigInt.from(1000) + fraction,
    // One commercial pound is 500 g; 0.01 pound is exactly 5 g.
    WeightInputUnit.commercialPound =>
      whole * BigInt.from(500) + fraction * BigInt.from(5),
  };
  if (grams <= BigInt.zero || grams > signedInt64Max) return null;
  return grams.toInt();
}
