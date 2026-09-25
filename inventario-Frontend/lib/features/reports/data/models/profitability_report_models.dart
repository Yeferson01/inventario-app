import 'sales_report_models.dart';

const profitabilityReportType = 'sales_profitability';
const profitabilityCostCapability = 'sales.view_costs';

/// An exact ratio. Consumers may format it later without storing a double.
class ExactProfitabilityMargin {
  const ExactProfitabilityMargin(this.numerator, this.denominator);

  final BigInt numerator;
  final BigInt denominator;
}

class ProfitabilityReportSummary {
  ProfitabilityReportSummary({
    required this.businessId,
    required this.branchId,
    required DateTime periodFrom,
    required DateTime periodTo,
    required this.knownNetSalesCents,
    required this.knownCogsCents,
    required this.knownGrossProfitCents,
    required this.unknownCostItemCount,
    required this.unknownCostNetSalesCents,
    required this.costCoverageComplete,
    required DateTime authoritativeAsOf,
  })  : periodFrom = periodFrom.toUtc(),
        periodTo = periodTo.toUtc(),
        authoritativeAsOf = authoritativeAsOf.toUtc() {
    if (businessId.trim().isEmpty ||
        branchId.trim().isEmpty ||
        !this.periodTo.isAfter(this.periodFrom) ||
        knownCogsCents.isNegative ||
        unknownCostItemCount < 0 ||
        knownGrossProfitCents != knownNetSalesCents - knownCogsCents ||
        costCoverageComplete != (unknownCostItemCount == 0)) {
      throw const FormatException('Profitability report totals are invalid.');
    }
  }

  final String businessId;
  final String branchId;
  final DateTime periodFrom;
  final DateTime periodTo;
  final BigInt knownNetSalesCents;
  final BigInt knownCogsCents;
  final BigInt knownGrossProfitCents;
  final int unknownCostItemCount;
  final BigInt unknownCostNetSalesCents;
  final bool costCoverageComplete;
  final DateTime authoritativeAsOf;

  ExactProfitabilityMargin? get knownGrossMargin =>
      knownNetSalesCents == BigInt.zero
          ? null
          : ExactProfitabilityMargin(
              knownGrossProfitCents,
              knownNetSalesCents,
            );

  Map<String, Object?> toCacheJson() => {
        'business_id': businessId,
        'branch_id': branchId,
        'period_from': periodFrom.toIso8601String(),
        'period_to': periodTo.toIso8601String(),
        'known_net_sales_cents': knownNetSalesCents.toString(),
        'known_cogs_cents': knownCogsCents.toString(),
        'known_gross_profit_cents': knownGrossProfitCents.toString(),
        'known_gross_margin': knownGrossMargin == null
            ? null
            : {
                'numerator': knownGrossProfitCents.toString(),
                'denominator': knownNetSalesCents.toString(),
              },
        'unknown_cost_item_count': unknownCostItemCount,
        'unknown_cost_net_sales_cents': unknownCostNetSalesCents.toString(),
        'cost_coverage_complete': costCoverageComplete,
        'authoritative_as_of': authoritativeAsOf.toIso8601String(),
      };

  factory ProfitabilityReportSummary.fromCacheJson(Map<String, Object?> json) {
    final count = parseReportInteger(
      json['unknown_cost_item_count'],
      'unknown_cost_item_count',
    );
    if (count.isNegative || count > BigInt.from(0x7fffffffffffffff)) {
      throw const FormatException('Invalid unknown cost item count.');
    }
    final coverage = json['cost_coverage_complete'];
    if (coverage is! bool) {
      throw const FormatException('Invalid cached cost coverage.');
    }
    final summary = ProfitabilityReportSummary(
      businessId: _requiredString(json, 'business_id'),
      branchId: _requiredString(json, 'branch_id'),
      periodFrom: parseReportDateTime(json['period_from'], 'period_from'),
      periodTo: parseReportDateTime(json['period_to'], 'period_to'),
      knownNetSalesCents: parseReportInteger(
          json['known_net_sales_cents'], 'known_net_sales_cents'),
      knownCogsCents:
          parseReportInteger(json['known_cogs_cents'], 'known_cogs_cents'),
      knownGrossProfitCents: parseReportInteger(
          json['known_gross_profit_cents'], 'known_gross_profit_cents'),
      unknownCostItemCount: count.toInt(),
      unknownCostNetSalesCents: parseReportInteger(
          json['unknown_cost_net_sales_cents'], 'unknown_cost_net_sales_cents'),
      costCoverageComplete: coverage,
      authoritativeAsOf: parseReportDateTime(
          json['authoritative_as_of'], 'authoritative_as_of'),
    );
    final margin = json['known_gross_margin'];
    if (summary.knownGrossMargin == null) {
      if (margin != null) {
        throw const FormatException('Cached margin has no denominator.');
      }
    } else if (margin is! Map ||
        parseReportInteger(margin['numerator'], 'margin numerator') !=
            summary.knownGrossProfitCents ||
        parseReportInteger(margin['denominator'], 'margin denominator') !=
            summary.knownNetSalesCents) {
      throw const FormatException('Cached margin does not match totals.');
    }
    return summary;
  }
}

class ProfitabilityReportSnapshot {
  const ProfitabilityReportSnapshot({
    required this.summary,
    required this.fetchedAt,
    required this.authorizationValidatedAt,
    required this.capabilityFingerprint,
    required this.includesSensitiveData,
    required this.includesCosts,
  });

  final ProfitabilityReportSummary summary;
  final DateTime fetchedAt;
  final DateTime authorizationValidatedAt;
  final String capabilityFingerprint;
  final bool includesSensitiveData;
  final bool includesCosts;
}

/// B1 sums integer quantities and two-decimal item values, so money must have
/// an exact cent representation. Fractional sub-cents are rejected, not rounded.
BigInt parseExactReportMoneyCents(Object? value, String field) {
  if (value is double && (!value.isFinite || value.abs() > 90071992547409.91)) {
    throw FormatException('Invalid $field in profitability response.');
  }
  final raw = value is BigInt ? value.toString() : value?.toString().trim();
  final match = raw == null
      ? null
      : RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$')
          .firstMatch(raw);
  if (match == null) {
    throw FormatException('Invalid $field in profitability response.');
  }
  final exponent = int.tryParse(match.group(4) ?? '0');
  if (exponent == null || exponent.abs() > 1000) {
    throw FormatException('Invalid $field in profitability response.');
  }
  var unscaled = BigInt.parse('${match.group(2)}${match.group(3) ?? ''}');
  final scale = (match.group(3) ?? '').length - exponent;
  if (scale <= 2) {
    unscaled *= BigInt.from(10).pow(2 - scale);
  } else {
    final divisor = BigInt.from(10).pow(scale - 2);
    if (unscaled.remainder(divisor) != BigInt.zero) {
      throw FormatException('Sub-cent $field in profitability response.');
    }
    unscaled ~/= divisor;
  }
  return match.group(1) == '-' ? -unscaled : unscaled;
}

void validateRemoteProfitabilityMargin(Object? value, BigInt revenueCents) {
  if (revenueCents == BigInt.zero) {
    if (value != null) {
      throw const FormatException('Margin must be null for zero revenue.');
    }
    return;
  }
  if (value is double && !value.isFinite) {
    throw const FormatException('Invalid profitability margin.');
  }
  if (value is! String && value is! num && value is! BigInt) {
    throw const FormatException('Invalid profitability margin.');
  }
  if (!RegExp(r'^[+-]?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$')
      .hasMatch(value.toString().trim())) {
    throw const FormatException('Invalid profitability margin.');
  }
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is String && value.trim().isNotEmpty) return value;
  throw FormatException('Invalid $field in cached profitability report.');
}
