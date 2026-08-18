import '../../cash/data/datasources/cash_session_local_dao.dart';
import '../data/datasources/cash_pos_reconciliation_local_dao.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import '../data/models/cash_pos_recovery_models.dart';
import '../data/models/local_recovery_models.dart';
import 'operational_bootstrap_download_models.dart';
import 'operational_bootstrap_download_service.dart';

class CashPosRecoveryService {
  CashPosRecoveryService({
    required OperationalBootstrapDownloadService downloadService,
    required CashPosReconciliationLocalDao reconciliationDao,
    required CashSessionLocalDao cashSessionDao,
    required ReconciliationIssueLocalDao issueDao,
  })  : _downloadService = downloadService,
        _reconciliationDao = reconciliationDao,
        _cashSessionDao = cashSessionDao,
        _issueDao = issueDao;

  final OperationalBootstrapDownloadService _downloadService;
  final CashPosReconciliationLocalDao _reconciliationDao;
  final CashSessionLocalDao _cashSessionDao;
  final ReconciliationIssueLocalDao _issueDao;

  Future<CashPosRecoveryResult> recover(
    CashPosRecoveryRequest request, {
    bool restart = false,
  }) async {
    final download = await _downloadService.download(
      OperationalBootstrapDownloadRequest(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
        appDeviceId: request.appDeviceId,
        bundle: 'cash_pos',
        limit: request.pageLimit,
      ),
      restart: restart,
    );

    final canonical = await _cashSessionDao.getCashRegisterById(
      id: request.canonicalCashRegisterId,
      businessId: request.businessId,
      branchId: request.branchId,
    );
    if (canonical == null || canonical['status'] != 'active') {
      await _issueDao.openOrUpdateIssue(
        ReconciliationIssueDraft(
          profileId: request.profileId,
          businessId: request.businessId,
          branchId: request.branchId,
          domain: 'cash_pos',
          entityType: 'cash_registers',
          entityId: request.canonicalCashRegisterId,
          issueType: 'runtime_missing',
          severity: 'blocking',
          message:
              'Canonical runtime cash register is missing, inactive, or outside the selected scope.',
        ),
      );
    } else {
      await _issueDao.resolveOpenIssue(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
        domain: 'cash_pos',
        issueType: 'runtime_missing',
        entityType: 'cash_registers',
        entityId: request.canonicalCashRegisterId,
      );
    }

    final openSession = canonical == null
        ? null
        : await _cashSessionDao.getOpenCashSessionForRegister(
            businessId: request.businessId,
            branchId: request.branchId,
            cashRegisterId: request.canonicalCashRegisterId,
          );
    final issues = await _issueDao.getIssues(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
      domain: 'cash_pos',
    );
    final blockers = issues
        .where(
          (issue) =>
              issue['status'] == 'open' && issue['severity'] == 'blocking',
        )
        .length;
    final sales = openSession == null
        ? 0
        : await _reconciliationDao.countSalesForSession(
            openSession['id'].toString(),
          );
    final ready = download.completed && canonical != null && blockers == 0;

    return CashPosRecoveryResult(
      snapshotId: download.snapshotId,
      cashContextReady: ready,
      canonicalCashRegisterId: request.canonicalCashRegisterId,
      openCashSessionId: openSession?['id']?.toString(),
      recoveredSalesCount: sales,
      blockingIssues: blockers,
      completed: download.completed,
    );
  }
}
