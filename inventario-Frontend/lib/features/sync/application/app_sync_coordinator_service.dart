import '../../../core/logging/app_logger.dart';
import 'app_runtime_setup_service.dart';
import 'app_sync_coordinator_models.dart';
import 'operational_context_pull_service.dart';
import 'scheduled_sync_models.dart';
import 'scheduled_sync_service.dart';

class AppSyncCoordinatorService {
  AppSyncCoordinatorService({
    required AppRuntimeSetupService runtimeSetupService,
    required ScheduledSyncService scheduledSyncService,
    required OperationalContextPullService operationalContextPullService,
  })  : _runtimeSetupService = runtimeSetupService,
        _scheduledSyncService = scheduledSyncService,
        _operationalContextPullService = operationalContextPullService;

  final AppRuntimeSetupService _runtimeSetupService;
  final ScheduledSyncService _scheduledSyncService;
  final OperationalContextPullService _operationalContextPullService;

  Future<AppSyncCoordinatorResult> runScheduledSyncIfDue(
    AppSyncCoordinatorInput input,
  ) {
    return _run(
      input: input,
      forcedTrigger: null,
    );
  }

  Future<AppSyncCoordinatorResult> runSyncForCashClose(
    AppSyncCoordinatorInput input,
  ) {
    return _run(
      input: input,
      forcedTrigger: ScheduledSyncTrigger.cashClose,
    );
  }

  Future<AppSyncCoordinatorResult> runManualSync(
    AppSyncCoordinatorInput input,
  ) {
    return _run(
      input: input,
      forcedTrigger: ScheduledSyncTrigger.manual,
    );
  }

  Future<AppSyncCoordinatorResult> _run({
    required AppSyncCoordinatorInput input,
    required ScheduledSyncTrigger? forcedTrigger,
  }) async {
    final decision = await _scheduledSyncService.evaluateRunDecision(
      forcedTrigger: forcedTrigger,
      now: input.now,
    );

    if (!decision.shouldRun) {
      return AppSyncCoordinatorResult(
        didRun: false,
        didPrepareRuntime: false,
        trigger: decision.trigger,
        reason: decision.reason,
      );
    }

    if (!input.isOnline) {
      final reason =
          'Sync omitido: hay una ventana válida (${decision.trigger.code}), '
          'pero el dispositivo está offline.';

      AppLogger.info(reason);

      return AppSyncCoordinatorResult(
        didRun: false,
        didPrepareRuntime: false,
        trigger: decision.trigger,
        reason: reason,
      );
    }

    final branchId = input.branchId?.trim();
    final profileId = input.profileId?.trim();
    if (branchId == null ||
        branchId.isEmpty ||
        profileId == null ||
        profileId.isEmpty) {
      const reason =
          'Sync omitido: se requiere profile y branch operacional explícita.';
      AppLogger.info(reason);
      return AppSyncCoordinatorResult(
        didRun: false,
        didPrepareRuntime: false,
        trigger: decision.trigger,
        reason: reason,
      );
    }

    final runtimeContext = await _runtimeSetupService.prepareRuntimeContext(
      businessId: input.businessId,
      branchId: branchId,
      profileId: profileId,
      installationId: input.installationId,
      deviceName: input.deviceName,
      platform: input.platform,
      appVersion: input.appVersion,
      osVersion: input.osVersion,
      metadata: {
        'source': 'app_sync_coordinator',
        'trigger': decision.trigger.code,
        if (input.metadata != null) ...input.metadata!,
      },
    );

    final operationalContextPullResult =
        await _pullOperationalContextIfPossible(
      businessId: runtimeContext.businessId,
      profileId: runtimeContext.profileId ?? input.profileId,
    );

    final scheduledResult = await _scheduledSyncService.runIfDue(
      businessId: runtimeContext.businessId,
      forcedTrigger: forcedTrigger,
      now: input.now,
    );

    return AppSyncCoordinatorResult(
      didRun: scheduledResult.didRun,
      didPrepareRuntime: true,
      trigger: decision.trigger,
      reason: scheduledResult.reason,
      runtimeContext: runtimeContext,
      operationalContextPullResult: operationalContextPullResult,
      scheduledSyncResult: scheduledResult,
    );
  }

  Future<Map<String, dynamic>?> _pullOperationalContextIfPossible({
    required String businessId,
    required String? profileId,
  }) async {
    final effectiveProfileId = profileId?.trim();

    if (effectiveProfileId == null || effectiveProfileId.isEmpty) {
      AppLogger.info(
        'Operational context pull skipped: profileId is missing.',
      );

      return null;
    }

    final result = await _operationalContextPullService.pullAndApply(
      businessId: businessId,
      profileId: effectiveProfileId,
    );

    return result.toJson();
  }
}
