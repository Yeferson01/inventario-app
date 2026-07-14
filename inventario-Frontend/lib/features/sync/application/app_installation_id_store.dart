import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/app_uuid.dart';

class AppInstallationIdStore {
  static const _installationIdKey = 'app.installation_id';

  Future<String> getOrCreateInstallationId() async {
    final preferences = await SharedPreferences.getInstance();

    final existing = preferences.getString(_installationIdKey);

    if (existing != null && existing.trim().isNotEmpty) {
      return existing;
    }

    final created = AppUuid.v7();

    await preferences.setString(_installationIdKey, created);

    return created;
  }

  Future<void> resetInstallationIdForTesting() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_installationIdKey);
  }
}
