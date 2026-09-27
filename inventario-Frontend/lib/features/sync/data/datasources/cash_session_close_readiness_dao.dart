import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../cash/data/datasources/cash_session_local_dao.dart';
import 'reconciliation_issue_local_dao.dart';

class CashSessionCloseEvidence {
  const CashSessionCloseEvidence({
    required this.session,
    required this.cashMovements,
    required this.outboxMutations,
    required this.dirtyPosCount,
    required this.openIssues,
  });

  final Map<String, dynamic>? session;
  final List<Map<String, dynamic>> cashMovements;
  final List<Map<String, dynamic>> outboxMutations;
  final int dirtyPosCount;
  final List<Map<String, dynamic>> openIssues;
}

class CashSessionCloseReadinessDao {
  CashSessionCloseReadinessDao({
    required AppDatabase database,
    required CashSessionLocalDao cashSessionDao,
    required ReconciliationIssueLocalDao issueDao,
  })  : _db = database,
        _cashSessionDao = cashSessionDao,
        _issueDao = issueDao;

  final AppDatabase _db;
  final CashSessionLocalDao _cashSessionDao;
  final ReconciliationIssueLocalDao _issueDao;

  Future<CashSessionCloseEvidence> load({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async {
    final session = await _cashSessionDao.getOpenCashSessionForBranch(
      businessId: businessId,
      branchId: branchId,
    );
    if (session == null) {
      return const CashSessionCloseEvidence(
        session: null,
        cashMovements: [],
        outboxMutations: [],
        dirtyPosCount: 0,
        openIssues: [],
      );
    }
    final sessionId = session['id'] as String;
    final movements = await _db.customSelect('''
      select id, local_status, sync_status from local_cash_movements
      where business_id = ? and branch_id = ? and cash_session_id = ?
    ''', variables: [
      Variable<String>(businessId),
      Variable<String>(branchId),
      Variable<String>(sessionId),
    ]).get();
    final mutations = await _db.customSelect('''
      select m.id, m.entity_table, m.entity_id, m.status, m.error_code,
             m.local_sync_batch_id as batch_id
      from local_sync_mutations m
      where m.business_id = ? and m.branch_id = ?
        and (
          (m.entity_table = 'cash_sessions' and m.entity_id = ?)
          or (m.entity_table = 'cash_movements' and m.entity_id in (
            select cm.id from local_cash_movements cm
            where cm.cash_session_id = ?
          ))
          or (m.entity_table = 'sales' and m.entity_id in (
            select s.id from sales s where s.cash_session_id = ?
          ))
          or (m.entity_table = 'sale_items' and m.entity_id in (
            select si.id from sale_items si join sales s on s.id = si.sale_id
            where s.cash_session_id = ?
          ))
          or (m.entity_table = 'sale_payments' and m.entity_id in (
            select sp.id from sale_payments sp join sales s on s.id = sp.sale_id
            where s.cash_session_id = ?
          ))
        )
    ''', variables: [
      Variable<String>(businessId),
      Variable<String>(branchId),
      ...List.generate(5, (_) => Variable<String>(sessionId)),
    ]).get();
    final dirty = await _db.customSelect('''
      select
        (select count(*) from sales s
         where s.cash_session_id = ? and s.deleted_at is null
           and (s.local_status <> 'synced' or s.sync_status <> 0)) +
        (select count(*) from sale_items si join sales s on s.id = si.sale_id
         where s.cash_session_id = ? and si.deleted_at is null
           and si.sync_status <> 0) +
        (select count(*) from sale_payments sp join sales s on s.id = sp.sale_id
         where s.cash_session_id = ? and sp.deleted_at is null
           and (sp.local_status <> 'synced' or sp.sync_status <> 0))
        as dirty_count
    ''', variables: [
      Variable<String>(sessionId),
      Variable<String>(sessionId),
      Variable<String>(sessionId),
    ]).getSingle();
    final issues = await _issueDao.getOpenIssues(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
    );
    return CashSessionCloseEvidence(
      session: session,
      cashMovements: movements
          .map((row) => Map<String, dynamic>.from(row.data))
          .toList(growable: false),
      outboxMutations: mutations
          .map((row) => Map<String, dynamic>.from(row.data))
          .toList(growable: false),
      dirtyPosCount: dirty.read<int>('dirty_count'),
      openIssues: issues,
    );
  }
}
