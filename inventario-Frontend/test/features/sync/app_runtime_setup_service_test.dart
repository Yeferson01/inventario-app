import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_runtime_setup_models.dart';
import 'package:inventario_frontend/features/sync/application/app_runtime_setup_service.dart';
import 'package:inventario_frontend/features/sync/data/models/authorized_operational_context_models.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_resolution_models.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_setup_models.dart';

void main() {
  test('normal preparation registers then resolves and never ensures',
      () async {
    var registerCalls = 0;
    var ensureCalls = 0;
    var resolveCalls = 0;
    final service = _service(
      register: (input) async {
        registerCalls++;
        return _device(branchId: input.branchId);
      },
      ensure: (input) async {
        ensureCalls++;
        return _setup();
      },
      resolve: ({
        required String profileId,
        required String businessId,
        required String branchId,
      }) async {
        resolveCalls++;
        return _runtime();
      },
    );

    final context = await service.prepareRuntimeContext(
      businessId: 'business-1',
      branchId: 'branch-x',
      profileId: 'profile-1',
      installationId: 'installation-1',
    );

    expect(registerCalls, 1);
    expect(resolveCalls, 1);
    expect(ensureCalls, 0);
    expect(context.cashRegisterId, 'cash-1');
  });

  test('settings.branches-only is not permitted to call ensure', () async {
    var ensureCalls = 0;
    final service = _service(
      ensure: (input) async {
        ensureCalls++;
        return _setup();
      },
    );

    final result = await service.ensureAdministrativeRuntime(
      context: _context(const ['settings.branches']),
      installationId: 'installation-1',
      appDeviceId: 'device-1',
    );

    expect(result.outcome, AdministrativeRuntimeSetupOutcome.notPermitted);
    expect(ensureCalls, 0);
  });

  test('settings.business explicitly ensures and then re-resolves runtime',
      () async {
    var ensureCalls = 0;
    var resolveCalls = 0;
    final service = _service(
      ensure: (input) async {
        ensureCalls++;
        expect(input.businessId, 'business-1');
        expect(input.branchId, 'branch-x');
        return _setup();
      },
      resolve: ({
        required String profileId,
        required String businessId,
        required String branchId,
      }) async {
        resolveCalls++;
        return _runtime();
      },
    );

    final result = await service.ensureAdministrativeRuntime(
      context: _context(const ['settings.business']),
      installationId: 'installation-1',
      appDeviceId: 'device-1',
    );

    expect(ensureCalls, 1);
    expect(resolveCalls, 1);
    expect(result.outcome, AdministrativeRuntimeSetupOutcome.completed);
    expect(result.runtime?.runtimeReady, isTrue);
  });
}

AppRuntimeSetupService _service({
  RuntimeDeviceRegistrationRunner? register,
  AdministrativeRuntimeEnsureRunner? ensure,
  RuntimeReadOnlyResolver? resolve,
}) {
  return AppRuntimeSetupService.withRunners(
    registerDevice:
        register ?? (input) async => _device(branchId: input.branchId),
    ensureRuntime: ensure ?? (input) async => _setup(),
    resolveRuntime: resolve ??
        ({
          required String profileId,
          required String businessId,
          required String branchId,
        }) async =>
            _runtime(),
    saveContext: (context) async {},
  );
}

AuthorizedOperationalContext _context(List<String> permissions) =>
    AuthorizedOperationalContext(
      profileId: 'profile-1',
      businessId: 'business-1',
      businessName: 'Business',
      businessStatus: 'active',
      businessUpdatedAt: DateTime.utc(2026, 8, 20),
      branchId: 'branch-x',
      branchName: 'X',
      branchStatus: 'active',
      branchUpdatedAt: DateTime.utc(2026, 8, 20),
      membershipIds: const ['membership-1'],
      membershipsUpdatedAt: DateTime.utc(2026, 8, 20),
      effectiveRoles: const [],
      effectivePermissions: permissions,
    );

RegisteredAppDeviceResult _device({required String branchId}) =>
    RegisteredAppDeviceResult(
      appDeviceId: 'device-1',
      businessId: 'business-1',
      branchId: branchId,
      installationId: 'installation-1',
      status: 'active',
      raw: const {},
    );

BusinessRuntimeSetupResult _setup() => const BusinessRuntimeSetupResult(
      businessId: 'business-1',
      branchId: 'branch-x',
      cashRegisterId: 'cash-1',
      receiptSequenceId: 'receipt-1',
      raw: {},
    );

ResolvedBusinessRuntime _runtime() => ResolvedBusinessRuntime(
      profileId: 'profile-1',
      businessId: 'business-1',
      businessName: 'Business',
      branchId: 'branch-x',
      branchName: 'X',
      cashRegisterId: 'cash-1',
      cashRegisterName: 'Caja Principal',
      receiptSequenceId: 'receipt-1',
      receiptSequenceName: 'Recibos X',
      receiptPrefix: 'POS',
      openCashSession: null,
      runtimeReady: true,
      resolvedAt: DateTime.utc(2026, 8, 20),
    );
