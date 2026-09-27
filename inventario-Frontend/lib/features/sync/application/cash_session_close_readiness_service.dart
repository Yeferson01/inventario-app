import '../data/datasources/cash_session_close_readiness_dao.dart';
import '../data/datasources/local_sync_outbox_dao.dart';

enum CashSessionCloseReadiness { ready, blocked, indeterminate }

class CashSessionCloseReadinessResult {
  const CashSessionCloseReadinessResult({
    required this.readiness,
    required this.reason,
    required this.sessionId,
    required this.cashRegisterId,
  });

  final CashSessionCloseReadiness readiness;
  final String reason;
  final String? sessionId;
  final String? cashRegisterId;
}

typedef CashCloseEvidenceLoader = Future<CashSessionCloseEvidence> Function({
  required String profileId,
  required String businessId,
  required String branchId,
});

typedef CashCloseProvenanceRefresher = Future<void> Function({
  required String profileId,
  required String businessId,
  required String branchId,
  required String cashRegisterId,
  required String appDeviceId,
});

class CashSessionCloseReadinessService {
  CashSessionCloseReadinessService({
    required CashCloseEvidenceLoader evidenceLoader,
    required Future<BatchDependencyReadiness> Function(String)
        dependencyReadinessLoader,
    CashCloseProvenanceRefresher? provenanceRefresher,
  })  : _evidenceLoader = evidenceLoader,
        _dependencyReadinessLoader = dependencyReadinessLoader,
        _provenanceRefresher = provenanceRefresher;

  final CashCloseEvidenceLoader _evidenceLoader;
  final Future<BatchDependencyReadiness> Function(String)
      _dependencyReadinessLoader;
  final CashCloseProvenanceRefresher? _provenanceRefresher;

  Future<CashSessionCloseReadinessResult> evaluate({
    required String profileId,
    required String businessId,
    required String branchId,
    String? appDeviceId,
  }) async {
    var evidence = await _evidenceLoader(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
    );
    var session = evidence.session;
    if (session == null) {
      return const CashSessionCloseReadinessResult(
        readiness: CashSessionCloseReadiness.indeterminate,
        reason: 'open_cash_session_not_found',
        sessionId: null,
        cashRegisterId: null,
      );
    }
    final sessionId = session['id']?.toString();
    final registerId = session['cash_register_id']?.toString();
    if (sessionId == null ||
        registerId == null ||
        sessionId.isEmpty ||
        registerId.isEmpty) {
      return const CashSessionCloseReadinessResult(
        readiness: CashSessionCloseReadiness.indeterminate,
        reason: 'cash_session_scope_missing',
        sessionId: null,
        cashRegisterId: null,
      );
    }
    CashSessionCloseReadinessResult result(
      CashSessionCloseReadiness readiness,
      String reason,
    ) =>
        CashSessionCloseReadinessResult(
          readiness: readiness,
          reason: reason,
          sessionId: sessionId,
          cashRegisterId: registerId,
        );

    if (evidence.openIssues
            .any((issue) => _isUnresolvedRelevant(issue, registerId)) &&
        _provenanceRefresher != null &&
        appDeviceId != null &&
        appDeviceId.isNotEmpty) {
      try {
        await _provenanceRefresher(
          profileId: profileId,
          businessId: businessId,
          branchId: branchId,
          cashRegisterId: registerId,
          appDeviceId: appDeviceId,
        );
        evidence = await _evidenceLoader(
          profileId: profileId,
          businessId: businessId,
          branchId: branchId,
        );
        if (evidence.session?['id'] != sessionId) {
          return result(CashSessionCloseReadiness.indeterminate,
              'cash_session_changed_during_recovery');
        }
        session = evidence.session!;
      } catch (_) {
        return result(CashSessionCloseReadiness.indeterminate,
            'cash_provenance_refresh_unavailable');
      }
    }

    if (session['local_status'] != 'synced' || session['sync_status'] != 0) {
      return result(
          CashSessionCloseReadiness.indeterminate, 'cash_session_pending');
    }

    for (final issue in evidence.openIssues) {
      if (issue['severity'] != 'blocking' || !_isCloseCritical(issue)) continue;
      if (issue['scope_resolution_status'] == 'resolved_no_session') continue;
      if (issue['scope_resolution_status'] == 'resolved_session') {
        if (issue['cash_session_id'] == sessionId) {
          return result(CashSessionCloseReadiness.blocked,
              'session_reconciliation_issue');
        }
        continue;
      }
      if (_isUnresolvedRelevant(issue, registerId)) {
        return result(CashSessionCloseReadiness.indeterminate,
            'cash_issue_scope_unresolved');
      }
    }
    for (final movement in evidence.cashMovements) {
      final status = movement['local_status']?.toString();
      if (status == 'conflict' || status == 'error') {
        return result(
            CashSessionCloseReadiness.blocked, 'cash_movement_not_converged');
      }
      if (status != 'synced' || movement['sync_status'] != 0) {
        return result(
            CashSessionCloseReadiness.indeterminate, 'cash_movement_pending');
      }
    }
    for (final mutation in evidence.outboxMutations) {
      final status = mutation['status']?.toString();
      if (status == 'applied') continue;
      final batchId = mutation['batch_id']?.toString();
      if (batchId != null && batchId.isNotEmpty) {
        final dependency = await _dependencyReadinessLoader(batchId);
        if (dependency == BatchDependencyReadiness.blocked) {
          return result(CashSessionCloseReadiness.blocked,
              'cash_effect_dependency_blocked');
        }
        if (dependency == BatchDependencyReadiness.waiting) {
          return result(CashSessionCloseReadiness.indeterminate,
              'cash_effect_dependency_waiting');
        }
      }
      if (status == 'conflict' ||
          status == 'rejected' ||
          status == 'skipped' ||
          (mutation['entity_table'] == 'cash_movements' && status == 'error')) {
        return result(
            CashSessionCloseReadiness.blocked, 'session_mutation_blocked');
      }
      return result(
          CashSessionCloseReadiness.indeterminate, 'session_mutation_pending');
    }
    if (evidence.dirtyPosCount > 0) {
      return result(
          CashSessionCloseReadiness.indeterminate, 'session_pos_pending');
    }
    return result(CashSessionCloseReadiness.ready, 'session_converged');
  }

  bool _isUnresolvedRelevant(Map<String, dynamic> issue, String registerId) {
    if (issue['scope_resolution_status'] == 'resolved_session' ||
        issue['scope_resolution_status'] == 'resolved_no_session') {
      return false;
    }
    return issue['severity'] == 'blocking' &&
        _isCloseCritical(issue) &&
        issue['cash_register_id'] == registerId;
  }

  bool _isCloseCritical(Map<String, dynamic> issue) {
    if (issue['domain'] != 'cash_pos') return false;
    return const {
      'sales',
      'sale_items',
      'sale_payments',
      'cash_sessions',
      'cash_registers',
      'cash_movements',
    }.contains(issue['entity_type']);
  }
}
