import '../../../core/logging/app_logger.dart';
import 'app_runtime_setup_service.dart';
import 'app_sync_coordinator_models.dart';
import 'scheduled_sync_models.dart';
import 'scheduled_sync_service.dart';

class AppSyncCoordinatorService {
  AppSyncCoordinatorService({
    required AppRuntimeSetupService runtimeSetupService,
    required ScheduledSyncService scheduledSyncService,
  })  : _runtimeSetupService = runtimeSetupService,
        _scheduledSyncService = scheduledSyncService;

  final AppRuntimeSetupService _runtimeSetupService;
  final ScheduledSyncService _scheduledSyncService;

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

    final runtimeContext = await _runtimeSetupService.prepareRuntimeContext(
      businessId: input.businessId,
      branchId: input.branchId,
      profileId: input.profileId,
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
      scheduledSyncResult: scheduledResult,
    );
  }
}
