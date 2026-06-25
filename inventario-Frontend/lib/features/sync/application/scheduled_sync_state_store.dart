import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ScheduledSyncStateStore {
  static const _completedSlotsKey = 'scheduled_sync.completed_slots';
  static const _lastResultKey = 'scheduled_sync.last_result';

  Future<Set<String>> getCompletedSlotKeys() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_completedSlotsKey);

    if (raw == null || raw.trim().isEmpty) {
      return <String>{};
    }

    final decoded = jsonDecode(raw);

    if (decoded is! List) {
      return <String>{};
    }

    return decoded.map((item) => item.toString()).toSet();
  }

  Future<void> markSlotCompleted(String slotKey) async {
    final preferences = await SharedPreferences.getInstance();
    final slots = await getCompletedSlotKeys();

    slots.add(slotKey);

    await preferences.setString(
      _completedSlotsKey,
      jsonEncode(slots.toList()..sort()),
    );
  }

  Future<void> saveLastResult(Map<String, dynamic> result) async {
    final preferences = await SharedPreferences.getInstance();

    await preferences.setString(
      _lastResultKey,
      jsonEncode(result),
    );
  }

  Future<Map<String, dynamic>?> getLastResult() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_lastResultKey);

    if (raw == null || raw.trim().isEmpty) {
      return null;
    }

    final decoded = jsonDecode(raw);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }

    return null;
  }
}
