/// Exact cents for one quoted amount and one quantity, rounded only once.
///
/// The quote is per [basisQuantity] units (1 UNIT, or grams for WEIGHT).
/// Never persist a rounded per-gram price before calling this function.
/// W2B must take the entire remaining cost basis on full stock exhaustion,
/// rather than leave a rounding residue from proportional COGS.
BigInt calculateBasisAmountCents({
  required BigInt baseAmountCents,
  required BigInt quantity,
  required BigInt basisQuantity,
}) {
  if (baseAmountCents < BigInt.zero || quantity < BigInt.zero) {
    throw ArgumentError('Amount and quantity must be non-negative.');
  }
  if (basisQuantity <= BigInt.zero) {
    throw ArgumentError.value(
        basisQuantity, 'basisQuantity', 'Must be positive.');
  }

  final numerator = baseAmountCents * quantity;
  final quotient = numerator ~/ basisQuantity;
  final remainder = numerator % basisQuantity;
  return remainder * BigInt.two >= basisQuantity
      ? quotient + BigInt.one
      : quotient;
}

final BigInt signedInt64Min = BigInt.parse('-9223372036854775808');
final BigInt signedInt64Max = BigInt.parse('9223372036854775807');

/// Checks the SQLite/PostgreSQL BIGINT range before converting for storage.
int checkedSignedInt64(BigInt value) {
  if (value < signedInt64Min || value > signedInt64Max) {
    throw RangeError('Value $value is outside signed BIGINT range.');
  }
  return value.toInt();
}
