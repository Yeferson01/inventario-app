import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/dashboard/application/dashboard_user_identity_provider.dart';

void main() {
  test('known roles use Spanish labels; unknown identifiers are not exposed',
      () {
    expect(dashboardRoleLabel(['owner']), 'Dueño');
    expect(dashboardRoleLabel(['admin']), 'Administrador');
    expect(dashboardRoleLabel(['cashier']), 'Cajero');
    expect(dashboardRoleLabel(['warehouse']), 'Almacenista');
    expect(dashboardRoleLabel(['technician']), 'Técnico');
    expect(
        dashboardRoleLabel(['cashier', 'warehouse']), 'Cajero · Almacenista');
    expect(dashboardRoleLabel(['custom_internal_role']), 'Usuario');
  });
}
