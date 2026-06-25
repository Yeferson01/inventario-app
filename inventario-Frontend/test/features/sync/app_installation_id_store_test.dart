import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_installation_id_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AppInstallationIdStore', () {
    test('creates and persists installation id', () async {
      SharedPreferences.setMockInitialValues({});

      final store = AppInstallationIdStore();

      final first = await store.getOrCreateInstallationId();
      final second = await store.getOrCreateInstallationId();

      expect(first, isNotEmpty);
      expect(second, equals(first));
    });
  });
}
