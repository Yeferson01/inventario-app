import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_uuid.dart';

class InstallationIdService {
  static const String _storageKey = 'app.installation_id';

  Future<String> getOrCreateInstallationId() async {
    final prefs = await SharedPreferences.getInstance();
    final currentValue = prefs.getString(_storageKey);

    if (currentValue != null && AppUuid.looksLikeUuid(currentValue)) {
      return currentValue;
    }

    final newValue = AppUuid.v7();
    await prefs.setString(_storageKey, newValue);

    return newValue;
  }

  Future<String?> getInstallationId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_storageKey);
  }

  Future<void> resetInstallationIdForDebugOnly() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
