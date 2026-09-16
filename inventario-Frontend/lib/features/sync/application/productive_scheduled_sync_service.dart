import '../../../core/logging/app_logger.dart';
import 'app_sync_coordinator_models.dart';
import 'productive_manual_sync_service.dart';
import 'scheduled_sync_models.dart';
import 'scheduled_sync_policy.dart';
import 'scheduled_sync_state_store.dart';

class ProductiveScheduledSyncResult {
  const ProductiveScheduledSyncResult({
    required this.didRun,
    required this.slotAttempted,
    required this.reason,
    this.trigger,
    this.slotKey,
    this.syncResult,
  });

  final bool didRun;
  final bool slotAttempted;
  final String reason;
  final ScheduledSyncTrigger? trigger;
  final String? slotKey;
  final ProductiveManualSyncResult? syncResult;
}

class ProductiveScheduledSyncService {
  ProductiveScheduledSyncService({
    required ProductiveManualSyncInputLoader inputLoader,
    required ProductiveManualSyncService productiveSyncService,
    required ScheduledSyncPolicy policy,
    required ScheduledSyncStateStore stateStore,
  })  : _inputLoader = inputLoader,
        _productiveSyncService = productiveSyncService,
        _policy = policy,
        _stateStore = stateStore;

  final ProductiveManualSyncInputLoader _inputLoader;
  final ProductiveManualSyncService _productiveSyncService;
  final ScheduledSyncPolicy _policy;
  final ScheduledSyncStateStore _stateStore;

  Future<ProductiveScheduledSyncResult>? _activeRun;

  Future<ProductiveScheduledSyncResult> runIfDue({DateTime? now}) {
    final activeRun = _activeRun;
    if (activeRun != null) return activeRun;

    final run = _runIfDue(now: now ?? DateTime.now());
    _activeRun = run;
    run.whenComplete(() {
      if (identical(_activeRun, run)) _activeRun = null;
    });
    return run;
  }

  Future<ProductiveScheduledSyncResult> _runIfDue({
    required DateTime now,
  }) async {
    final AppSyncCoordinatorInput? input;
    try {
      input = await _inputLoader();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'Scheduled productive sync could not load its context.',
        error: error,
        stackTrace: stackTrace,
      );
      return const ProductiveScheduledSyncResult(
        didRun: false,
        slotAttempted: false,
        reason: 'No hay un contexto operacional listo.',
      );
    }

    final scope = _scopeFrom(input);
    if (input == null || scope == null) {
      return const ProductiveScheduledSyncResult(
        didRun: false,
        slotAttempted: false,
        reason: 'No hay un contexto operacional listo.',
      );
    }

    final attemptedSlots = await _stateStore.getAttemptedScopedSlotKeys();
    final decision = _policy.evaluateScoped(
      now: now,
      scope: scope,
      attemptedSlotKeys: attemptedSlots,
    );
    if (!decision.shouldRun) {
      return ProductiveScheduledSyncResult(
        didRun: false,
        slotAttempted: true,
        reason: decision.reason,
        trigger: decision.trigger,
        slotKey: decision.slotKey,
      );
    }

    if (!input.isOnline) {
      return ProductiveScheduledSyncResult(
        didRun: false,
        slotAttempted: false,
        reason: 'Sin conexión; el slot permanece elegible para catch-up.',
        trigger: decision.trigger,
        slotKey: decision.slotKey,
      );
    }

    try {
      final syncResult = await _productiveSyncService.run(
        trigger: ProductiveSyncTrigger.scheduled,
        inputOverride: input,
      );
      final madeDomainAttempt =
          syncResult.domainResults.any((result) => result.attempted);
      final resultMatchesScope = _matchesScope(syncResult, scope);

      if (madeDomainAttempt && resultMatchesScope) {
        await _stateStore.markScopedSlotAttempted(decision.slotKey);
      }

      return ProductiveScheduledSyncResult(
        didRun: madeDomainAttempt && resultMatchesScope,
        slotAttempted: madeDomainAttempt && resultMatchesScope,
        reason: resultMatchesScope
            ? syncResult.message
            : 'La ejecución activa pertenecía a otro scope; este slot sigue '
                'elegible.',
        trigger: decision.trigger,
        slotKey: decision.slotKey,
        syncResult: syncResult,
      );
    } catch (error, stackTrace) {
      await _stateStore.markScopedSlotAttempted(decision.slotKey);
      AppLogger.error(
        'Scheduled productive sync failed after starting.',
        error: error,
        stackTrace: stackTrace,
      );
      return ProductiveScheduledSyncResult(
        didRun: true,
        slotAttempted: true,
        reason: 'El intento programado falló y se reintentará manualmente '
            'o en el siguiente slot.',
        trigger: decision.trigger,
        slotKey: decision.slotKey,
      );
    }
  }

  ScheduledSyncScope? _scopeFrom(AppSyncCoordinatorInput? input) {
    final profileId = input?.profileId?.trim();
    final businessId = input?.businessId.trim();
    final branchId = input?.branchId?.trim();
    if (profileId == null ||
        profileId.isEmpty ||
        businessId == null ||
        businessId.isEmpty ||
        branchId == null ||
        branchId.isEmpty) {
      return null;
    }
    return ScheduledSyncScope(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
    );
  }

  bool _matchesScope(
    ProductiveManualSyncResult result,
    ScheduledSyncScope expected,
  ) {
    final actual = result.scope;
    return actual != null &&
        actual.profileId == expected.profileId &&
        actual.businessId == expected.businessId &&
        actual.branchId == expected.branchId;
  }
}
