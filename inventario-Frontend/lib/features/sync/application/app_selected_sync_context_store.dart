import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AppSelectedSyncContext {
  const AppSelectedSyncContext({
    required this.businessId,
    this.branchId,
    this.profileId,
  });

  final String businessId;
  final String? branchId;
  final String? profileId;

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      'profile_id': profileId,
    };
  }

  factory AppSelectedSyncContext.fromJson(Map<String, dynamic> json) {
    final businessId = _string(json['business_id']);

    if (businessId == null) {
      throw StateError('AppSelectedSyncContext inválido: falta business_id.');
    }

    return AppSelectedSyncContext(
      businessId: businessId,
      branchId: _string(json['branch_id']),
      profileId: _string(json['profile_id']),
    );
  }

  static String? _string(Object? value) {
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

class AppSelectedSyncContextStore {
  static const _selectedContextKey = 'app_sync.selected_context';

  Future<void> saveSelectedContext(AppSelectedSyncContext context) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(
      _selectedContextKey,
      jsonEncode(context.toJson()),
    );
  }

  Future<AppSelectedSyncContext?> getSelectedContext() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_selectedContextKey);

    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);

    if (decoded is Map<String, dynamic>) {
      return AppSelectedSyncContext.fromJson(decoded);
    }

    if (decoded is Map) {
      return AppSelectedSyncContext.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    }

    return null;
  }

  Future<void> clearSelectedContext() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_selectedContextKey);
  }
}
