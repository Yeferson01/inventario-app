import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/data/models/operational_context_pull_models.dart';

void main() {
  group('OperationalContextSnapshot', () {
    test('calculates total records', () {
      const snapshot = OperationalContextSnapshot(
        businesses: [
          {'id': 'business-1'},
        ],
        profiles: [
          {'id': 'profile-1'},
        ],
        branches: [
          {'id': 'branch-1'},
        ],
        businessMembers: [
          {'id': 'member-1'},
        ],
        roles: [
          {'id': 'role-1'},
        ],
        permissions: [
          {'id': 'permission-1'},
          {'id': 'permission-2'},
        ],
        rolePermissions: [
          {
            'role_id': 'role-1',
            'permission_id': 'permission-1',
          },
        ],
      );

      expect(snapshot.totalRecords, equals(8));

      final json = snapshot.toJson();

      expect(json['businesses'], equals(1));
      expect(json['permissions'], equals(2));
      expect(json['total_records'], equals(8));
    });
  });

  group('OperationalContextPullResult', () {
    test('calculates total applied', () {
      const result = OperationalContextPullResult(
        businessId: 'business-1',
        profileId: 'profile-1',
        appliedBusinesses: 1,
        appliedProfiles: 1,
        appliedBranches: 2,
        appliedBusinessMembers: 1,
        appliedRoles: 3,
        appliedPermissions: 10,
        appliedRolePermissions: 20,
      );

      expect(result.totalApplied, equals(38));

      final json = result.toJson();

      expect(json['business_id'], equals('business-1'));
      expect(json['total_applied'], equals(38));
    });
  });
}
