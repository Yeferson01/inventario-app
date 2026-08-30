import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/runtime_setup_models.dart';

class AppRuntimeContextStore {
  static const _contextPrefix = 'app_runtime_context';

  Future<void> saveContext(AppRuntimeContext context) async {
    final preferences = await SharedPreferences.getInstance();
    final branchId = _requiredBranchId(context.branchId);

    await preferences.setString(
      _contextKey(context.businessId, branchId, context.installationId),
      jsonEncode(context.toJson()),
    );
  }

  Future<AppRuntimeContext?> getContext({
    required String businessId,
    required String branchId,
    required String installationId,
  }) async {
    final preferences = await SharedPreferences.getInstance();

    final raw = preferences.getString(
      _contextKey(businessId, branchId, installationId),
    );

    if (raw != null && raw.trim().isNotEmpty) {
      return _decodeContext(raw);
    }

    // Migrate the former business+installation cache only when its embedded
    // branch matches the explicitly requested branch. A legacy context from a
    // different branch must never supply runtime IDs for the selected branch.
    final legacyRaw = preferences.getString(
      _legacyContextKey(businessId, installationId),
    );
    if (legacyRaw == null || legacyRaw.trim().isEmpty) {
      return null;
    }
    final legacy = _decodeContext(legacyRaw);
    if (legacy == null || legacy.branchId != branchId) {
      return null;
    }
    await saveContext(legacy);
    return legacy;
  }

  AppRuntimeContext? _decodeContext(String raw) {
    if (raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);

    if (decoded is! Map) {
      return null;
    }

    final map = Map<String, dynamic>.from(decoded);

    final appDeviceId = _string(map['app_device_id']);

    if (appDeviceId == null) {
      return null;
    }

    return AppRuntimeContext(
      businessId: _requiredString(map, 'business_id'),
      branchId: _string(map['branch_id']),
      profileId: _string(map['profile_id']),
      installationId: _requiredString(map, 'installation_id'),
      appDeviceId: appDeviceId,
      cashRegisterId: _string(map['cash_register_id']),
      cashSessionId: _string(map['cash_session_id']),
      receiptSequenceId: _string(map['receipt_sequence_id']),
    );
  }

  String _contextKey(
    String businessId,
    String branchId,
    String installationId,
  ) {
    return '$_contextPrefix.$businessId.$branchId.$installationId';
  }

  String _legacyContextKey(String businessId, String installationId) {
    return '$_contextPrefix.$businessId.$installationId';
  }

  String _requiredBranchId(String? value) {
    final branchId = _string(value);
    if (branchId == null) {
      throw ArgumentError('AppRuntimeContext requiere branchId explícita.');
    }
    return branchId;
  }

  String _requiredString(Map<String, dynamic> map, String key) {
    final value = _string(map[key]);

    if (value == null) {
      throw StateError('Contexto runtime inválido. Falta $key.');
    }

    return value;
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
}
