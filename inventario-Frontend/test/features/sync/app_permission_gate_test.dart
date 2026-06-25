import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/presentation/widgets/app_permission_gate.dart';

void main() {
  group('Permission gate widgets', () {
    test('AppPermissionGate class exists', () {
      expect(AppPermissionGate, isNotNull);
    });

    test('AppAnyPermissionGate class exists', () {
      expect(AppAnyPermissionGate, isNotNull);
    });

    test('AppAllPermissionsGate class exists', () {
      expect(AppAllPermissionsGate, isNotNull);
    });
  });
}
