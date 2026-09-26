import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../../../../core/utils/app_uuid.dart';
import '../models/local_recovery_models.dart';

class ReconciliationIssueLocalDao {
  ReconciliationIssueLocalDao(this._db);

  final AppDatabase _db;

  Future<String> openIssue(ReconciliationIssueDraft issue) async {
    _validateIssue(issue);

    final id = AppUuid.v7();
    final now = DateTime.now().toUtc();
    await _db.into(_db.localReconciliationIssues).insert(
          LocalReconciliationIssuesCompanion.insert(
            id: id,
            profileId: issue.profileId,
            businessId: issue.businessId,
            branchId: issue.branchId,
            domain: issue.domain,
            entityType: Value(issue.entityType),
            entityId: Value(issue.entityId),
            saleId: Value(issue.saleId),
            cashRegisterId: Value(issue.cashRegisterId),
            cashSessionId: Value(issue.cashSessionId),
            scopeResolutionStatus:
                Value(issue.scopeResolutionStatus.storageValue),
            scopeEvidenceType: Value(issue.scopeEvidenceType),
            issueType: issue.issueType,
            severity: issue.severity,
            message: issue.message,
            metadataJson: Value(issue.metadataJson),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  Future<String> openOrUpdateIssue(ReconciliationIssueDraft issue) async {
    _validateIssue(issue);
    final existing = await _db.customSelect(
      '''
      select id, sale_id, cash_register_id, cash_session_id,
        scope_resolution_status, scope_evidence_type
      from local_reconciliation_issues
      where profile_id = ? and business_id = ? and branch_id = ?
        and domain = ? and issue_type = ? and status = 'open'
        and coalesce(entity_type, '') = ? and coalesce(entity_id, '') = ?
      limit 1
      ''',
      variables: [
        Variable<String>(issue.profileId),
        Variable<String>(issue.businessId),
        Variable<String>(issue.branchId),
        Variable<String>(issue.domain),
        Variable<String>(issue.issueType),
        Variable<String>(issue.entityType ?? ''),
        Variable<String>(issue.entityId ?? ''),
      ],
      readsFrom: {_db.localReconciliationIssues},
    ).getSingleOrNull();
    if (existing == null) {
      return openIssue(issue);
    }

    final id = existing.read<String>('id');
    final prior = existing.data;
    final priorStatus = ReconciliationScopeResolutionStatus.fromStorage(
      prior['scope_resolution_status'],
    );
    final incomingStatus = issue.scopeResolutionStatus;
    final conflict = (priorStatus !=
                ReconciliationScopeResolutionStatus.unresolved &&
            incomingStatus != ReconciliationScopeResolutionStatus.unresolved &&
            priorStatus != incomingStatus) ||
        (prior['cash_session_id'] != null &&
            issue.cashSessionId != null &&
            prior['cash_session_id'] != issue.cashSessionId) ||
        (prior['cash_register_id'] != null &&
            issue.cashRegisterId != null &&
            prior['cash_register_id'] != issue.cashRegisterId) ||
        (prior['sale_id'] != null &&
            issue.saleId != null &&
            prior['sale_id'] != issue.saleId);
    if (conflict) {
      if (issue.issueType != 'scope_provenance_conflict') {
        await openOrUpdateIssue(ReconciliationIssueDraft(
          profileId: issue.profileId,
          businessId: issue.businessId,
          branchId: issue.branchId,
          domain: issue.domain,
          entityType: issue.entityType,
          entityId: issue.entityId,
          issueType: 'scope_provenance_conflict',
          severity: 'blocking',
          message: 'Contradictory authoritative cash-session provenance.',
          metadataJson: jsonEncode({
            'prior_sale_id': prior['sale_id'],
            'incoming_sale_id': issue.saleId,
            'prior_register_id': prior['cash_register_id'],
            'incoming_register_id': issue.cashRegisterId,
            'prior_session_id': prior['cash_session_id'],
            'incoming_session_id': issue.cashSessionId,
            'prior_status': priorStatus.storageValue,
            'incoming_status': incomingStatus.storageValue,
          }),
        ));
      }
      return id;
    }

    final promote =
        priorStatus == ReconciliationScopeResolutionStatus.unresolved &&
            incomingStatus != ReconciliationScopeResolutionStatus.unresolved;
    final keepPrior =
        priorStatus != ReconciliationScopeResolutionStatus.unresolved &&
            incomingStatus == ReconciliationScopeResolutionStatus.unresolved;
    final now = DateTime.now().toUtc();
    await (_db.update(_db.localReconciliationIssues)
          ..where((row) => row.id.equals(id)))
        .write(
      LocalReconciliationIssuesCompanion(
        severity: Value(issue.severity),
        message: Value(issue.message),
        metadataJson: Value(issue.metadataJson),
        saleId: Value(keepPrior
            ? prior['sale_id'] as String?
            : issue.saleId ?? prior['sale_id'] as String?),
        cashRegisterId: Value(keepPrior
            ? prior['cash_register_id'] as String?
            : issue.cashRegisterId ?? prior['cash_register_id'] as String?),
        cashSessionId: Value(keepPrior
            ? prior['cash_session_id'] as String?
            : issue.cashSessionId ?? prior['cash_session_id'] as String?),
        scopeResolutionStatus: Value(
            promote ? incomingStatus.storageValue : priorStatus.storageValue),
        scopeEvidenceType: Value(keepPrior
            ? prior['scope_evidence_type'] as String?
            : issue.scopeEvidenceType ??
                prior['scope_evidence_type'] as String?),
        updatedAt: Value(now),
      ),
    );
    return id;
  }

  void _validateIssue(ReconciliationIssueDraft issue) {
    if (issue.severity != 'warning' && issue.severity != 'blocking') {
      throw ArgumentError('Severity de reconciliación no soportada.');
    }
    if (issue.scopeResolutionStatus ==
            ReconciliationScopeResolutionStatus.resolvedSession &&
        (issue.cashSessionId == null || issue.cashSessionId!.trim().isEmpty)) {
      throw ArgumentError('Resolved session requires cash_session_id.');
    }
    if (issue.scopeResolutionStatus ==
            ReconciliationScopeResolutionStatus.resolvedNoSession &&
        issue.cashSessionId != null) {
      throw ArgumentError(
          'Resolved no-session cannot contain cash_session_id.');
    }
  }

  Future<void> resolveIssue(String id) async {
    final now = DateTime.now().toUtc();
    await _db.customStatement(
      '''
      update local_reconciliation_issues
      set status = 'resolved', resolved_at = ?, updated_at = ?
      where id = ?
      ''',
      normalizeSqliteParameters([now, now, id]),
    );
  }

  Future<void> resolveOpenIssue({
    required String profileId,
    required String businessId,
    required String branchId,
    required String domain,
    required String issueType,
    String? entityType,
    String? entityId,
  }) async {
    final now = DateTime.now().toUtc();
    await _db.customStatement(
      '''
      update local_reconciliation_issues
      set status = 'resolved', resolved_at = ?, updated_at = ?
      where profile_id = ? and business_id = ? and branch_id = ?
        and domain = ? and issue_type = ? and status = 'open'
        and coalesce(entity_type, '') = ? and coalesce(entity_id, '') = ?
      ''',
      normalizeSqliteParameters([
        now,
        now,
        profileId,
        businessId,
        branchId,
        domain,
        issueType,
        entityType ?? '',
        entityId ?? '',
      ]),
    );
  }

  Future<List<Map<String, dynamic>>> getOpenBlockingIssues({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select *
      from local_reconciliation_issues
      where profile_id = ? and business_id = ? and branch_id = ?
        and severity = 'blocking' and status = 'open'
      order by created_at
      ''',
      variables: [
        Variable<String>(profileId),
        Variable<String>(businessId),
        Variable<String>(branchId),
      ],
      readsFrom: {_db.localReconciliationIssues},
    ).get();
    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  Future<List<Map<String, dynamic>>> getOpenIssues({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select *
      from local_reconciliation_issues
      where profile_id = ? and business_id = ? and branch_id = ?
        and status = 'open'
      order by created_at
      ''',
      variables: [
        Variable<String>(profileId),
        Variable<String>(businessId),
        Variable<String>(branchId),
      ],
      readsFrom: {_db.localReconciliationIssues},
    ).get();
    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  Future<List<Map<String, dynamic>>> getIssues({
    required String profileId,
    required String businessId,
    required String branchId,
    required String domain,
    String? entityType,
    String? entityId,
  }) async {
    final entityTypeFilter = entityType == null ? '' : 'and entity_type = ?';
    final entityIdFilter = entityId == null ? '' : 'and entity_id = ?';
    final rows = await _db.customSelect(
      '''
      select *
      from local_reconciliation_issues
      where profile_id = ? and business_id = ? and branch_id = ?
        and domain = ? $entityTypeFilter $entityIdFilter
      order by created_at
      ''',
      variables: [
        Variable<String>(profileId),
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(domain),
        if (entityType != null) Variable<String>(entityType),
        if (entityId != null) Variable<String>(entityId),
      ],
      readsFrom: {_db.localReconciliationIssues},
    ).get();
    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }
}
