import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../../../../core/utils/app_uuid.dart';
import '../models/local_recovery_models.dart';

class ReconciliationIssueLocalDao {
  ReconciliationIssueLocalDao(this._db);

  final AppDatabase _db;

  Future<String> openIssue(ReconciliationIssueDraft issue) async {
    if (issue.severity != 'warning' && issue.severity != 'blocking') {
      throw ArgumentError('Severity de reconciliación no soportada.');
    }

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
    if (issue.severity != 'warning' && issue.severity != 'blocking') {
      throw ArgumentError('Severity de reconciliación no soportada.');
    }
    final existing = await _db.customSelect(
      '''
      select id
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
    final now = DateTime.now().toUtc();
    await (_db.update(_db.localReconciliationIssues)
          ..where((row) => row.id.equals(id)))
        .write(
      LocalReconciliationIssuesCompanion(
        severity: Value(issue.severity),
        message: Value(issue.message),
        metadataJson: Value(issue.metadataJson),
        updatedAt: Value(now),
      ),
    );
    return id;
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
