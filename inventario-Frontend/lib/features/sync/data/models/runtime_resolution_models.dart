import 'operational_integration_failure.dart';

class ResolvedOpenCashSession {
  const ResolvedOpenCashSession({
    required this.cashSessionId,
    required this.cashRegisterId,
    required this.status,
    required this.openedBy,
    required this.openedAt,
  });

  factory ResolvedOpenCashSession.fromJson(Object? value) {
    final json = _map(value, 'open_cash_session');
    return ResolvedOpenCashSession(
      cashSessionId: _requiredString(json, 'cash_session_id'),
      cashRegisterId: _requiredString(json, 'cash_register_id'),
      status: _requiredString(json, 'status'),
      openedBy: _requiredString(json, 'opened_by'),
      openedAt: _requiredDate(json, 'opened_at'),
    );
  }

  final String cashSessionId;
  final String cashRegisterId;
  final String status;
  final String openedBy;
  final DateTime openedAt;

  Map<String, Object?> toJson() => {
        'cash_session_id': cashSessionId,
        'cash_register_id': cashRegisterId,
        'status': status,
        'opened_by': openedBy,
        'opened_at': openedAt.toIso8601String(),
      };
}

class ResolvedBusinessRuntime {
  const ResolvedBusinessRuntime({
    required this.profileId,
    required this.businessId,
    required this.businessName,
    required this.branchId,
    required this.branchName,
    required this.cashRegisterId,
    required this.cashRegisterName,
    required this.receiptSequenceId,
    required this.receiptSequenceName,
    required this.receiptPrefix,
    required this.openCashSession,
    required this.runtimeReady,
    required this.resolvedAt,
  });

  factory ResolvedBusinessRuntime.fromRpc(Object? value) {
    final json = _map(value, 'resolved business runtime');
    final runtime = ResolvedBusinessRuntime(
      profileId: _requiredString(json, 'profile_id'),
      businessId: _requiredString(json, 'business_id'),
      businessName: _requiredString(json, 'business_name'),
      branchId: _requiredString(json, 'branch_id'),
      branchName: _requiredString(json, 'branch_name'),
      cashRegisterId: _optionalString(json['cash_register_id']),
      cashRegisterName: _optionalString(json['cash_register_name']),
      receiptSequenceId: _optionalString(json['receipt_sequence_id']),
      receiptSequenceName: _optionalString(json['receipt_sequence_name']),
      receiptPrefix: _optionalString(json['receipt_prefix']),
      openCashSession: json['open_cash_session'] == null
          ? null
          : ResolvedOpenCashSession.fromJson(json['open_cash_session']),
      runtimeReady: _requiredBool(json, 'runtime_ready'),
      resolvedAt: _requiredDate(json, 'resolved_at'),
    );
    if (runtime.runtimeReady &&
        (runtime.cashRegisterId == null || runtime.receiptSequenceId == null)) {
      throw _malformed(
        'runtime_ready requires cash_register_id and receipt_sequence_id.',
      );
    }
    if (runtime.openCashSession != null &&
        runtime.openCashSession!.cashRegisterId != runtime.cashRegisterId) {
      throw _malformed(
          'Open cash session does not use the canonical register.');
    }
    return runtime;
  }

  final String profileId;
  final String businessId;
  final String businessName;
  final String branchId;
  final String branchName;
  final String? cashRegisterId;
  final String? cashRegisterName;
  final String? receiptSequenceId;
  final String? receiptSequenceName;
  final String? receiptPrefix;
  final ResolvedOpenCashSession? openCashSession;
  final bool runtimeReady;
  final DateTime resolvedAt;

  String? get openCashSessionId => openCashSession?.cashSessionId;

  Map<String, Object?> toJson() => {
        'profile_id': profileId,
        'business_id': businessId,
        'business_name': businessName,
        'branch_id': branchId,
        'branch_name': branchName,
        'cash_register_id': cashRegisterId,
        'cash_register_name': cashRegisterName,
        'receipt_sequence_id': receiptSequenceId,
        'receipt_sequence_name': receiptSequenceName,
        'receipt_prefix': receiptPrefix,
        'open_cash_session': openCashSession?.toJson(),
        'runtime_ready': runtimeReady,
        'resolved_at': resolvedAt.toIso8601String(),
      };
}

OperationalIntegrationException _malformed(String message) {
  return OperationalIntegrationException(
    kind: OperationalIntegrationFailureKind.malformedResponse,
    message: message,
  );
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map) throw _malformed('$field must be a JSON object.');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) throw _malformed('$key must be a non-empty string.');
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw _malformed('Expected a non-empty string or null.');
  }
  return value.trim();
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw _malformed('$key must be a boolean.');
  return value;
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw _malformed('$key must be a timestamp string.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw _malformed('$key is not a valid timestamp.');
  return parsed.toUtc();
}
