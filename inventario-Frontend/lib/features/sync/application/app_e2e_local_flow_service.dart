import '../../../core/logging/app_logger.dart';
import 'app_business_selection_models.dart';
import 'app_business_selection_service.dart';
import 'app_context_service.dart';
import 'app_e2e_local_flow_models.dart';
import 'app_installation_id_store.dart';
import 'app_sync_coordinator_models.dart';
import 'app_sync_coordinator_service.dart';
import 'operational_context_pull_service.dart';

class AppE2ELocalFlowService {
  AppE2ELocalFlowService({
    required AppBusinessSelectionService businessSelectionService,
    required AppContextService appContextService,
    required AppSyncCoordinatorService syncCoordinatorService,
    required AppInstallationIdStore installationIdStore,
    required OperationalContextPullService operationalContextPullService,
  })  : _businessSelectionService = businessSelectionService,
        _appContextService = appContextService,
        _syncCoordinatorService = syncCoordinatorService,
        _installationIdStore = installationIdStore,
        _operationalContextPullService = operationalContextPullService;

  final AppBusinessSelectionService _businessSelectionService;
  final AppContextService _appContextService;
  final AppSyncCoordinatorService _syncCoordinatorService;
  final AppInstallationIdStore _installationIdStore;
  final OperationalContextPullService _operationalContextPullService;

  Future<AppE2ELocalFlowResult> run(
    AppE2ELocalFlowInput input,
  ) async {
    final installationId =
        await _installationIdStore.getOrCreateInstallationId();

    var options = await _businessSelectionService.getAvailableContexts(
      profileId: input.profileId,
    );

    Map<String, dynamic>? preContextPullResult;

    if (options.isEmpty &&
        input.preferredBusinessId != null &&
        input.preferredBusinessId!.trim().isNotEmpty) {
      try {
        final pullResult = await _operationalContextPullService.pullAndApply(
          businessId: input.preferredBusinessId!.trim(),
          profileId: input.profileId,
        );

        preContextPullResult = pullResult.toJson();

        options = await _businessSelectionService.getAvailableContexts(
          profileId: input.profileId,
        );
      } catch (error, stackTrace) {
        AppLogger.error(
          'Pre-context operational pull failed: $error',
          error: error,
          stackTrace: stackTrace,
        );

        return AppE2ELocalFlowResult(
          installationId: installationId,
          availableContextCount: 0,
          didSelectContext: false,
          didResolveCurrentContext: false,
          didAttemptManualSync: input.runManualSync,
          didRunManualSync: false,
          reason:
              'No hay contextos locales y falló el pull operativo previo: $error',
          manualSyncResult: {
            'pre_context_pull_error': error.toString(),
            'pre_context_pull_stack_trace': stackTrace.toString(),
          },
        );
      }
    }

    if (options.isEmpty) {
      return AppE2ELocalFlowResult(
        installationId: installationId,
        availableContextCount: 0,
        didSelectContext: false,
        didResolveCurrentContext: false,
        didAttemptManualSync: input.runManualSync,
        didRunManualSync: false,
        reason: 'No hay negocios/sucursales disponibles para el perfil actual. '
            'Para una primera prueba real, informa preferredBusinessId.',
        manualSyncResult: preContextPullResult == null
            ? null
            : {
                'pre_context_pull_result': preContextPullResult,
              },
      );
    }

    final selectedResult = await _selectContext(
      input: input,
      options: options,
    );

    final currentContext = await _appContextService.loadCurrentContext(
      installationId: installationId,
      isOnline: input.isOnline,
      lastSyncStatus: input.lastSyncStatus,
    );

    if (currentContext == null) {
      return AppE2ELocalFlowResult(
        installationId: installationId,
        availableContextCount: options.length,
        didSelectContext: true,
        didResolveCurrentContext: false,
        didAttemptManualSync: input.runManualSync,
        didRunManualSync: false,
        reason:
            'Se seleccionó contexto, pero AppCurrentContext no pudo resolverse.',
        selectedContext: selectedResult,
      );
    }

    Map<String, dynamic>? manualSyncResult;
    var didRunManualSync = false;

    if (input.runManualSync) {
      final syncResult = await _syncCoordinatorService.runManualSync(
        AppSyncCoordinatorInput(
          businessId: currentContext.businessId,
          branchId: currentContext.branchId,
          profileId: currentContext.profileId ?? input.profileId,
          installationId: installationId,
          isOnline: input.isOnline,
          deviceName: input.deviceName,
          platform: input.platform,
          appVersion: input.appVersion,
          osVersion: input.osVersion,
          metadata: {
            'source': 'app_e2e_local_flow',
            if (input.metadata != null) ...input.metadata!,
          },
        ),
      );

      manualSyncResult = syncResult.toJson();
      didRunManualSync = syncResult.didRun;
    }

    final result = AppE2ELocalFlowResult(
      installationId: installationId,
      availableContextCount: options.length,
      didSelectContext: true,
      didResolveCurrentContext: true,
      didAttemptManualSync: input.runManualSync,
      didRunManualSync: didRunManualSync,
      reason: input.runManualSync
          ? 'Validación local completada y sync manual controlado ejecutado.'
          : 'Validación local completada sin ejecutar sync manual.',
      selectedContext: selectedResult,
      currentContext: currentContext,
      manualSyncResult: {
        if (preContextPullResult != null)
          'pre_context_pull_result': preContextPullResult,
        if (manualSyncResult != null) 'manual_sync_result': manualSyncResult,
      },
    );

    AppLogger.info(
      'E2E local flow completed: '
      'business=${currentContext.businessId} '
      'branch=${currentContext.branchId} '
      'role=${currentContext.roleName} '
      'permissions=${result.permissions.length}',
    );

    return result;
  }

  Future<AppBusinessSelectionResult> _selectContext({
    required AppE2ELocalFlowInput input,
    required List<AppBusinessSelectionOption> options,
  }) async {
    final preferredBusinessId = input.preferredBusinessId?.trim();
    final preferredBranchId = input.preferredBranchId?.trim();

    if (preferredBusinessId != null && preferredBusinessId.isNotEmpty) {
      return _businessSelectionService.selectContext(
        profileId: input.profileId,
        businessId: preferredBusinessId,
        branchId: preferredBranchId != null && preferredBranchId.isNotEmpty
            ? preferredBranchId
            : null,
      );
    }

    final existing = await _businessSelectionService.getSelectedOption(
      profileId: input.profileId,
    );

    if (existing != null) {
      return _businessSelectionService.selectContext(
        profileId: input.profileId,
        businessId: existing.businessId,
        branchId: existing.branchId,
      );
    }

    final first = options.first;

    return _businessSelectionService.selectContext(
      profileId: input.profileId,
      businessId: first.businessId,
      branchId: first.branchId,
    );
  }
}
