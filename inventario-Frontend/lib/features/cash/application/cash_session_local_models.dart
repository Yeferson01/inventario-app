class OpenCashSessionInput {
  const OpenCashSessionInput({
    required this.businessId,
    required this.branchId,
    required this.profileId,
    required this.cashRegisterId,
    this.openingCashAmount = 0,
    this.appDeviceId,
    this.deviceInstallationId,
    this.metadata = const {},
  });

  final String businessId;
  final String branchId;
  final String profileId;
  final String cashRegisterId;
  final double openingCashAmount;
  final String? appDeviceId;
  final String? deviceInstallationId;
  final Map<String, dynamic> metadata;
}

class CashRecoveryRequiredException implements Exception {
  const CashRecoveryRequiredException({
    required this.cashRegisterId,
    required this.businessId,
    required this.branchId,
  });

  final String cashRegisterId;
  final String businessId;
  final String branchId;

  @override
  String toString() => 'CashRecoveryRequiredException: canonical cash register '
      '$cashRegisterId is not materialized for $businessId/$branchId.';
}

class LocalCashRegisterResult {
  const LocalCashRegisterResult({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.name,
    required this.code,
    required this.created,
  });

  final String id;
  final String businessId;
  final String branchId;
  final String name;
  final String code;
  final bool created;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'branch_id': branchId,
      'name': name,
      'code': code,
      'created': created,
    };
  }
}

class LocalCashSessionResult {
  const LocalCashSessionResult({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.cashRegisterId,
    required this.openedByProfileId,
    required this.openedAt,
    required this.openingCashAmount,
    required this.status,
    required this.created,
  });

  final String id;
  final String businessId;
  final String branchId;
  final String cashRegisterId;
  final String? openedByProfileId;
  final DateTime openedAt;
  final double openingCashAmount;
  final String status;
  final bool created;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'branch_id': branchId,
      'cash_register_id': cashRegisterId,
      'opened_by_profile_id': openedByProfileId,
      'opened_at': openedAt.toUtc().toIso8601String(),
      'opening_cash_amount': openingCashAmount,
      'status': status,
      'created': created,
    };
  }
}

class OpenCashSessionResult {
  const OpenCashSessionResult({
    required this.cashRegister,
    required this.cashSession,
    required this.reusedOpenSession,
  });

  final LocalCashRegisterResult cashRegister;
  final LocalCashSessionResult cashSession;
  final bool reusedOpenSession;

  Map<String, dynamic> toJson() {
    return {
      'cash_register': cashRegister.toJson(),
      'cash_session': cashSession.toJson(),
      'reused_open_session': reusedOpenSession,
    };
  }
}

class CloseCashSessionInput {
  const CloseCashSessionInput({
    required this.businessId,
    required this.branchId,
    required this.profileId,
    required this.actualClosingAmount,
    this.notes,
  });

  final String businessId;
  final String branchId;
  final String profileId;
  final double actualClosingAmount;
  final String? notes;
}

class CloseCashSessionResult {
  const CloseCashSessionResult({
    required this.cashSessionId,
    required this.cashRegisterId,
    required this.businessId,
    required this.branchId,
    required this.expectedCashAmount,
    required this.actualClosingAmount,
    required this.differenceAmount,
    required this.status,
  });

  final String cashSessionId;
  final String cashRegisterId;
  final String businessId;
  final String branchId;
  final double expectedCashAmount;
  final double actualClosingAmount;
  final double differenceAmount;
  final String status;

  Map<String, dynamic> toJson() {
    return {
      'cash_session_id': cashSessionId,
      'cash_register_id': cashRegisterId,
      'business_id': businessId,
      'branch_id': branchId,
      'expected_cash_amount': expectedCashAmount,
      'closing_cash_amount': actualClosingAmount,
      'actual_closing_amount': actualClosingAmount,
      'difference_amount': differenceAmount,
      'status': status,
    };
  }
}
