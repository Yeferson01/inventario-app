import 'operational_bootstrap_models.dart';

class InventoryBalanceSnapshotRow {
  const InventoryBalanceSnapshotRow({
    required this.remoteBalanceId,
    required this.businessId,
    required this.branchId,
    required this.productId,
    required this.quantityOnHand,
    required this.quantityReserved,
    required this.quantityAvailable,
    required this.averageCost,
    required this.remoteUpdatedAt,
    required this.remoteDeletedAt,
    required this.state,
  });

  factory InventoryBalanceSnapshotRow.fromBootstrapRow(
    OperationalBootstrapRow row,
  ) {
    if (row.state == OperationalBootstrapRecordState.unspecified) {
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.malformedResponse,
        message: 'Balance snapshot rows require an explicit record state.',
      );
    }
    final json = row.data;
    return InventoryBalanceSnapshotRow(
      remoteBalanceId: _requiredString(json, 'id'),
      businessId: _requiredString(json, 'business_id'),
      branchId: _requiredString(json, 'branch_id'),
      productId: _requiredString(json, 'product_id'),
      quantityOnHand: _requiredInt(json, 'quantity_on_hand'),
      quantityReserved: _requiredInt(json, 'quantity_reserved'),
      quantityAvailable: _requiredInt(json, 'quantity_available'),
      averageCost: _optionalDouble(json['average_cost']),
      remoteUpdatedAt: _requiredDate(json, 'updated_at'),
      remoteDeletedAt: _optionalDate(json['deleted_at'], 'deleted_at'),
      state: row.state,
    );
  }

  final String remoteBalanceId;
  final String businessId;
  final String branchId;
  final String productId;
  final int quantityOnHand;
  final int quantityReserved;
  final int quantityAvailable;
  final double? averageCost;
  final DateTime remoteUpdatedAt;
  final DateTime? remoteDeletedAt;
  final OperationalBootstrapRecordState state;

  bool get isTombstone => state == OperationalBootstrapRecordState.tombstone;

  String get semanticIdentity => '$businessId:$branchId:$productId';
}

class InventoryBalanceReconciliationRequest {
  const InventoryBalanceReconciliationRequest({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.appDeviceId,
    this.pageLimit = 1000,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String appDeviceId;
  final int pageLimit;
}

class InventoryBalanceReconciliationResult {
  const InventoryBalanceReconciliationResult({
    required this.snapshotId,
    required this.attempts,
    required this.movementsChecked,
    required this.balancesReconciled,
    required this.blockingIssues,
    required this.converged,
  });

  final String? snapshotId;
  final int attempts;
  final int movementsChecked;
  final int balancesReconciled;
  final int blockingIssues;
  final bool converged;
}

OperationalBootstrapException _malformed(String message) {
  return OperationalBootstrapException(
    kind: OperationalBootstrapFailureKind.malformedResponse,
    message: message,
  );
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw _malformed('$key must be a non-empty string.');
  }
  return value.trim();
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) {
    return value;
  }
  if (value is num && value == value.roundToDouble()) {
    return value.toInt();
  }
  throw _malformed('$key must be an integer.');
}

double? _optionalDouble(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  throw _malformed('Expected a numeric value or null.');
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = _optionalDate(json[key], key);
  if (value == null) {
    throw _malformed('$key must be an ISO-8601 timestamp.');
  }
  return value;
}

DateTime? _optionalDate(Object? value, String key) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw _malformed('$key must be an ISO-8601 string or null.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw _malformed('$key is not a valid ISO-8601 timestamp.');
  }
  return parsed.toUtc();
}
