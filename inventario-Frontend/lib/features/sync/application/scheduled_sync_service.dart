import '../../../core/logging/app_logger.dart';
import '../../catalog/application/catalog_sync_service.dart';
import '../../catalog/data/models/catalog_remote_models.dart';
import 'catalog_sync_upload_service.dart';
import 'scheduled_sync_models.dart';
import 'scheduled_sync_policy.dart';
import 'scheduled_sync_state_store.dart';

class ScheduledSyncService {
  ScheduledSyncService({
    required CatalogSyncUploadService catalogUploadService,
    required CatalogSyncService catalogPullService,
    required ScheduledSyncPolicy policy,
    required ScheduledSyncStateStore stateStore,
  })  : _catalogUploadService = catalogUploadService,
        _catalogPullService = catalogPullService,
        _policy = policy,
        _stateStore = stateStore;

  final CatalogSyncUploadService _catalogUploadService;
  final CatalogSyncService _catalogPullService;
  final ScheduledSyncPolicy _policy;
  final ScheduledSyncStateStore _stateStore;

  Future<ScheduledSyncDecision> evaluateRunDecision({
    ScheduledSyncTrigger? forcedTrigger,
    DateTime? now,
  }) async {
    final effectiveNow = now ?? DateTime.now();
    final completedSlots = await _stateStore.getCompletedSlotKeys();

    return _policy.evaluate(
      now: effectiveNow,
      completedSlotKeys: completedSlots,
      forcedTrigger: forcedTrigger,
    );
  }

  Future<ScheduledSyncRunResult> runIfDue({
    required String businessId,
    ScheduledSyncTrigger? forcedTrigger,
    DateTime? now,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final effectiveNow = now ?? DateTime.now();

    final completedSlots = await _stateStore.getCompletedSlotKeys();

    final decision = _policy.evaluate(
      now: effectiveNow,
      completedSlotKeys: completedSlots,
      forcedTrigger: forcedTrigger,
    );

    if (!decision.shouldRun) {
      final result = ScheduledSyncRunResult(
        didRun: false,
        trigger: decision.trigger,
        reason: decision.reason,
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        catalogUploadResult: null,
        catalogPullResult: null,
      );

      await _stateStore.saveLastResult(result.toJson());
      return result;
    }

    try {
      final uploadResult =
          await _catalogUploadService.uploadPendingCatalogBatches(
        businessId: businessId,
      );

      final pullResult = await _catalogPullService.pullCatalogDelta(
        businessId: businessId,
      );

      if (pullResult.completed) {
        await _stateStore.markSlotCompleted(decision.slotKey);
      }

      final resultReason = switch (pullResult.status) {
        CatalogSyncRunStatus.complete => decision.reason,
        CatalogSyncRunStatus.incomplete =>
          'Catálogo incompleto y reanudable; el slot no fue completado.',
        CatalogSyncRunStatus.failed =>
          'Pull de catálogo falló (${pullResult.failureClassification}).',
      };

      final result = ScheduledSyncRunResult(
        didRun: true,
        trigger: decision.trigger,
        reason: resultReason,
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        catalogUploadResult: uploadResult.toJson(),
        catalogPullResult: pullResult.toJson(),
      );

      await _stateStore.saveLastResult(result.toJson());

      if (pullResult.completed) {
        AppLogger.info(
          'Scheduled sync completed: trigger=${decision.trigger.code} '
          'business=$businessId slot=${decision.slotKey}',
        );
      } else {
        AppLogger.warning(
          'Scheduled sync did not complete catalog pull: '
          'status=${pullResult.status.name} business=$businessId',
        );
      }

      return result;
    } catch (error, stackTrace) {
      final result = ScheduledSyncRunResult(
        didRun: true,
        trigger: decision.trigger,
        reason: 'Scheduled sync failed: ${error.toString()}',
        startedAt: startedAt,
        finishedAt: DateTime.now().toUtc(),
        catalogUploadResult: null,
        catalogPullResult: null,
      );

      await _stateStore.saveLastResult(result.toJson());

      AppLogger.error(
        'Scheduled sync failed: trigger=${decision.trigger.code}',
        error: error,
        stackTrace: stackTrace,
      );

      rethrow;
    }
  }

  Future<ScheduledSyncRunResult> runForCashClose({
    required String businessId,
  }) {
    return runIfDue(
      businessId: businessId,
      forcedTrigger: ScheduledSyncTrigger.cashClose,
    );
  }

  Future<ScheduledSyncRunResult> runManual({
    required String businessId,
  }) {
    return runIfDue(
      businessId: businessId,
      forcedTrigger: ScheduledSyncTrigger.manual,
    );
  }
}
