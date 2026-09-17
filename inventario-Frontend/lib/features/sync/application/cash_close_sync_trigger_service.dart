import '../../cash/application/cash_session_local_models.dart';
import '../../cash/application/cash_session_local_service.dart';
import 'productive_manual_sync_service.dart';

enum CashCloseSyncBlockReason {
  unavailable,
  retryablePending,
  requiresAttention,
  scopeMismatch,
}

class CashCloseSyncBlockedException implements Exception {
  const CashCloseSyncBlockedException(this.reason, this.message);

  final CashCloseSyncBlockReason reason;
  final String message;

  @override
  String toString() => message;
}

class ProductiveCashCloseResult {
  const ProductiveCashCloseResult({
    required this.closeResult,
    required this.preCloseSyncResult,
    required this.nonCriticalPendingDomains,
  });

  final CloseCashSessionResult closeResult;
  final ProductiveManualSyncResult preCloseSyncResult;
  final Set<ProductiveSyncDomain> nonCriticalPendingDomains;
}

class CashCloseSyncTriggerService {
  CashCloseSyncTriggerService({
    required ProductiveManualSyncService productiveSyncService,
    required CashSessionLocalService cashSessionService,
  })  : _productiveSyncService = productiveSyncService,
        _cashSessionService = cashSessionService;

  final ProductiveManualSyncService _productiveSyncService;
  final CashSessionLocalService _cashSessionService;
  Future<ProductiveCashCloseResult>? _activeClose;

  Future<ProductiveCashCloseResult> closeCashSession(
    CloseCashSessionInput input,
  ) {
    final activeClose = _activeClose;
    if (activeClose != null) return activeClose;

    final close = _closeCashSession(input);
    _activeClose = close;
    close.then<void>(
      (_) {
        if (identical(_activeClose, close)) _activeClose = null;
      },
      onError: (Object _, StackTrace __) {
        if (identical(_activeClose, close)) _activeClose = null;
      },
    );
    return close;
  }

  Future<ProductiveCashCloseResult> _closeCashSession(
    CloseCashSessionInput input,
  ) async {
    final syncResult = await _productiveSyncService.run(
      trigger: ProductiveSyncTrigger.cashClose,
    );

    if (syncResult.outcome == ProductiveManualSyncOutcome.unavailable) {
      throw const CashCloseSyncBlockedException(
        CashCloseSyncBlockReason.unavailable,
        'No se pudo completar el cierre ahora.',
      );
    }

    _assertExpectedScope(syncResult, input);
    if (syncResult.outcome == ProductiveManualSyncOutcome.requiresAttention ||
        syncResult.domainResults.any((result) => result.requiresAttention)) {
      throw const CashCloseSyncBlockedException(
        CashCloseSyncBlockReason.requiresAttention,
        'Hay operaciones pendientes que necesitan revisión.',
      );
    }
    if (syncResult.outcome == ProductiveManualSyncOutcome.failed) {
      throw const CashCloseSyncBlockedException(
        CashCloseSyncBlockReason.retryablePending,
        'No se pudo completar el cierre ahora.',
      );
    }

    final criticalResults = syncResult.domainResults.where(
      (result) =>
          result.domain == ProductiveSyncDomain.cash ||
          result.domain == ProductiveSyncDomain.pos,
    );
    if (criticalResults.length != 2 ||
        criticalResults.any((result) =>
            !result.attempted ||
            !result.succeeded ||
            result.pending ||
            result.failedRetryable)) {
      throw const CashCloseSyncBlockedException(
        CashCloseSyncBlockReason.retryablePending,
        'No se pudo completar el cierre ahora.',
      );
    }

    final nonCriticalPending = syncResult.domainResults
        .where((result) =>
            result.domain != ProductiveSyncDomain.cash &&
            result.domain != ProductiveSyncDomain.pos &&
            (result.pending || result.failedRetryable || !result.succeeded))
        .map((result) => result.domain)
        .toSet();

    final closeResult = await _cashSessionService.closeCashSession(input);
    return ProductiveCashCloseResult(
      closeResult: closeResult,
      preCloseSyncResult: syncResult,
      nonCriticalPendingDomains: nonCriticalPending,
    );
  }

  void _assertExpectedScope(
    ProductiveManualSyncResult result,
    CloseCashSessionInput input,
  ) {
    final scope = result.scope;
    if (scope == null ||
        scope.profileId != input.profileId ||
        scope.businessId != input.businessId ||
        scope.branchId != input.branchId) {
      throw const CashCloseSyncBlockedException(
        CashCloseSyncBlockReason.scopeMismatch,
        'No se pudo completar el cierre ahora.',
      );
    }
  }
}
