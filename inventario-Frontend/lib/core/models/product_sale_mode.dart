enum ProductSaleMode {
  unit('unit', 1),
  weight('weight', 500);

  const ProductSaleMode(this.wireValue, this.salePriceBasisQuantity);

  final String wireValue;
  // UNIT count or grams for WEIGHT. One commercial pound is exactly 500 g.
  final int salePriceBasisQuantity;

  String get displayLabel => switch (this) {
        ProductSaleMode.unit => 'Por unidad',
        ProductSaleMode.weight => 'Por peso',
      };

  String get priceBasisLabel => switch (this) {
        ProductSaleMode.unit => 'por unidad',
        ProductSaleMode.weight => 'por libra (500 g)',
      };

  static ProductSaleMode parse(Object? value) => switch (value) {
        'unit' => ProductSaleMode.unit,
        'weight' => ProductSaleMode.weight,
        _ => throw FormatException('Unsupported product sale_mode: $value'),
      };
}

/// Parse PostgreSQL bigint JSON without converting through floating point.
/// NULL is the intentional legacy/undetermined state.
int? parseNullableExactCents(Object? value, String field) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is String && RegExp(r'^-?[0-9]+$').hasMatch(value)) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException(
      '$field must be an exact signed 64-bit integer or null.');
}
