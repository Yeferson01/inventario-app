import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/runtime_setup_models.dart';

class AppRuntimeContextStore {
  static const _contextPrefix = 'app_runtime_context';

  Future<void> saveContext(AppRuntimeContext context) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(
      _contextKey(context.businessId, context.installationId),
      jsonEncode(context.toJson()),
    );
  }

  Future<AppRuntimeContext?> getContext({
    required String businessId,
    required String installationId,
  }) async {
    final preferences = await SharedPreferences.getInstance();

    final raw = preferences.getString(_contextKey(businessId, installationId));

    if (raw == null || raw.trim().isEmpty) {
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

  String _contextKey(String businessId, String installationId) {
    return '$_contextPrefix.$businessId.$installationId';
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
