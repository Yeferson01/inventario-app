import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/authorized_operational_context_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/datasources/runtime_resolution_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/datasources/runtime_setup_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/models/operational_integration_failure.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_setup_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('server-authoritative discovery', () {
    test('invokes the no-argument RPC and preserves explicit branch contexts',
        () async {
      var calls = 0;
      final dataSource =
          AuthorizedOperationalContextRemoteDataSource.withInvoker(
        () async {
          calls++;
          return _discoveryResponse([
            _contextJson(branchId: 'branch-x', branchName: 'X'),
            _contextJson(branchId: 'branch-y', branchName: 'Y'),
          ]);
        },
      );
      final service = AuthorizedOperationalContextService(
        remoteDataSource: dataSource,
        authenticatedProfileId: () => 'profile-1',
      );

      final contexts = await service.listAuthorizedContexts();

      expect(calls, 1);
      expect(contexts.map((item) => item.branchId), ['branch-x', 'branch-y']);
      expect(contexts.every((item) => item.branchId.isNotEmpty), isTrue);
    });

    test('preserves unioned permissions and multiple memberships as one row',
        () async {
      final dataSource =
          AuthorizedOperationalContextRemoteDataSource.withInvoker(
        () async => _discoveryResponse([
          _contextJson(
            membershipIds: const ['membership-business', 'membership-branch'],
            permissions: const ['inventory.read', 'sales.create'],
          ),
        ]),
      );
      final service = AuthorizedOperationalContextService(
        remoteDataSource: dataSource,
        authenticatedProfileId: () => 'profile-1',
      );

      final context = (await service.listAuthorizedContexts()).single;

      expect(context.membershipIds, hasLength(2));
      expect(
        context.effectivePermissions,
        ['inventory.read', 'sales.create'],
      );
    });

    test('rejects duplicate business and branch scopes', () async {
      final row = _contextJson();
      final service = AuthorizedOperationalContextService(
        remoteDataSource:
            AuthorizedOperationalContextRemoteDataSource.withInvoker(
          () async => _discoveryResponse([row, row]),
        ),
        authenticatedProfileId: () => 'profile-1',
      );

      await expectLater(
        service.listAuthorizedContexts(),
        throwsA(
          isA<OperationalIntegrationException>().having(
            (error) => error.kind,
            'kind',
            OperationalIntegrationFailureKind.malformedResponse,
          ),
        ),
      );
    });
  });

  group('canonical device registration', () {
    test('sends one canonical call without profile_id', () async {
      final calls = <Map<String, Object?>>[];
      final names = <String>[];
      final dataSource = RuntimeSetupRemoteDataSource.withInvoker(
        (name, parameters) async {
          names.add(name);
          calls.add(parameters);
          return _deviceResponse(branchId: 'branch-x');
        },
      );

      await dataSource.registerOrUpdateAppDevice(
        const RegisterAppDeviceInput(
          businessId: 'business-1',
          branchId: 'branch-x',
          installationId: 'installation-1',
        ),
      );

      expect(names, ['register_or_update_app_device']);
      expect(calls, hasLength(1));
      expect(calls.single.keys, {
        'p_business_id',
        'p_branch_id',
        'p_installation_id',
        'p_device_name',
        'p_platform',
        'p_app_version',
        'p_os_version',
        'p_metadata',
      });
      expect(calls.single.containsKey('p_profile_id'), isFalse);
    });

    test('branch switch accepts the same canonical device id', () async {
      final dataSource = RuntimeSetupRemoteDataSource.withInvoker(
        (name, parameters) async => _deviceResponse(
          branchId: parameters['p_branch_id']! as String,
        ),
      );

      final x = await dataSource.registerOrUpdateAppDevice(
        const RegisterAppDeviceInput(
          businessId: 'business-1',
          branchId: 'branch-x',
          installationId: 'installation-1',
        ),
      );
      final y = await dataSource.registerOrUpdateAppDevice(
        const RegisterAppDeviceInput(
          businessId: 'business-1',
          branchId: 'branch-y',
          installationId: 'installation-1',
        ),
      );

      expect(x.appDeviceId, 'device-1');
      expect(y.appDeviceId, x.appDeviceId);
      expect(y.branchId, 'branch-y');
    });

    test('maps blocked device errors without retrying another signature',
        () async {
      var calls = 0;
      final dataSource = RuntimeSetupRemoteDataSource.withInvoker(
        (name, parameters) async {
          calls++;
          throw const PostgrestException(
            message:
                'App device is blocked and cannot be reactivated by self-registration',
            code: 'P0001',
          );
        },
      );

      await expectLater(
        dataSource.registerOrUpdateAppDevice(
          const RegisterAppDeviceInput(
            businessId: 'business-1',
            branchId: 'branch-x',
            installationId: 'installation-1',
          ),
        ),
        throwsA(
          isA<OperationalIntegrationException>().having(
            (error) => error.kind,
            'kind',
            OperationalIntegrationFailureKind.deviceBlocked,
          ),
        ),
      );
      expect(calls, 1);
    });
  });

  test('runtime resolve sends only exact business and branch parameters',
      () async {
    Map<String, Object?>? captured;
    final dataSource = RuntimeResolutionRemoteDataSource.withInvoker(
      (parameters) async {
        captured = parameters;
        return _runtimeResponse();
      },
    );

    final runtime = await dataSource.resolve(
      businessId: 'business-1',
      branchId: 'branch-x',
    );

    expect(captured, {
      'p_business_id': 'business-1',
      'p_branch_id': 'branch-x',
    });
    expect(runtime.cashRegisterId, 'cash-1');
    expect(runtime.openCashSessionId, 'session-1');
  });
}

Map<String, Object?> _discoveryResponse(List<Map<String, Object?>> contexts) =>
    {
      'profile_id': 'profile-1',
      'contexts': contexts,
      'generated_at': '2026-08-20T12:00:00Z',
    };

Map<String, Object?> _contextJson({
  String branchId = 'branch-x',
  String branchName = 'X',
  List<String> membershipIds = const ['membership-1'],
  List<String> permissions = const ['inventory.read'],
}) =>
    {
      'profile_id': 'profile-1',
      'business_id': 'business-1',
      'business_name': 'Business',
      'business_status': 'active',
      'business_updated_at': '2026-08-20T10:00:00Z',
      'branch_id': branchId,
      'branch_name': branchName,
      'branch_status': 'active',
      'branch_updated_at': '2026-08-20T10:00:00Z',
      'membership_ids': membershipIds,
      'memberships_updated_at': '2026-08-20T10:00:00Z',
      'effective_roles': [
        {
          'role_id': 'role-1',
          'role_name': 'custom',
          'is_system_role': false,
          'membership_ids': membershipIds,
        },
      ],
      'effective_permissions': permissions,
    };

Map<String, Object?> _deviceResponse({required String branchId}) => {
      'app_device_id': 'device-1',
      'business_id': 'business-1',
      'branch_id': branchId,
      'profile_id': 'profile-1',
      'installation_id': 'installation-1',
      'status': 'active',
    };

Map<String, Object?> _runtimeResponse() => {
      'profile_id': 'profile-1',
      'business_id': 'business-1',
      'business_name': 'Business',
      'branch_id': 'branch-x',
      'branch_name': 'X',
      'cash_register_id': 'cash-1',
      'cash_register_name': 'Caja Principal',
      'receipt_sequence_id': 'receipt-1',
      'receipt_sequence_name': 'Recibos X',
      'receipt_prefix': 'POS',
      'open_cash_session': {
        'cash_session_id': 'session-1',
        'cash_register_id': 'cash-1',
        'status': 'open',
        'opened_by': 'profile-1',
        'opened_at': '2026-08-20T11:00:00Z',
      },
      'runtime_ready': true,
      'resolved_at': '2026-08-20T12:00:00Z',
    };
