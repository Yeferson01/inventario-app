import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_business_selection_models.dart';

void main() {
  group('AppBusinessSelectionOption', () {
    test('parses row and builds display name with branch', () {
      final option = AppBusinessSelectionOption.fromRow({
        'membership_id': 'membership-1',
        'business_id': 'business-1',
        'business_name': 'Tienda Principal',
        'branch_id': 'branch-1',
        'branch_name': 'Sucursal Centro',
        'profile_id': 'profile-1',
        'role_id': 'role-1',
        'role_name': 'owner',
      });

      expect(option.membershipId, equals('membership-1'));
      expect(option.businessId, equals('business-1'));
      expect(option.branchId, equals('branch-1'));
      expect(option.roleName, equals('owner'));
      expect(option.hasBranch, isTrue);
      expect(option.displayName, equals('Tienda Principal / Sucursal Centro'));
    });

    test('uses business name as display name when branch is missing', () {
      final option = AppBusinessSelectionOption.fromRow({
        'membership_id': 'membership-1',
        'business_id': 'business-1',
        'business_name': 'Tienda Principal',
        'profile_id': 'profile-1',
        'role_id': 'role-1',
        'role_name': 'admin',
      });

      expect(option.hasBranch, isFalse);
      expect(option.displayName, equals('Tienda Principal'));
    });

    test('throws when required field is missing', () {
      expect(
        () => AppBusinessSelectionOption.fromRow({
          'business_id': 'business-1',
          'business_name': 'Tienda Principal',
        }),
        throwsStateError,
      );
    });
  });

  group('AppBusinessSelectionResult', () {
    test('serializes selected result', () {
      const option = AppBusinessSelectionOption(
        membershipId: 'membership-1',
        businessId: 'business-1',
        businessName: 'Tienda Principal',
        branchId: 'branch-1',
        branchName: 'Sucursal Centro',
        profileId: 'profile-1',
        roleId: 'role-1',
        roleName: 'owner',
      );

      const result = AppBusinessSelectionResult(
        selected: option,
        savedBusinessId: 'business-1',
        savedBranchId: 'branch-1',
        savedProfileId: 'profile-1',
      );

      final json = result.toJson();

      expect(json['saved_business_id'], equals('business-1'));
      expect(json['saved_branch_id'], equals('branch-1'));
      expect(json['selected'], isA<Map<String, dynamic>>());
    });
  });
}
