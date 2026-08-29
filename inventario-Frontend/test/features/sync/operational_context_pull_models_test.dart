import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_context_local_dao.dart';
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

  test('local context applies only the requested profile membership', () async {
    final database = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(database.close);
    const snapshot = OperationalContextSnapshot(
      businesses: [
        {'id': 'business-1', 'name': 'Cronos Business'},
      ],
      profiles: [
        {'id': 'profile-current'},
      ],
      branches: [],
      businessMembers: [
        {
          'id': 'member-current',
          'business_id': 'business-1',
          'profile_id': 'profile-current',
          'role_id': 'role-owner',
        },
        {
          'id': 'member-foreign',
          'business_id': 'business-1',
          'profile_id': 'profile-foreign',
          'role_id': 'role-owner',
        },
      ],
      roles: [
        {'id': 'role-owner', 'name': 'owner', 'is_system_role': true},
      ],
      permissions: [],
      rolePermissions: [],
    );

    final result = await OperationalContextLocalDao(database).applySnapshot(
      businessId: 'business-1',
      profileId: 'profile-current',
      snapshot: snapshot,
    );

    expect(result.appliedBusinessMembers, 1);
    final memberships = await database.select(database.businessMembers).get();
    expect(memberships, hasLength(1));
    expect(memberships.single.id, 'member-current');
    expect(memberships.single.profileId, 'profile-current');
  });
}
