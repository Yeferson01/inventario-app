class CashRemoteStateUnavailableException implements Exception {
  const CashRemoteStateUnavailableException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'CashRemoteStateUnavailableException: $message';
}

class AuthoritativeCashSessionSnapshot {
  const AuthoritativeCashSessionSnapshot({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.cashRegisterId,
    required this.openedByProfileId,
    required this.closedByProfileId,
    required this.openedAt,
    required this.closedAt,
    required this.openingCashAmount,
    required this.expectedCashAmount,
    required this.closingCashAmount,
    required this.differenceAmount,
    required this.status,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.reusedOpenSession,
    required this.idempotent,
    this.notes,
  });

  factory AuthoritativeCashSessionSnapshot.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Cash session RPC must return an object.');
    }
    final json = value.map((key, item) => MapEntry(key.toString(), item));
    return AuthoritativeCashSessionSnapshot(
      id: _requiredString(json, 'cash_session_id'),
      businessId: _requiredString(json, 'business_id'),
      branchId: _requiredString(json, 'branch_id'),
      cashRegisterId: _requiredString(json, 'cash_register_id'),
      openedByProfileId: _nullableString(json['opened_by_profile_id']),
      closedByProfileId: _nullableString(json['closed_by_profile_id']),
      openedAt: _requiredDate(json, 'opened_at'),
      closedAt: _nullableDate(json['closed_at']),
      openingCashAmount: _requiredDouble(json, 'opening_cash_amount'),
      expectedCashAmount: _nullableDouble(json['expected_cash_amount']),
      closingCashAmount: _nullableDouble(json['closing_cash_amount']),
      differenceAmount: _nullableDouble(json['difference_amount']),
      status: _requiredString(json, 'status'),
      version: _requiredInt(json, 'version'),
      createdAt: _requiredDate(json, 'created_at'),
      updatedAt: _requiredDate(json, 'updated_at'),
      reusedOpenSession: json['reused_open_session'] == true,
      idempotent: json['idempotent'] == true,
      notes: _nullableString(json['notes']),
    );
  }

  final String id;
  final String businessId;
  final String branchId;
  final String cashRegisterId;
  final String? openedByProfileId;
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
  final bool reusedOpenSession;
  final bool idempotent;
  final String? notes;
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = _nullableString(json[key]);
  if (value == null) throw FormatException('$key is required.');
  return value;
}

String? _nullableString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = _nullableDate(json[key]);
  if (value == null) throw FormatException('$key is required.');
  return value;
}

DateTime? _nullableDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value.toUtc();
  return DateTime.tryParse(value.toString())?.toUtc();
}

double _requiredDouble(Map<String, Object?> json, String key) {
  final value = _nullableDouble(json[key]);
  if (value == null) throw FormatException('$key is required.');
  return value;
}

double? _nullableDouble(Object? value) {
  if (value is num) return value.toDouble();
  return value == null ? null : double.tryParse(value.toString());
}

int _requiredInt(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  final parsed = int.tryParse(value?.toString() ?? '');
  if (parsed == null) throw FormatException('$key is required.');
  return parsed;
}
