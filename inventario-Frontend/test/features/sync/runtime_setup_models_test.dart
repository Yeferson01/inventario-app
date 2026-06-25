import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_setup_models.dart';

void main() {
  group('RegisterAppDeviceInput', () {
    test('builds prefixed rpc params', () {
      const input = RegisterAppDeviceInput(
        businessId: 'business-1',
        branchId: 'branch-1',
        profileId: 'profile-1',
        installationId: 'installation-1',
        deviceName: 'Caja Android 1',
        platform: 'android',
        appVersion: '1.0.0',
        osVersion: 'Android 14',
        metadata: {
          'model': 'test-device',
        },
      );

      final params = input.toRpcParamsWithPrefix();

      expect(params['p_business_id'], equals('business-1'));
      expect(params['p_branch_id'], equals('branch-1'));
      expect(params['p_profile_id'], equals('profile-1'));
      expect(params['p_installation_id'], equals('installation-1'));
      expect(params['p_platform'], equals('android'));
      expect(params['p_metadata'], isA<Map<String, dynamic>>());
    });

    test('builds unprefixed rpc params without profile id', () {
      const input = RegisterAppDeviceInput(
        businessId: 'business-1',
        installationId: 'installation-1',
      );

      final params = input.toRpcParamsWithoutPrefix(includeProfileId: false);

      expect(params['business_id'], equals('business-1'));
      expect(params['installation_id'], equals('installation-1'));
      expect(params.containsKey('profile_id'), isFalse);
    });
  });

  group('RegisteredAppDeviceResult', () {
    test('parses result from id', () {
      final result = RegisteredAppDeviceResult.fromRpc(
        {
          'id': 'device-1',
          'business_id': 'business-1',
          'installation_id': 'installation-1',
          'status': 'active',
        },
        fallbackBusinessId: 'business-1',
        fallbackInstallationId: 'installation-1',
      );

      expect(result.appDeviceId, equals('device-1'));
      expect(result.status, equals('active'));
    });

    test('throws if device id is missing', () {
      expect(
        () => RegisteredAppDeviceResult.fromRpc(
          {
            'business_id': 'business-1',
          },
          fallbackBusinessId: 'business-1',
          fallbackInstallationId: 'installation-1',
        ),
        throwsStateError,
      );
    });
  });

  group('BusinessRuntimeSetupResult', () {
    test('parses runtime setup result', () {
      final result = BusinessRuntimeSetupResult.fromRpc(
        {
          'business_id': 'business-1',
          'branch_id': 'branch-1',
          'cash_register_id': 'cash-register-1',
          'receipt_sequence_id': 'receipt-sequence-1',
        },
        fallbackBusinessId: 'business-1',
      );

      expect(result.businessId, equals('business-1'));
      expect(result.branchId, equals('branch-1'));
      expect(result.cashRegisterId, equals('cash-register-1'));
      expect(result.receiptSequenceId, equals('receipt-sequence-1'));
    });
  });

  group('AppRuntimeContext', () {
    test('serializes to json', () {
      const context = AppRuntimeContext(
        businessId: 'business-1',
        branchId: 'branch-1',
        profileId: 'profile-1',
        installationId: 'installation-1',
        appDeviceId: 'device-1',
        cashRegisterId: 'cash-register-1',
      );

      final json = context.toJson();

      expect(json['business_id'], equals('business-1'));
      expect(json['branch_id'], equals('branch-1'));
      expect(json['app_device_id'], equals('device-1'));
      expect(json['installation_id'], equals('installation-1'));
    });
  });
}
