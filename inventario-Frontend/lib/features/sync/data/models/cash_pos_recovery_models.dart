import 'operational_bootstrap_models.dart';

class CashPosRecoveryRequest {
  const CashPosRecoveryRequest({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.appDeviceId,
    required this.canonicalCashRegisterId,
    this.pageLimit = 1000,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String appDeviceId;
  final String canonicalCashRegisterId;
  final int pageLimit;
}

class CashPosRecoveryResult {
  const CashPosRecoveryResult({
    required this.snapshotId,
    required this.cashContextReady,
    required this.canonicalCashRegisterId,
    required this.openCashSessionId,
    required this.recoveredSalesCount,
    required this.blockingIssues,
    required this.completed,
  });

  final String snapshotId;
  final bool cashContextReady;
  final String canonicalCashRegisterId;
  final String? openCashSessionId;
  final int recoveredSalesCount;
  final int blockingIssues;
  final bool completed;
}

class CashRegisterSnapshotRow {
  CashRegisterSnapshotRow.fromRow(OperationalBootstrapRow row)
      : id = _requiredString(row.data, 'id'),
        businessId = _requiredString(row.data, 'business_id'),
        branchId = _requiredString(row.data, 'branch_id'),
        name = _requiredString(row.data, 'name'),
        status = _requiredString(row.data, 'status'),
        version = _optionalInt(row.data['version']) ?? 1,
        createdAt = _requiredDate(row.data, 'created_at'),
        updatedAt = _requiredDate(row.data, 'updated_at'),
        deletedAt = _optionalDate(row.data['deleted_at'], 'deleted_at'),
        state = _requiredState(row);

  final String id;
  final String businessId;
  final String branchId;
  final String name;
  final String status;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final OperationalBootstrapRecordState state;
}

class CashSessionSnapshotRow {
  CashSessionSnapshotRow.fromRow(OperationalBootstrapRow row)
      : id = _requiredString(row.data, 'id'),
        businessId = _requiredString(row.data, 'business_id'),
        branchId = _requiredString(row.data, 'branch_id'),
        cashRegisterId = _requiredString(row.data, 'cash_register_id'),
        openedByProfileId = _requiredStringAny(
          row.data,
          const ['opened_by_profile_id', 'opened_by'],
        ),
        closedByProfileId = _optionalStringAny(
          row.data,
          const ['closed_by_profile_id', 'closed_by'],
        ),
        openedAt = _requiredDate(row.data, 'opened_at'),
        closedAt = _optionalDate(row.data['closed_at'], 'closed_at'),
        openingCashAmount = _requiredDoubleAny(
          row.data,
          const ['opening_cash_amount', 'opening_amount'],
        ),
        expectedCashAmount = _optionalDoubleAny(
          row.data,
          const ['expected_cash_amount', 'expected_closing_amount'],
        ),
        closingCashAmount = _optionalDoubleAny(
          row.data,
          const ['closing_cash_amount', 'actual_closing_amount'],
        ),
        differenceAmount = _optionalDouble(row.data['difference_amount']),
        status = _requiredString(row.data, 'status'),
        version = _optionalInt(row.data['version']) ?? 1,
        createdAt = _requiredDate(row.data, 'created_at'),
        updatedAt = _requiredDate(row.data, 'updated_at'),
        deletedAt = _optionalDate(row.data['deleted_at'], 'deleted_at'),
        state = _requiredState(row);

  final String id;
  final String businessId;
  final String branchId;
  final String cashRegisterId;
  final String openedByProfileId;
  final String? closedByProfileId;
  final DateTime openedAt;
  final DateTime? closedAt;
  final double openingCashAmount;
  final double? expectedCashAmount;
  final double? closingCashAmount;
  final double? differenceAmount;
  final String status;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final OperationalBootstrapRecordState state;
}

class CashPosSaleSnapshotRow {
  CashPosSaleSnapshotRow.fromRow(OperationalBootstrapRow row)
      : id = _requiredString(row.data, 'id'),
        businessId = _requiredString(row.data, 'business_id'),
        branchId = _requiredString(row.data, 'branch_id'),
        cashSessionId = _requiredString(row.data, 'cash_session_id'),
        userId = _optionalString(row.data['user_id']),
        customerId = _optionalString(row.data['customer_id']),
        subtotal = _requiredDouble(row.data, 'subtotal'),
        discountTotal = _requiredDouble(row.data, 'discount_total'),
        taxTotal = _requiredDouble(row.data, 'tax_total'),
        total = _requiredDouble(row.data, 'total'),
        paymentMethod = _optionalString(row.data['payment_method']),
        paymentStatus = _optionalString(row.data['payment_status']) ?? 'paid',
        idempotencyKey = _optionalString(row.data['idempotency_key']),
        status = _optionalString(row.data['status']) ?? 'completed',
        metadata = _optionalMap(row.data['metadata']),
        createdAt = _requiredDate(row.data, 'created_at'),
        updatedAt = _requiredDate(row.data, 'updated_at'),
        deletedAt = _optionalDate(row.data['deleted_at'], 'deleted_at'),
        state = _requiredState(row);

  final String id;
  final String businessId;
  final String branchId;
  final String cashSessionId;
  final String? userId;
  final String? customerId;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double total;
  final String? paymentMethod;
  final String paymentStatus;
  final String? idempotencyKey;
  final String status;
  final Map<String, Object?>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final OperationalBootstrapRecordState state;
}

class CashPosSaleItemSnapshotRow {
  CashPosSaleItemSnapshotRow.fromRow(OperationalBootstrapRow row)
      : id = _requiredString(row.data, 'id'),
        saleId = _requiredString(row.data, 'sale_id'),
        productId = _optionalString(row.data['product_id']),
        productNameSnapshot =
            _optionalString(row.data['product_name_snapshot']),
        barcodeSnapshot = _optionalString(row.data['barcode_snapshot']),
        quantity = _requiredInt(row.data, 'quantity'),
        unitPrice = _requiredDouble(row.data, 'unit_price'),
        discountTotal = _optionalDoubleAny(
              row.data,
              const ['discount_total', 'discount_amount'],
            ) ??
            0,
        taxTotal = _optionalDoubleAny(
              row.data,
              const ['tax_total', 'tax_amount'],
            ) ??
            0,
        subtotal = _requiredDouble(row.data, 'subtotal'),
        lineTotal = _optionalDoubleAny(
              row.data,
              const ['line_total', 'total'],
            ) ??
            _requiredDouble(row.data, 'subtotal'),
        metadata = _optionalMap(row.data['metadata']),
        createdAt = _requiredDate(row.data, 'created_at'),
        updatedAt = _requiredDate(row.data, 'updated_at'),
        deletedAt = _optionalDate(row.data['deleted_at'], 'deleted_at'),
        state = _requiredState(row);

  final String id;
  final String saleId;
  final String? productId;
  final String? productNameSnapshot;
  final String? barcodeSnapshot;
  final int quantity;
  final double unitPrice;
  final double discountTotal;
  final double taxTotal;
  final double subtotal;
  final double lineTotal;
  final Map<String, Object?>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final OperationalBootstrapRecordState state;
}

class CashPosSalePaymentSnapshotRow {
  CashPosSalePaymentSnapshotRow.fromRow(OperationalBootstrapRow row)
      : id = _requiredString(row.data, 'id'),
        businessId = _requiredString(row.data, 'business_id'),
        saleId = _requiredString(row.data, 'sale_id'),
        paymentMethod = _requiredPaymentMethod(row.data),
        amount = _requiredPositiveDouble(row.data, 'amount'),
        currency = _requiredString(row.data, 'currency'),
        status = _requiredString(row.data, 'status'),
        reference = _optionalString(row.data['reference']),
        metadata = _optionalMap(row.data['metadata']),
        createdAt = _requiredDate(row.data, 'created_at'),
        updatedAt = _requiredDate(row.data, 'updated_at'),
        deletedAt = _optionalDate(row.data['deleted_at'], 'deleted_at'),
        state = _requiredState(row);

  final String id;
  final String businessId;
  final String saleId;
  final String paymentMethod;
  final double amount;
  final String currency;
  final String status;
  final String? reference;
  final Map<String, Object?>? metadata;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final OperationalBootstrapRecordState state;
}

OperationalBootstrapRecordState _requiredState(OperationalBootstrapRow row) {
  if (row.state == OperationalBootstrapRecordState.unspecified) {
    throw _malformed('Cash/POS rows require an explicit record state.');
  }
  return row.state;
}

OperationalBootstrapException _malformed(String message) =>
    OperationalBootstrapException(
      kind: OperationalBootstrapFailureKind.malformedResponse,
      message: message,
    );

String _requiredString(Map<String, Object?> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) throw _malformed('$key must be a non-empty string.');
  return value;
}

String _requiredStringAny(Map<String, Object?> json, List<String> keys) {
  final value = _optionalStringAny(json, keys);
  if (value == null) throw _malformed('${keys.join('/')} is required.');
  return value;
}

String? _optionalStringAny(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = _optionalString(json[key]);
    if (value != null) return value;
  }
  return null;
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = _optionalInt(json[key]);
  if (value == null) throw _malformed('$key must be an integer.');
  return value;
}

int? _optionalInt(Object? value) {
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  return null;
}

double _requiredDouble(Map<String, Object?> json, String key) {
  final value = _optionalDouble(json[key]);
  if (value == null) throw _malformed('$key must be numeric.');
  return value;
}

double _requiredPositiveDouble(Map<String, Object?> json, String key) {
  final value = _requiredDouble(json, key);
  if (value <= 0) throw _malformed('$key must be greater than zero.');
  return value;
}

String _requiredPaymentMethod(Map<String, Object?> json) {
  final value = _requiredString(json, 'payment_method');
  if (!const {
    'cash',
    'card',
    'bank_transfer',
    'nequi',
    'daviplata',
    'credit',
    'other',
  }.contains(value)) {
    throw _malformed('Unsupported payment_method: $value.');
  }
  return value;
}

double _requiredDoubleAny(Map<String, Object?> json, List<String> keys) {
  final value = _optionalDoubleAny(json, keys);
  if (value == null) throw _malformed('${keys.join('/')} must be numeric.');
  return value;
}

double? _optionalDoubleAny(Map<String, Object?> json, List<String> keys) {
  for (final key in keys) {
    final value = _optionalDouble(json[key]);
    if (value != null) return value;
  }
  return null;
}

double? _optionalDouble(Object? value) =>
    value is num ? value.toDouble() : null;

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = _optionalDate(json[key], key);
  if (value == null) throw _malformed('$key must be an ISO-8601 timestamp.');
  return value;
}

DateTime? _optionalDate(Object? value, String key) {
  if (value == null) return null;
  if (value is! String) throw _malformed('$key must be an ISO-8601 string.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw _malformed('$key is not a valid timestamp.');
  return parsed.toUtc();
}

Map<String, Object?>? _optionalMap(Object? value) {
  if (value == null) return null;
  if (value is! Map) throw _malformed('metadata must be an object or null.');
  return value.map((key, item) => MapEntry(key.toString(), item));
}
