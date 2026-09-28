import '../../../cash/application/cash_movement_models.dart';
import 'sales_report_models.dart';

const cashFlowReportType = 'cash_flow_summary';
const cashFlowReportCapability = 'reports.cash';

class CashFlowCategoryTotal {
  const CashFlowCategoryTotal({required this.count, required this.totalCents});
  final int count;
  final BigInt totalCents;
}

class CashFlowReportSummary {
  const CashFlowReportSummary({
    required this.businessId,
    required this.branchId,
    required this.periodFrom,
    required this.periodTo,
    required this.cashSalesCents,
    required this.additionalInflowsCents,
    required this.totalInflowsCents,
    required this.totalOutflowsCents,
    required this.netCashFlowCents,
    required this.inventoryAcquisitionCents,
    required this.operatingExpensesCents,
    required this.ownerWithdrawalsCents,
    required this.otherOutflowsCents,
    required this.outflowByCategory,
    required this.authoritativeAsOf,
  });

  final String businessId;
  final String branchId;
  final DateTime periodFrom;
  final DateTime periodTo;
  final BigInt cashSalesCents;
  final BigInt additionalInflowsCents;
  final BigInt totalInflowsCents;
  final BigInt totalOutflowsCents;
  final BigInt netCashFlowCents;
  final BigInt inventoryAcquisitionCents;
  final BigInt operatingExpensesCents;
  final BigInt ownerWithdrawalsCents;
  final BigInt otherOutflowsCents;
  final Map<String, CashFlowCategoryTotal> outflowByCategory;
  final DateTime authoritativeAsOf;

  Map<String, Object?> toJson() => {
        'business_id': businessId,
        'branch_id': branchId,
        'period_from': periodFrom.toUtc().toIso8601String(),
        'period_to': periodTo.toUtc().toIso8601String(),
        'cash_sales_cents': cashSalesCents.toString(),
        'additional_cash_inflows_cents': additionalInflowsCents.toString(),
        'total_cash_inflows_cents': totalInflowsCents.toString(),
        'total_cash_outflows_cents': totalOutflowsCents.toString(),
        'net_cash_flow_cents': netCashFlowCents.toString(),
        'inventory_acquisition_outflows_cents':
            inventoryAcquisitionCents.toString(),
        'operating_expenses_cents': operatingExpensesCents.toString(),
        'owner_withdrawals_cents': ownerWithdrawalsCents.toString(),
        'other_outflows_cents': otherOutflowsCents.toString(),
        'outflow_by_category': outflowByCategory.map(
          (key, value) => MapEntry(key, {
            'count': value.count,
            'total_cents': value.totalCents.toString(),
          }),
        ),
        'authoritative_as_of': authoritativeAsOf.toUtc().toIso8601String(),
      };

  factory CashFlowReportSummary.fromJson(Map<String, Object?> json) {
    String string(String field) {
      final value = json[field];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid cash report $field');
      }
      return value;
    }

    BigInt cents(String field, {bool allowNegative = false}) {
      // RPC and cache encode integer cents as decimal text to avoid JSON
      // floating-point precision loss on large aggregates.
      final value = json[field];
      if (value is! String || !RegExp(r'^-?\d+$').hasMatch(value)) {
        throw FormatException('Invalid cash report $field');
      }
      final parsed = BigInt.parse(value);
      if (!allowNegative && parsed.isNegative) {
        throw FormatException('Invalid cash report $field');
      }
      return parsed;
    }

    final from = parseReportDateTime(json['period_from'], 'period_from');
    final to = parseReportDateTime(json['period_to'], 'period_to');
    if (!to.isAfter(from)) {
      throw const FormatException('Invalid cash report period');
    }
    final rawBreakdown = json['outflow_by_category'];
    if (rawBreakdown is! Map) {
      throw const FormatException('Invalid cash report breakdown');
    }
    final breakdown = <String, CashFlowCategoryTotal>{};
    for (final entry in rawBreakdown.entries) {
      final code = entry.key;
      final item = entry.value;
      if (code is! String ||
          item is! Map ||
          CashMovementCategoryMetadata.byCode[code]?.supports(
                CashMovementDirection.outflow,
              ) !=
              true) {
        throw const FormatException('Invalid cash report category');
      }
      final count = parseReportInteger(item['count'], 'count');
      final rawTotal = item['total_cents'];
      if (count <= BigInt.zero ||
          count > BigInt.from(0x7fffffffffffffff) ||
          rawTotal is! String ||
          !RegExp(r'^\d+$').hasMatch(rawTotal)) {
        throw const FormatException('Invalid cash report category total');
      }
      breakdown[code] = CashFlowCategoryTotal(
          count: count.toInt(), totalCents: BigInt.parse(rawTotal));
    }
    final sales = cents('cash_sales_cents');
    final additional = cents('additional_cash_inflows_cents');
    final inflows = cents('total_cash_inflows_cents');
    final outflows = cents('total_cash_outflows_cents');
    final net = cents('net_cash_flow_cents', allowNegative: true);
    final acquisition = cents('inventory_acquisition_outflows_cents');
    final operating = cents('operating_expenses_cents');
    final owner = cents('owner_withdrawals_cents');
    final other = cents('other_outflows_cents');
    BigInt totalFor(bool Function(CashMovementCategoryMetadata) predicate) =>
        breakdown.entries.fold(
            BigInt.zero,
            (total, entry) =>
                predicate(CashMovementCategoryMetadata.byCode[entry.key]!)
                    ? total + entry.value.totalCents
                    : total);
    if (inflows != sales + additional ||
        net != inflows - outflows ||
        outflows !=
            breakdown.values
                .fold(BigInt.zero, (total, item) => total + item.totalCents) ||
        acquisition !=
            totalFor((category) => category.countsAsInventoryAcquisition) ||
        operating !=
            totalFor((category) => category.countsAsOperatingExpense) ||
        owner != totalFor((category) => category.countsAsOwnerMovement) ||
        other !=
            totalFor((category) => category
                .countsAsOtherCashOutflow(CashMovementDirection.outflow)) ||
        outflows != acquisition + operating + owner + other) {
      throw const FormatException('Inconsistent cash report totals');
    }
    return CashFlowReportSummary(
      businessId: string('business_id'),
      branchId: string('branch_id'),
      periodFrom: from,
      periodTo: to,
      cashSalesCents: sales,
      additionalInflowsCents: additional,
      totalInflowsCents: inflows,
      totalOutflowsCents: outflows,
      netCashFlowCents: net,
      inventoryAcquisitionCents: acquisition,
      operatingExpensesCents: operating,
      ownerWithdrawalsCents: owner,
      otherOutflowsCents: other,
      outflowByCategory: Map.unmodifiable(breakdown),
      authoritativeAsOf: parseReportDateTime(
          json['authoritative_as_of'], 'authoritative_as_of'),
    );
  }
}

class CashFlowReportSnapshot {
  const CashFlowReportSnapshot({
    required this.summary,
    required this.fetchedAt,
    required this.authorizationValidatedAt,
    required this.hasPendingLocalSync,
    this.hasPendingLocalCashSales = false,
  });
  final CashFlowReportSummary summary;
  final DateTime fetchedAt;
  final DateTime authorizationValidatedAt;
  final bool hasPendingLocalSync;
  final bool hasPendingLocalCashSales;
}
