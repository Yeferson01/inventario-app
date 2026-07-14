import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_business_selection_models.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';
import 'package:inventario_frontend/features/sync/application/app_e2e_local_flow_models.dart';

void main() {
  group('AppE2ELocalFlowInput', () {
    test('serializes to json', () {
      const input = AppE2ELocalFlowInput(
        profileId: 'profile-1',
        isOnline: true,
        preferredBusinessId: 'business-1',
        preferredBranchId: 'branch-1',
        runManualSync: true,
      );

      final json = input.toJson();

      expect(json['profile_id'], equals('profile-1'));
      expect(json['is_online'], isTrue);
      expect(json['preferred_business_id'], equals('business-1'));
      expect(json['run_manual_sync'], isTrue);
    });
  });

  group('AppE2ELocalFlowResult', () {
    test('calculates successful local validation', () {
      final result = AppE2ELocalFlowResult(
        installationId: 'installation-1',
        availableContextCount: 1,
        didSelectContext: true,
        didResolveCurrentContext: true,
        didAttemptManualSync: false,
        didRunManualSync: false,
        reason: 'OK',
        selectedContext: const AppBusinessSelectionResult(
          selected: AppBusinessSelectionOption(
            membershipId: 'membership-1',
            businessId: 'business-1',
            businessName: 'Tienda',
            profileId: 'profile-1',
            roleId: 'role-1',
            roleName: 'owner',
          ),
          savedBusinessId: 'business-1',
          savedProfileId: 'profile-1',
        ),
        currentContext: AppCurrentContext(
          businessId: 'business-1',
          profileId: 'profile-1',
          installationId: 'installation-1',
          isOnline: true,
          roleName: 'owner',
          permissions: AppPermissionSet.fromIterable([
            'products.read',
            'products.create',
          ]),
        ),
      );

      expect(result.successfulLocalValidation, isTrue);
      expect(result.permissions.length, equals(2));

      final json = result.toJson();

      expect(json['successful_local_validation'], isTrue);
      expect(json['permissions'], contains('products.create'));
    });

    test('fails local validation when context is not resolved', () {
      const result = AppE2ELocalFlowResult(
        installationId: 'installation-1',
        availableContextCount: 1,
        didSelectContext: true,
        didResolveCurrentContext: false,
        didAttemptManualSync: false,
        didRunManualSync: false,
        reason: 'Context missing',
      );

      expect(result.successfulLocalValidation, isFalse);
    });
  });
}
