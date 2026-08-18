import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AppSelectedSyncContext {
  const AppSelectedSyncContext({
    required this.businessId,
    required this.profileId,
    this.branchId,
  });

  final String businessId;
  final String? branchId;
  final String profileId;

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      'profile_id': profileId,
    };
  }

  factory AppSelectedSyncContext.fromJson(Map<String, dynamic> json) {
    final businessId = _string(json['business_id']);
    final profileId = _string(json['profile_id']);

    if (businessId == null || profileId == null) {
      throw StateError(
        'AppSelectedSyncContext inválido: falta business_id o profile_id.',
      );
    }

    return AppSelectedSyncContext(
      businessId: businessId,
      branchId: _string(json['branch_id']),
      profileId: profileId,
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
  static const _legacySelectedContextKey = 'app_sync.selected_context';
  static const _selectedContextKeyPrefix = 'app_sync.selected_context.';

  Future<void> saveSelectedContext(AppSelectedSyncContext context) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(
      _keyForProfile(context.profileId),
      jsonEncode(context.toJson()),
    );
  }

  Future<AppSelectedSyncContext?> getSelectedContext({
    required String profileId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final scopedRaw = preferences.getString(_keyForProfile(profileId));

    if (scopedRaw != null && scopedRaw.trim().isNotEmpty) {
      final scopedContext = _decodeContext(scopedRaw);
      return scopedContext.profileId == profileId ? scopedContext : null;
    }

    final legacyRaw = preferences.getString(_legacySelectedContextKey);
    if (legacyRaw == null || legacyRaw.trim().isEmpty) {
      return null;
    }
    AppSelectedSyncContext legacyContext;
    try {
      legacyContext = _decodeContext(legacyRaw);
    } on StateError {
      return null;
    } on FormatException {
      return null;
    }
    if (legacyContext.profileId != profileId) {
      return null;
    }

    await preferences.setString(
      _keyForProfile(profileId),
      jsonEncode(legacyContext.toJson()),
    );
    return legacyContext;
  }

  AppSelectedSyncContext _decodeContext(String raw) {
    if (raw.trim().isEmpty) {
      throw StateError('Selected sync context vacío.');
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

    throw StateError('Selected sync context inválido.');
  }

  Future<void> clearSelectedContext({required String profileId}) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_keyForProfile(profileId));
  }

  String _keyForProfile(String profileId) {
    final normalized = profileId.trim();
    if (normalized.isEmpty) {
      throw ArgumentError('profileId no puede estar vacío.');
    }
    return '$_selectedContextKeyPrefix$normalized';
  }
}
