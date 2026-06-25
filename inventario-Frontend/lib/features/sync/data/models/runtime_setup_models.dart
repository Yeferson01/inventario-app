class RegisterAppDeviceInput {
  const RegisterAppDeviceInput({
    required this.businessId,
    required this.installationId,
    this.branchId,
    this.profileId,
    this.deviceName,
    this.platform,
    this.appVersion,
    this.osVersion,
    this.metadata,
  });

  final String businessId;
  final String installationId;

  final String? branchId;
  final String? profileId;
  final String? deviceName;
  final String? platform;
  final String? appVersion;
  final String? osVersion;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toRpcParamsWithPrefix({bool includeProfileId = true}) {
    return {
      'p_business_id': businessId,
      'p_branch_id': branchId,
      if (includeProfileId) 'p_profile_id': profileId,
      'p_installation_id': installationId,
      'p_device_name': deviceName,
      'p_platform': platform,
      'p_app_version': appVersion,
      'p_os_version': osVersion,
      'p_metadata': metadata ?? <String, dynamic>{},
    };
  }

  Map<String, dynamic> toRpcParamsWithoutPrefix(
      {bool includeProfileId = true}) {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      if (includeProfileId) 'profile_id': profileId,
      'installation_id': installationId,
      'device_name': deviceName,
      'platform': platform,
      'app_version': appVersion,
      'os_version': osVersion,
      'metadata': metadata ?? <String, dynamic>{},
    };
  }
}

class RegisteredAppDeviceResult {
  const RegisteredAppDeviceResult({
    required this.appDeviceId,
    required this.businessId,
    required this.installationId,
    required this.status,
    required this.raw,
  });

  final String appDeviceId;
  final String businessId;
  final String installationId;
  final String status;
  final Map<String, dynamic> raw;

  factory RegisteredAppDeviceResult.fromRpc(
    dynamic value, {
    required String fallbackBusinessId,
    required String fallbackInstallationId,
  }) {
    final map = _asMap(value);

    final appDeviceId = _string(
      map['app_device_id'] ??
          map['id'] ??
          map['device_id'] ??
          map['appDeviceId'],
    );

    if (appDeviceId == null) {
      throw StateError(
        'La RPC register_or_update_app_device no devolvió app_device_id/id.',
      );
    }

    return RegisteredAppDeviceResult(
      appDeviceId: appDeviceId,
      businessId: _string(map['business_id']) ?? fallbackBusinessId,
      installationId: _string(map['installation_id']) ?? fallbackInstallationId,
      status: _string(map['status']) ?? 'active',
      raw: map,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'app_device_id': appDeviceId,
      'business_id': businessId,
      'installation_id': installationId,
      'status': status,
      'raw': raw,
    };
  }
}

class EnsureBusinessRuntimeSetupInput {
  const EnsureBusinessRuntimeSetupInput({
    required this.businessId,
    this.branchId,
    this.profileId,
    this.appDeviceId,
    this.metadata,
  });

  final String businessId;
  final String? branchId;
  final String? profileId;
  final String? appDeviceId;
  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toRpcParamsWithPrefix({bool includeProfileId = true}) {
    return {
      'p_business_id': businessId,
      'p_branch_id': branchId,
      if (includeProfileId) 'p_profile_id': profileId,
      'p_app_device_id': appDeviceId,
      'p_metadata': metadata ?? <String, dynamic>{},
    };
  }

  Map<String, dynamic> toRpcParamsWithoutPrefix(
      {bool includeProfileId = true}) {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      if (includeProfileId) 'profile_id': profileId,
      'app_device_id': appDeviceId,
      'metadata': metadata ?? <String, dynamic>{},
    };
  }
}

class BusinessRuntimeSetupResult {
  const BusinessRuntimeSetupResult({
    required this.businessId,
    this.branchId,
    this.cashRegisterId,
    this.cashSessionId,
    this.receiptSequenceId,
    required this.raw,
  });

  final String businessId;
  final String? branchId;
  final String? cashRegisterId;
  final String? cashSessionId;
  final String? receiptSequenceId;
  final Map<String, dynamic> raw;

  factory BusinessRuntimeSetupResult.fromRpc(
    dynamic value, {
    required String fallbackBusinessId,
    String? fallbackBranchId,
  }) {
    final map = _asMap(value);

    return BusinessRuntimeSetupResult(
      businessId: _string(map['business_id']) ?? fallbackBusinessId,
      branchId: _string(map['branch_id']) ?? fallbackBranchId,
      cashRegisterId: _string(
        map['cash_register_id'] ?? map['default_cash_register_id'],
      ),
      cashSessionId: _string(
        map['cash_session_id'] ?? map['current_cash_session_id'],
      ),
      receiptSequenceId: _string(
        map['receipt_sequence_id'] ?? map['default_receipt_sequence_id'],
      ),
      raw: map,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      'cash_register_id': cashRegisterId,
      'cash_session_id': cashSessionId,
      'receipt_sequence_id': receiptSequenceId,
      'raw': raw,
    };
  }
}

class AppRuntimeContext {
  const AppRuntimeContext({
    required this.businessId,
    required this.installationId,
    required this.appDeviceId,
    this.branchId,
    this.profileId,
    this.cashRegisterId,
    this.cashSessionId,
    this.receiptSequenceId,
  });

  final String businessId;
  final String installationId;
  final String appDeviceId;

  final String? branchId;
  final String? profileId;
  final String? cashRegisterId;
  final String? cashSessionId;
  final String? receiptSequenceId;

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      'profile_id': profileId,
      'installation_id': installationId,
      'app_device_id': appDeviceId,
      'cash_register_id': cashRegisterId,
      'cash_session_id': cashSessionId,
      'receipt_sequence_id': receiptSequenceId,
    };
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }

  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  if (value is List && value.isNotEmpty) {
    final first = value.first;

    if (first is Map<String, dynamic>) {
      return first;
    }

    if (first is Map) {
      return Map<String, dynamic>.from(first);
    }
  }

  return {
    'value': value?.toString(),
  };
}

String? _string(Object? value) {
  if (value == null) {
    return null;
  }

  final text = value.toString().trim();

  if (text.isEmpty) {
    return null;
  }

  return text;
}
