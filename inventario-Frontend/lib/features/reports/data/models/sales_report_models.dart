const salesSummaryReportType = 'sales_summary';
const salesReportCapability = 'reports.sales';

class SalesReportPeriod {
  SalesReportPeriod({required DateTime from, required DateTime to})
      : from = from.toUtc(),
        to = to.toUtc() {
    if (!this.to.isAfter(this.from)) {
      throw ArgumentError.value(to, 'to', 'Must be after from.');
    }
  }

  final DateTime from;
  final DateTime to;

  String get filterKey =>
      'from=${from.toIso8601String()}|to=${to.toIso8601String()}';
}

class SalesReportScope {
  SalesReportScope({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.period,
  }) {
    if (profileId.trim().isEmpty ||
        businessId.trim().isEmpty ||
        branchId.trim().isEmpty) {
      throw ArgumentError('Sales report scope identifiers are required.');
    }
  }

  final String profileId;
  final String businessId;
  final String branchId;
  final SalesReportPeriod period;
}

class SalesReportSummary {
  const SalesReportSummary({
    required this.businessId,
    required this.branchId,
    required this.periodFrom,
    required this.periodTo,
    required this.grossSalesCents,
    required this.saleCount,
    required this.averageTicketCents,
    required this.authoritativeAsOf,
  });

  final String businessId;
  final String branchId;
  final DateTime periodFrom;
  final DateTime periodTo;
  final BigInt grossSalesCents;
  final int saleCount;
  final BigInt? averageTicketCents;
  final DateTime authoritativeAsOf;

  Map<String, Object?> toJson() => {
        'business_id': businessId,
        'branch_id': branchId,
        'period_from': periodFrom.toUtc().toIso8601String(),
        'period_to': periodTo.toUtc().toIso8601String(),
        'gross_sales_cents': grossSalesCents.toString(),
        'sale_count': saleCount,
        'average_ticket_cents': averageTicketCents?.toString(),
        'authoritative_as_of': authoritativeAsOf.toUtc().toIso8601String(),
      };

  factory SalesReportSummary.fromCacheJson(Map<String, Object?> json) {
    final businessId = _requiredString(json, 'business_id');
    final branchId = _requiredString(json, 'branch_id');
    final periodFrom = parseReportDateTime(json['period_from'], 'period_from');
    final periodTo = parseReportDateTime(json['period_to'], 'period_to');
    if (!periodTo.isAfter(periodFrom)) {
      throw const FormatException('Cached sales report period is invalid.');
    }
    final grossSalesCents = parseReportInteger(
      json['gross_sales_cents'],
      'gross_sales_cents',
    );
    final saleCountValue = parseReportInteger(json['sale_count'], 'sale_count');
    final averageValue = json['average_ticket_cents'];
    final averageTicketCents = averageValue == null
        ? null
        : parseReportInteger(averageValue, 'average_ticket_cents');
    if (grossSalesCents.isNegative ||
        saleCountValue.isNegative ||
        (averageTicketCents?.isNegative ?? false) ||
        saleCountValue > BigInt.from(0x7fffffffffffffff)) {
      throw const FormatException('Cached sales report totals are invalid.');
    }
    final saleCount = saleCountValue.toInt();
    if ((saleCount == 0) != (averageTicketCents == null)) {
      throw const FormatException(
        'Cached average ticket does not match the sale count.',
      );
    }
    return SalesReportSummary(
      businessId: businessId,
      branchId: branchId,
      periodFrom: periodFrom,
      periodTo: periodTo,
      grossSalesCents: grossSalesCents,
      saleCount: saleCount,
      averageTicketCents: averageTicketCents,
      authoritativeAsOf: parseReportDateTime(
        json['authoritative_as_of'],
        'authoritative_as_of',
      ),
    );
  }
}

class SalesReportSnapshot {
  const SalesReportSnapshot({
    required this.summary,
    required this.fetchedAt,
    required this.authorizationValidatedAt,
    required this.capabilityFingerprint,
    required this.includesSensitiveData,
    required this.includesCosts,
  });

  final SalesReportSummary summary;
  final DateTime fetchedAt;
  final DateTime authorizationValidatedAt;
  final String capabilityFingerprint;
  final bool includesSensitiveData;
  final bool includesCosts;
}

DateTime parseReportDateTime(Object? value, String field) {
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toUtc();
    }
  }
  throw FormatException('Invalid $field in sales report response.');
}

BigInt parseReportInteger(Object? value, String field) {
  if (value is BigInt) return value;
  if (value is int) return BigInt.from(value);
  if (value is num && value.isFinite && value == value.truncateToDouble()) {
    return BigInt.parse(value.toString().split('.').first);
  }
  if (value is String && RegExp(r'^[+-]?\d+$').hasMatch(value.trim())) {
    return BigInt.parse(value.trim());
  }
  throw FormatException('Invalid $field in sales report response.');
}

BigInt parseReportMoneyCents(Object? value, String field) {
  if (value is num && !value.isFinite) {
    throw FormatException('Invalid $field in sales report response.');
  }
  final raw = value is BigInt ? value.toString() : value?.toString().trim();
  if (raw == null || raw.isEmpty) {
    throw FormatException('Invalid $field in sales report response.');
  }
  final match = RegExp(
    r'^([+-]?)(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$',
  ).firstMatch(raw);
  if (match == null) {
    throw FormatException('Invalid $field in sales report response.');
  }

  final negative = match.group(1) == '-';
  final whole = match.group(2)!;
  final fraction = match.group(3) ?? '';
  final exponent = int.tryParse(match.group(4) ?? '0');
  if (exponent == null || exponent.abs() > 1000) {
    throw FormatException('Invalid $field in sales report response.');
  }

  var unscaled = BigInt.parse('$whole$fraction');
  final decimalScale = fraction.length - exponent;
  if (decimalScale <= 2) {
    unscaled *= _powerOfTen(2 - decimalScale);
  } else {
    final divisor = _powerOfTen(decimalScale - 2);
    final quotient = unscaled ~/ divisor;
    final remainder = unscaled.remainder(divisor);
    unscaled =
        remainder * BigInt.two >= divisor ? quotient + BigInt.one : quotient;
  }
  return negative ? -unscaled : unscaled;
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is String && value.trim().isNotEmpty) {
    return value;
  }
  throw FormatException('Invalid $field in sales report response.');
}

BigInt _powerOfTen(int exponent) {
  var value = BigInt.one;
  for (var index = 0; index < exponent; index += 1) {
    value *= BigInt.from(10);
  }
  return value;
}
