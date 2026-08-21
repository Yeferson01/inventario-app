import '../../../core/logging/app_logger.dart';
import '../data/datasources/runtime_setup_remote_datasource.dart';
import '../data/models/authorized_operational_context_models.dart';
import '../data/models/runtime_resolution_models.dart';
import '../data/models/runtime_setup_models.dart';
import 'app_runtime_context_store.dart';
import 'app_runtime_setup_models.dart';
import 'runtime_resolution_service.dart';

typedef RuntimeDeviceRegistrationRunner = Future<RegisteredAppDeviceResult>
    Function(RegisterAppDeviceInput input);
typedef AdministrativeRuntimeEnsureRunner = Future<BusinessRuntimeSetupResult>
    Function(EnsureBusinessRuntimeSetupInput input);
typedef RuntimeReadOnlyResolver = Future<ResolvedBusinessRuntime> Function({
  required String profileId,
  required String businessId,
  required String branchId,
});
typedef RuntimeContextWriter = Future<void> Function(AppRuntimeContext context);

class AppRuntimeSetupService {
  factory AppRuntimeSetupService({
    required RuntimeSetupRemoteDataSource remoteDataSource,
    required RuntimeResolutionService runtimeResolutionService,
    required AppRuntimeContextStore contextStore,
  }) {
    return AppRuntimeSetupService.withRunners(
      registerDevice: remoteDataSource.registerOrUpdateAppDevice,
      ensureRuntime: remoteDataSource.ensureBusinessRuntimeSetup,
      resolveRuntime: runtimeResolutionService.resolve,
      saveContext: contextStore.saveContext,
    );
  }

  AppRuntimeSetupService.withRunners({
    required RuntimeDeviceRegistrationRunner registerDevice,
    required AdministrativeRuntimeEnsureRunner ensureRuntime,
    required RuntimeReadOnlyResolver resolveRuntime,
    required RuntimeContextWriter saveContext,
  })  : _registerDevice = registerDevice,
        _ensureRuntime = ensureRuntime,
        _resolveRuntime = resolveRuntime,
        _saveContext = saveContext;

  final RuntimeDeviceRegistrationRunner _registerDevice;
  final AdministrativeRuntimeEnsureRunner _ensureRuntime;
  final RuntimeReadOnlyResolver _resolveRuntime;
  final RuntimeContextWriter _saveContext;

  /// Registers the canonical device and resolves existing runtime read-only.
  /// Missing infrastructure is never created by this normal preparation path.
  Future<AppRuntimeContext> prepareRuntimeContext({
    required String businessId,
    required String branchId,
    required String profileId,
    required String installationId,
    String? deviceName,
    String? platform,
    String? appVersion,
    String? osVersion,
    Map<String, dynamic>? metadata,
  }) async {
    final registeredDevice = await _registerDevice(
      RegisterAppDeviceInput(
        businessId: businessId,
        branchId: branchId,
        installationId: installationId,
        deviceName: deviceName,
        platform: platform,
        appVersion: appVersion,
        osVersion: osVersion,
        metadata: {
          'source': 'flutter_runtime_resolve',
          if (metadata != null) ...metadata,
        },
      ),
    );
    final runtime = await _resolveRuntime(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
    );
    final context = _contextFromRuntime(
      runtime: runtime,
      profileId: profileId,
      installationId: installationId,
      appDeviceId: registeredDevice.appDeviceId,
    );
    await _saveContext(context);
    AppLogger.info(
      'Runtime resolved: business=$businessId branch=$branchId '
      'appDevice=${context.appDeviceId} ready=${runtime.runtimeReady}',
    );
    return context;
  }

  /// Explicit administrative action. `settings.business` is the sole client
  /// capability gate and the server remains the final security authority.
  Future<AdministrativeRuntimeSetupResult> ensureAdministrativeRuntime({
    required AuthorizedOperationalContext context,
    required String installationId,
    required String appDeviceId,
    Map<String, dynamic>? metadata,
  }) async {
    if (!context.effectivePermissions.contains('settings.business')) {
      return const AdministrativeRuntimeSetupResult(
        outcome: AdministrativeRuntimeSetupOutcome.notPermitted,
        message: 'The context cannot request administrative runtime setup.',
      );
    }
    final setup = await _ensureRuntime(
      EnsureBusinessRuntimeSetupInput(
        businessId: context.businessId,
        branchId: context.branchId,
        appDeviceId: appDeviceId,
        metadata: {
          'source': 'explicit_administrative_runtime_setup',
          if (metadata != null) ...metadata,
        },
      ),
    );
    final resolved = await _resolveRuntime(
      profileId: context.profileId,
      businessId: context.businessId,
      branchId: context.branchId,
    );
    if (!resolved.runtimeReady) {
      return AdministrativeRuntimeSetupResult(
        outcome: AdministrativeRuntimeSetupOutcome.runtimeStillMissing,
        message: 'Runtime remains incomplete after administrative setup.',
        setupResult: setup,
        runtime: resolved,
      );
    }
    await _saveContext(
      _contextFromRuntime(
        runtime: resolved,
        profileId: context.profileId,
        installationId: installationId,
        appDeviceId: appDeviceId,
      ),
    );
    return AdministrativeRuntimeSetupResult(
      outcome: AdministrativeRuntimeSetupOutcome.completed,
      message: 'Administrative runtime setup completed and re-resolved.',
      setupResult: setup,
      runtime: resolved,
    );
  }

  AppRuntimeContext _contextFromRuntime({
    required ResolvedBusinessRuntime runtime,
    required String profileId,
    required String installationId,
    required String appDeviceId,
  }) {
    return AppRuntimeContext(
      businessId: runtime.businessId,
      branchId: runtime.branchId,
      profileId: profileId,
      installationId: installationId,
      appDeviceId: appDeviceId,
      cashRegisterId: runtime.cashRegisterId,
      cashSessionId: runtime.openCashSessionId,
      receiptSequenceId: runtime.receiptSequenceId,
    );
  }
}
