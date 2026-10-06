class InventoryHistoryCursor {
  const InventoryHistoryCursor({
    required this.occurredAt,
    required this.id,
  });

  final DateTime occurredAt;
  final String id;

  @override
  bool operator ==(Object other) {
    return other is InventoryHistoryCursor &&
        other.occurredAt == occurredAt &&
        other.id == id;
  }

  @override
  int get hashCode => Object.hash(occurredAt, id);
}

/// Local movement dates may be Drift Unix seconds, legacy Unix milliseconds,
/// or ISO-8601 text from history hydration. Financial history is constrained
/// to 2000-01-01 through 2100-01-01 UTC; out-of-range values fail closed.
DateTime? parseInventoryHistoryTimestamp(Object? value) {
  const firstValidMs = 946684800000; // 2000-01-01T00:00:00Z
  const lastValidMs = 4102444800000; // 2100-01-01T00:00:00Z
  DateTime? parsed;
  if (value is int) {
    // Every valid Unix second is below 100 billion; every valid Unix
    // millisecond in the accepted period is above it.
    final millis = value < 100000000000 ? value * 1000 : value;
    if (millis < firstValidMs || millis >= lastValidMs) return null;
    parsed = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  } else if (value is String) {
    parsed = DateTime.tryParse(value)?.toUtc();
  } else if (value is DateTime) {
    parsed = value.toUtc();
  }
  if (parsed == null ||
      parsed.millisecondsSinceEpoch < firstValidMs ||
      parsed.millisecondsSinceEpoch >= lastValidMs) {
    return null;
  }
  return parsed;
}

class InventoryHistoryRemoteRow {
  const InventoryHistoryRemoteRow({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.productId,
    required this.movementType,
    required this.effectiveType,
    required this.quantityDelta,
    required this.occurredAt,
    required this.idempotencyKey,
    this.sourceType,
    this.sourceId,
    this.referenceType,
    this.referenceId,
    this.previousStock,
    this.newStock,
    this.createdBy,
    this.deviceId,
    this.reversedMovementId,
    this.unitCost,
  });

  factory InventoryHistoryRemoteRow.fromJson(Map<String, dynamic> json) {
    return InventoryHistoryRemoteRow(
      id: _requiredString(json, 'id'),
      businessId: _requiredString(json, 'business_id'),
      branchId: _requiredString(json, 'branch_id'),
      productId: _requiredString(json, 'product_id'),
      movementType: _requiredString(json, 'movement_type'),
      effectiveType: _requiredString(json, 'effective_type'),
      quantityDelta: _requiredInt(json, 'quantity_delta'),
      occurredAt: _requiredDateTime(json, 'occurred_at'),
      idempotencyKey: _requiredString(json, 'idempotency_key'),
      sourceType: _optionalString(json['source_type']),
      sourceId: _optionalString(json['source_id']),
      referenceType: _optionalString(json['reference_type']),
      referenceId: _optionalString(json['reference_id']),
      previousStock: _optionalInt(json, 'previous_stock'),
      newStock: _optionalInt(json, 'new_stock'),
      createdBy: _optionalString(json['created_by']),
      deviceId: _optionalString(json['device_id']),
      reversedMovementId: _optionalString(json['reversed_movement_id']),
      unitCost: _optionalDouble(json, 'unit_cost'),
    );
  }

  final String id;
  final String businessId;
  final String branchId;
  final String productId;
  final String movementType;
  final String? sourceType;
  final String effectiveType;
  final String? sourceId;
  final String? referenceType;
  final String? referenceId;
  final int quantityDelta;
  final DateTime occurredAt;
  final int? previousStock;
  final int? newStock;
  final String? createdBy;
  final String? deviceId;
  final String? reversedMovementId;
  final String idempotencyKey;
  final double? unitCost;
}

class InventoryHistoryRemotePage {
  const InventoryHistoryRemotePage({
    required this.rows,
    required this.hasMore,
    this.nextCursor,
  });

  factory InventoryHistoryRemotePage.fromRows(
    List<InventoryHistoryRemoteRow> rows, {
    required int requestedLimit,
  }) {
    final hasMore = rows.length == requestedLimit;
    final last = rows.isEmpty ? null : rows.last;
    return InventoryHistoryRemotePage(
      rows: List.unmodifiable(rows),
      hasMore: hasMore,
      nextCursor: last == null
          ? null
          : InventoryHistoryCursor(
              occurredAt: last.occurredAt,
              id: last.id,
            ),
    );
  }

  final List<InventoryHistoryRemoteRow> rows;
  final InventoryHistoryCursor? nextCursor;
  final bool hasMore;
}

class InventoryMovementHistoryEntry {
  const InventoryMovementHistoryEntry({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.productId,
    this.productName,
    this.productBarcode,
    this.isWeight = false,
    required this.movementType,
    required this.effectiveType,
    required this.quantityDelta,
    required this.occurredAt,
    this.sourceType,
    this.sourceId,
    this.referenceType,
    this.referenceId,
    this.previousStock,
    this.newStock,
    this.createdBy,
    this.deviceId,
    this.reversedMovementId,
    this.unitCost,
  });

  final String id;
  final String businessId;
  final String branchId;
  final String productId;
  final String? productName;
  final String? productBarcode;
  final bool isWeight;
  final String movementType;
  final String? sourceType;
  final String effectiveType;
  final String? sourceId;
  final String? referenceType;
  final String? referenceId;
  final int quantityDelta;
  final DateTime occurredAt;
  final int? previousStock;
  final int? newStock;
  final String? createdBy;
  final String? deviceId;
  final String? reversedMovementId;
  final double? unitCost;

  String get productFallbackLabel => productId;
}

class InventoryHistoryCoverage {
  const InventoryHistoryCoverage({
    required this.hasCachedRows,
    required this.hasMoreRemote,
    this.oldestCursor,
    this.lastRefreshedAt,
  });

  final bool hasCachedRows;
  final bool hasMoreRemote;
  final InventoryHistoryCursor? oldestCursor;
  final DateTime? lastRefreshedAt;
}

class InventoryHistoryLocalQuery {
  const InventoryHistoryLocalQuery({
    required this.businessId,
    required this.branchId,
    this.productId,
    this.effectiveType,
    this.from,
    this.to,
    this.cursor,
    this.limit = 50,
  });

  final String businessId;
  final String branchId;
  final String? productId;
  final String? effectiveType;
  final DateTime? from;
  final DateTime? to;
  final InventoryHistoryCursor? cursor;
  final int limit;
}

enum InventoryHistoryHydrationOutcome {
  hydrated,
  cachedOffline,
  noCachedHistory,
  connectionRequired,
  noMoreRemote,
}

class InventoryHistoryHydrationResult {
  const InventoryHistoryHydrationResult({
    required this.outcome,
    required this.coverage,
    this.rowsApplied = 0,
  });

  final InventoryHistoryHydrationOutcome outcome;
  final InventoryHistoryCoverage coverage;
  final int rowsApplied;
}

String effectiveInventoryMovementType({
  required String movementType,
  String? sourceType,
  String? referenceType,
}) {
  final normalizedReference = referenceType?.trim().toLowerCase();
  if (normalizedReference == 'manual_initial_stock' ||
      normalizedReference == 'initial_stock') {
    return 'initial_stock';
  }
  final normalizedSource = sourceType?.trim().toLowerCase();
  if (normalizedSource != null && normalizedSource.isNotEmpty) {
    return normalizedSource;
  }
  return movementType.trim().toLowerCase();
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) {
    throw FormatException('Inventory history row is missing $key.');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String) {
    throw const FormatException('Inventory history string is malformed.');
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num && value.isFinite && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw FormatException('Inventory history row has invalid $key.');
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  if (json[key] == null) return null;
  return _requiredInt(json, key);
}

double? _optionalDouble(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('Inventory history row has invalid $key.');
}

DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('Inventory history row has invalid $key.');
  }
  final parsed = parseInventoryHistoryTimestamp(value);
  if (parsed == null) {
    throw FormatException('Inventory history row has invalid $key.');
  }
  return parsed;
}
