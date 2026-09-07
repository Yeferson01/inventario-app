enum InventoryProductValuationStatus {
  known,
  unknownCost,
  invalidStock,
  precisionAnomaly,
}

class InventoryProductValuation {
  const InventoryProductValuation._({
    required this.status,
    required this.quantityOnHand,
    required this.averageCostCents,
    required this.valueCents,
  });

  static final BigInt _maximumAverageCostCents = BigInt.parse('99999999999999');

  final InventoryProductValuationStatus status;
  final int quantityOnHand;
  final BigInt? averageCostCents;
  final BigInt? valueCents;

  bool get isKnown => status == InventoryProductValuationStatus.known;

  factory InventoryProductValuation.fromStock({
    required int quantityOnHand,
    required Object? averageCost,
  }) {
    if (quantityOnHand < 0) {
      return InventoryProductValuation._(
        status: InventoryProductValuationStatus.invalidStock,
        quantityOnHand: quantityOnHand,
        averageCostCents: null,
        valueCents: null,
      );
    }

    if (quantityOnHand == 0) {
      return InventoryProductValuation._(
        status: InventoryProductValuationStatus.known,
        quantityOnHand: quantityOnHand,
        averageCostCents: null,
        valueCents: BigInt.zero,
      );
    }

    if (averageCost == null) {
      return InventoryProductValuation._(
        status: InventoryProductValuationStatus.unknownCost,
        quantityOnHand: quantityOnHand,
        averageCostCents: null,
        valueCents: null,
      );
    }

    final parsedCost = averageCost is num
        ? averageCost.toDouble()
        : double.tryParse(averageCost.toString());
    if (parsedCost == null || !parsedCost.isFinite || parsedCost < 0) {
      return InventoryProductValuation._(
        status: InventoryProductValuationStatus.precisionAnomaly,
        quantityOnHand: quantityOnHand,
        averageCostCents: null,
        valueCents: null,
      );
    }

    final scaledCost = parsedCost * 100;
    if (!scaledCost.isFinite || scaledCost > 99999999999999.5) {
      return InventoryProductValuation._(
        status: InventoryProductValuationStatus.precisionAnomaly,
        quantityOnHand: quantityOnHand,
        averageCostCents: null,
        valueCents: null,
      );
    }

    final averageCostCents = BigInt.from(scaledCost.round());
    if (averageCostCents < BigInt.zero ||
        averageCostCents > _maximumAverageCostCents) {
      return InventoryProductValuation._(
        status: InventoryProductValuationStatus.precisionAnomaly,
        quantityOnHand: quantityOnHand,
        averageCostCents: null,
        valueCents: null,
      );
    }

    return InventoryProductValuation._(
      status: InventoryProductValuationStatus.known,
      quantityOnHand: quantityOnHand,
      averageCostCents: averageCostCents,
      valueCents: BigInt.from(quantityOnHand) * averageCostCents,
    );
  }
}

class InventoryValuationSummary {
  const InventoryValuationSummary({
    required this.knownValueCents,
    required this.unknownCostProductCount,
    required this.unknownCostUnitCount,
    required this.invalidStockProductCount,
    required this.precisionAnomalyProductCount,
  });

  factory InventoryValuationSummary.fromRows(
    Iterable<Map<String, dynamic>> rows,
  ) {
    var knownValueCents = BigInt.zero;
    var unknownCostProductCount = 0;
    var unknownCostUnitCount = BigInt.zero;
    var invalidStockProductCount = 0;
    var precisionAnomalyProductCount = 0;

    for (final row in rows) {
      final quantityOnHand = _intValue(row['quantity_on_hand']);
      if (quantityOnHand == null) {
        invalidStockProductCount += 1;
        continue;
      }
      final valuation = InventoryProductValuation.fromStock(
        quantityOnHand: quantityOnHand,
        averageCost: row['stock_average_cost'],
      );
      switch (valuation.status) {
        case InventoryProductValuationStatus.known:
          knownValueCents += valuation.valueCents!;
        case InventoryProductValuationStatus.unknownCost:
          unknownCostProductCount += 1;
          unknownCostUnitCount += BigInt.from(quantityOnHand);
        case InventoryProductValuationStatus.invalidStock:
          invalidStockProductCount += 1;
        case InventoryProductValuationStatus.precisionAnomaly:
          precisionAnomalyProductCount += 1;
      }
    }

    return InventoryValuationSummary(
      knownValueCents: knownValueCents,
      unknownCostProductCount: unknownCostProductCount,
      unknownCostUnitCount: unknownCostUnitCount,
      invalidStockProductCount: invalidStockProductCount,
      precisionAnomalyProductCount: precisionAnomalyProductCount,
    );
  }

  static final InventoryValuationSummary empty = InventoryValuationSummary(
    knownValueCents: BigInt.zero,
    unknownCostProductCount: 0,
    unknownCostUnitCount: BigInt.zero,
    invalidStockProductCount: 0,
    precisionAnomalyProductCount: 0,
  );

  final BigInt knownValueCents;
  final int unknownCostProductCount;
  final BigInt unknownCostUnitCount;
  final int invalidStockProductCount;
  final int precisionAnomalyProductCount;

  bool get isComplete =>
      unknownCostProductCount == 0 &&
      invalidStockProductCount == 0 &&
      precisionAnomalyProductCount == 0;
}

String formatInventoryMoneyCents(BigInt cents) {
  final negative = cents.isNegative;
  final absolute = cents.abs();
  final whole = absolute ~/ BigInt.from(100);
  final fraction = (absolute % BigInt.from(100)).toString().padLeft(2, '0');
  return '${negative ? '-' : ''}\$$whole.$fraction';
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}
