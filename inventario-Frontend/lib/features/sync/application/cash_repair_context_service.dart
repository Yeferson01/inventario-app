import 'dart:convert';

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
typedef CashRepairSessionConverger = Future<void> Function({
  required String businessId,
  required String branchId,
  required String cashRegisterId,
  required String? authoritativeOpenCashSessionId,
});
typedef CashRepairSessionConflictResolver = Future<void> Function({
  required String profileId,
  required String businessId,
  required String branchId,
  required String cashSessionId,
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
    required CashRepairSessionConverger convergeCashSessions,
    required CashRepairSessionConflictResolver resolveOpenSessionConflict,
  })  : _authenticatedProfileId = authenticatedProfileId,
        _resolveRuntime = resolveRuntime,
        _recoverCash = recoverCash,
        _loadOpenBlockingIssues = loadOpenBlockingIssues,
        _loadOpenSessions = loadOpenSessions,
        _writeRuntimeContext = writeRuntimeContext,
        _convergeCashSessions = convergeCashSessions,
        _resolveOpenSessionConflict = resolveOpenSessionConflict;

  final CashRepairAuthenticatedProfileId _authenticatedProfileId;
  final CashRepairRuntimeResolver _resolveRuntime;
  final CashRepairRecoveryRunner _recoverCash;
  final CashRepairBlockingIssueLoader _loadOpenBlockingIssues;
  final CashRepairOpenSessionLoader _loadOpenSessions;
  final CashRepairRuntimeWriter _writeRuntimeContext;
  final CashRepairSessionConverger _convergeCashSessions;
  final CashRepairSessionConflictResolver _resolveOpenSessionConflict;

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

    final remoteOpenCashSessionId = _string(runtime.openCashSessionId);
    if (remoteOpenCashSessionId == request.originalCashSessionId) {
      throw const CashRepairContextException(
        'La sesión original continúa abierta según el estado autoritativo.',
      );
    }
    await _convergeCashSessions(
      businessId: request.businessId,
      branchId: request.branchId,
      cashRegisterId: canonicalCashRegisterId,
      authoritativeOpenCashSessionId: remoteOpenCashSessionId,
    );
    await _resolveOpenSessionConflict(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
      cashSessionId: request.originalCashSessionId,
    );

    final recovery = await _recoverCash(
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

    final blockers = await _loadOpenBlockingIssues(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
    );
    final localOpenSessions = await _loadOpenSessions(
      businessId: request.businessId,
      branchId: request.branchId,
      cashRegisterId: canonicalCashRegisterId,
    );
    final unsafeCashBlocker = blockers.any(
      (issue) =>
          issue['domain']?.toString() == 'cash_pos' &&
          !_isCompatibleStaleSaleBlocker(issue, request),
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
    if (_string(recovery.openCashSessionId) != remoteOpenCashSessionId) {
      throw const CashRepairContextException(
        'Recovery no confirmó la sesión abierta del runtime autoritativo.',
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

  bool _isCompatibleStaleSaleBlocker(
    Map<String, dynamic> issue,
    CashRepairContextRequest request,
  ) {
    if (issue['issue_type']?.toString() != 'sale_cash_session_rejected' ||
        issue['entity_type']?.toString() != 'sales') {
      return false;
    }
    if (issue['entity_id']?.toString() == request.saleId) return true;

    final rawMetadata = issue['metadata_json'];
    Map<String, dynamic>? metadata;
    if (rawMetadata is Map) {
      metadata = rawMetadata.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    } else if (rawMetadata is String) {
      try {
        final decoded = jsonDecode(rawMetadata);
        if (decoded is Map) {
          metadata = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      } on FormatException {
        return false;
      }
    }
    return metadata?['cash_session_id']?.toString() ==
            request.originalCashSessionId &&
        metadata?['cash_register_id']?.toString() == request.cashRegisterId &&
        metadata?['branch_id']?.toString() == request.branchId &&
        metadata?['remote_rule']?.toString() == 'sale_cash_session_invalid' &&
        metadata?['remote_reason']?.toString() == 'closed';
  }

  String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}
