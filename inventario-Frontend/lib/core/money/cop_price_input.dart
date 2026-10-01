/// Parses a Colombian peso amount into exact integer cents.
///
/// A dot groups thousands and a comma separates at most two decimal digits.
/// Unseparated digits are whole pesos. Ambiguous dot-decimal input is rejected.
int? parseCopPriceCents(String input) {
  final text = input.trim().replaceAll(RegExp(r'^\$\s*'), '');
  final match =
      RegExp(r'^(?:[0-9]+|[1-9][0-9]{0,2}(?:\.[0-9]{3})+)(?:,([0-9]{1,2}))?$')
          .firstMatch(text);
  if (match == null) return null;
  final pesos = BigInt.tryParse(text.split(',').first.replaceAll('.', ''));
  if (pesos == null) return null;
  final decimal = match.group(1);
  final centavos = decimal == null ? 0 : int.parse(decimal.padRight(2, '0'));
  final cents = pesos * BigInt.from(100) + BigInt.from(centavos);
  // Hosted products.sale_price NUMERIC(12,2).
  if (cents > BigInt.from(999999999999)) return null;
  return cents.toInt();
}

/// Exact decimal text for the legacy NUMERIC(12,2) sync field.
String exactPesosFromCents(int cents) {
  if (cents < 0 || cents > 999999999999) {
    throw RangeError.value(cents, 'cents');
  }
  return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
}

String formatCopPriceCents(int cents) {
  final pesos = (cents ~/ 100).toString();
  final grouped = pesos.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final fraction = cents % 100;
  return fraction == 0
      ? '\$$grouped'
      : '\$$grouped,${fraction.toString().padLeft(2, '0')}';
}
