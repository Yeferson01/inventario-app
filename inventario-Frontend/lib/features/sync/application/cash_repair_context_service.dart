import '../data/models/cash_pos_recovery_models.dart';
import '../data/models/runtime_resolution_models.dart';
import '../data/models/runtime_setup_models.dart';

typedef CashRepairAuthenticatedProfileId = String? Function();
typedef CashRepairRuntimeResolver = Future<ResolvedBusinessRuntime> Function({
  required String profileId,
  required String businessId,
  required String branchId,
});
typedef CashRepairRecoveryRunner = Future<CashPosRecoveryResult> Function(
  CashPosRecoveryRequest request,
);
typedef CashRepairBlockingIssueLoader = Future<List<Map<String, dynamic>>>
    Function({
  required String profileId,
  required String businessId,
  required String branchId,
});
typedef CashRepairOpenSessionLoader = Future<List<Map<String, dynamic>>>
    Function({
  required String businessId,
  required String branchId,
  required String cashRegisterId,
});
typedef CashRepairRuntimeWriter = Future<void> Function(
  AppRuntimeContext context,
);
typedef CashRepairOriginalSessionReconciler = Future<bool> Function({
  required String profileId,
  required String businessId,
  required String branchId,
  required String cashRegisterId,
  required String originalCashSessionId,
  required String? remoteOpenCashSessionId,
  required String saleId,
});

class CashRepairContextRequest {
  const CashRepairContextRequest({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.installationId,
    required this.appDeviceId,
    required this.cashRegisterId,
    required this.originalCashSessionId,
    required this.saleId,
    required this.effectivePermissions,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String installationId;
  final String appDeviceId;
  final String cashRegisterId;
  final String originalCashSessionId;
  final String saleId;
  final Set<String> effectivePermissions;
}

class CashRepairContextResult {
  const CashRepairContextResult({
    required this.runtime,
    required this.openCashSessionId,
  });

  final ResolvedBusinessRuntime runtime;
  final String? openCashSessionId;
}

class CashRepairContextException implements Exception {
  const CashRepairContextException(this.message);

  final String message;

  @override
  String toString() => 'CashRepairContextException: $message';
}

class CashRepairContextService {
  CashRepairContextService({
    required CashRepairAuthenticatedProfileId authenticatedProfileId,
    required CashRepairRuntimeResolver resolveRuntime,
    required CashRepairRecoveryRunner recoverCash,
    required CashRepairBlockingIssueLoader loadOpenBlockingIssues,
    required CashRepairOpenSessionLoader loadOpenSessions,
    required CashRepairRuntimeWriter writeRuntimeContext,
    required CashRepairOriginalSessionReconciler reconcileOriginalSession,
  })  : _authenticatedProfileId = authenticatedProfileId,
        _resolveRuntime = resolveRuntime,
        _recoverCash = recoverCash,
        _loadOpenBlockingIssues = loadOpenBlockingIssues,
        _loadOpenSessions = loadOpenSessions,
        _writeRuntimeContext = writeRuntimeContext,
        _reconcileOriginalSession = reconcileOriginalSession;

  final CashRepairAuthenticatedProfileId _authenticatedProfileId;
  final CashRepairRuntimeResolver _resolveRuntime;
  final CashRepairRecoveryRunner _recoverCash;
  final CashRepairBlockingIssueLoader _loadOpenBlockingIssues;
  final CashRepairOpenSessionLoader _loadOpenSessions;
  final CashRepairRuntimeWriter _writeRuntimeContext;
  final CashRepairOriginalSessionReconciler _reconcileOriginalSession;

  Future<CashRepairContextResult> refresh(
    CashRepairContextRequest request,
  ) async {
    _validateRequest(request);
    if (_authenticatedProfileId() != request.profileId) {
      throw const CashRepairContextException(
        'La sesión autenticada no coincide con el contexto de reparación.',
      );
    }

    final runtime = await _resolveRuntime(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
    );
    final canonicalCashRegisterId = runtime.cashRegisterId?.trim();
    if (runtime.profileId != request.profileId ||
        runtime.businessId != request.businessId ||
        runtime.branchId != request.branchId ||
        !runtime.runtimeReady ||
        canonicalCashRegisterId == null ||
        canonicalCashRegisterId != request.cashRegisterId) {
      throw const CashRepairContextException(
        'El runtime autoritativo no coincide con la venta pendiente.',
      );
    }

    var recovery = await _recoverCash(
      CashPosRecoveryRequest(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
        appDeviceId: request.appDeviceId,
        canonicalCashRegisterId: canonicalCashRegisterId,
      ),
    );
    if (!recovery.completed ||
        recovery.canonicalCashRegisterId != canonicalCashRegisterId) {
      throw const CashRepairContextException(
        'No se pudo actualizar el estado autoritativo de caja.',
      );
    }

    var blockers = await _loadOpenBlockingIssues(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
    );
    var localOpenSessions = await _loadOpenSessions(
      businessId: request.businessId,
      branchId: request.branchId,
      cashRegisterId: canonicalCashRegisterId,
    );
    var remoteOpenCashSessionId = _string(runtime.openCashSessionId);
    if (remoteOpenCashSessionId == request.originalCashSessionId) {
      throw const CashRepairContextException(
        'La sesión original continúa abierta según el estado autoritativo.',
      );
    }
    final hasExpectedOpenConflict = remoteOpenCashSessionId != null &&
        blockers.any(
          (issue) =>
              issue['domain']?.toString() == 'cash_pos' &&
              issue['issue_type']?.toString() == 'cash_open_session_conflict' &&
              issue['entity_type']?.toString() == 'cash_sessions' &&
              issue['entity_id']?.toString() == request.originalCashSessionId,
        );
    final originalSessionStillOpen = localOpenSessions.any(
      (session) => session['id']?.toString() == request.originalCashSessionId,
    );
    if (originalSessionStillOpen) {
      if (remoteOpenCashSessionId != null && !hasExpectedOpenConflict) {
        throw const CashRepairContextException(
          'La sesión remota abierta no coincide con un conflicto local verificable.',
        );
      }
      final reconciled = await _reconcileOriginalSession(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
        cashRegisterId: canonicalCashRegisterId,
        originalCashSessionId: request.originalCashSessionId,
        remoteOpenCashSessionId: remoteOpenCashSessionId,
        saleId: request.saleId,
      );
      if (!reconciled) {
        throw const CashRepairContextException(
          'La sesión original no pudo converger de forma segura.',
        );
      }
      recovery = await _recoverCash(
        CashPosRecoveryRequest(
          profileId: request.profileId,
          businessId: request.businessId,
          branchId: request.branchId,
          appDeviceId: request.appDeviceId,
          canonicalCashRegisterId: canonicalCashRegisterId,
        ),
      );
      if (!recovery.completed ||
          recovery.canonicalCashRegisterId != canonicalCashRegisterId) {
        throw const CashRepairContextException(
          'La segunda lectura de caja no pudo confirmar la convergencia.',
        );
      }
      blockers = await _loadOpenBlockingIssues(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
      );
      localOpenSessions = await _loadOpenSessions(
        businessId: request.businessId,
        branchId: request.branchId,
        cashRegisterId: canonicalCashRegisterId,
      );
      remoteOpenCashSessionId =
          _string(recovery.openCashSessionId) ?? remoteOpenCashSessionId;
    }

    final unsafeCashBlocker = blockers.any(
      (issue) =>
          issue['domain']?.toString() == 'cash_pos' &&
          !_isCurrentStaleSaleBlocker(issue, request.saleId),
    );
    if (unsafeCashBlocker) {
      throw const CashRepairContextException(
        'Existe otro conflicto de caja que impide abrir una sesión segura.',
      );
    }

    final localOpenSessionIds = localOpenSessions
        .map((session) => _string(session['id']))
        .whereType<String>()
        .toSet();
    if (remoteOpenCashSessionId == null && localOpenSessionIds.isNotEmpty) {
      throw const CashRepairContextException(
        'Persiste una sesión local abierta sin respaldo autoritativo.',
      );
    }
    if (remoteOpenCashSessionId != null &&
        (localOpenSessionIds.length != 1 ||
            !localOpenSessionIds.contains(remoteOpenCashSessionId))) {
      throw const CashRepairContextException(
        'La sesión remota abierta no quedó materializada de forma única.',
      );
    }
    final openCashSessionId = remoteOpenCashSessionId;

    await _writeRuntimeContext(
      AppRuntimeContext(
        businessId: request.businessId,
        branchId: request.branchId,
        profileId: request.profileId,
        installationId: request.installationId,
        appDeviceId: request.appDeviceId,
        cashRegisterId: canonicalCashRegisterId,
        cashSessionId: openCashSessionId,
        receiptSequenceId: runtime.receiptSequenceId,
      ),
    );
    return CashRepairContextResult(
      runtime: runtime,
      openCashSessionId: openCashSessionId,
    );
  }

  void _validateRequest(CashRepairContextRequest request) {
    if ([
          request.profileId,
          request.businessId,
          request.branchId,
          request.installationId,
          request.appDeviceId,
          request.cashRegisterId,
          request.originalCashSessionId,
          request.saleId,
        ].any((value) => value.trim().isEmpty) ||
        !request.effectivePermissions.contains('cash.open')) {
      throw const CashRepairContextException(
        'El contexto mínimo para abrir caja no está autorizado o está incompleto.',
      );
    }
  }

  bool _isCurrentStaleSaleBlocker(
    Map<String, dynamic> issue,
    String saleId,
  ) {
    return issue['issue_type']?.toString() == 'sale_cash_session_rejected' &&
        issue['entity_type']?.toString() == 'sales' &&
        issue['entity_id']?.toString() == saleId;
  }

  String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
