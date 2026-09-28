import '../../sync/data/datasources/authorized_operational_context_local_dao.dart';
import '../../sync/data/models/local_recovery_models.dart';
import '../data/datasources/cash_flow_report_remote_datasource.dart';
import '../data/datasources/report_snapshot_local_dao.dart';
import '../data/datasources/sales_report_remote_datasource.dart';
import '../data/models/cash_flow_report_models.dart';
import '../data/models/sales_report_models.dart';

enum CashFlowCacheOutcome { available, noCache, unauthorized }

enum CashFlowRefreshOutcome { refreshed, unauthorized, remoteFailure }

class CashFlowCacheResult {
  const CashFlowCacheResult(this.outcome, [this.snapshot]);
  final CashFlowCacheOutcome outcome;
  final CashFlowReportSnapshot? snapshot;
}

class CashFlowRefreshResult {
  const CashFlowRefreshResult(
    this.outcome, {
    this.snapshot,
    this.failureKind,
  });
  final CashFlowRefreshOutcome outcome;
  final CashFlowReportSnapshot? snapshot;
  final SalesReportRemoteFailureKind? failureKind;
}

class CashFlowReportService {
  CashFlowReportService({
    required String? Function() authenticatedProfileId,
    required AuthorizedOperationalContextLocalDao authorizationDao,
    required ReportSnapshotLocalDao snapshotDao,
    required CashFlowReportRemoteDatasource remoteDatasource,
    DateTime Function()? now,
  })  : _authenticatedProfileId = authenticatedProfileId,
        _authorizationDao = authorizationDao,
        _snapshotDao = snapshotDao,
        _remoteDatasource = remoteDatasource,
        _now = now ?? (() => DateTime.now().toUtc());

  final String? Function() _authenticatedProfileId;
  final AuthorizedOperationalContextLocalDao _authorizationDao;
  final ReportSnapshotLocalDao _snapshotDao;
  final CashFlowReportRemoteDatasource _remoteDatasource;
  final DateTime Function() _now;

  Future<CashFlowCacheResult> readCached(SalesReportScope scope) async {
    if (await _authorized(scope) == null) {
      await _invalidate(scope);
      return const CashFlowCacheResult(CashFlowCacheOutcome.unauthorized);
    }
    try {
      final snapshot = await _snapshotDao.readCashFlow(scope);
      return CashFlowCacheResult(
          snapshot == null
              ? CashFlowCacheOutcome.noCache
              : CashFlowCacheOutcome.available,
          snapshot);
    } on FormatException {
      return const CashFlowCacheResult(CashFlowCacheOutcome.noCache);
    }
  }

  Future<CashFlowRefreshResult> refresh(SalesReportScope scope) async {
    if (await _authorized(scope) == null) {
      await _invalidate(scope);
      return const CashFlowRefreshResult(CashFlowRefreshOutcome.unauthorized);
    }
    try {
      final summary = await _remoteDatasource.loadSummary(
          businessId: scope.businessId,
          branchId: scope.branchId,
          period: scope.period);
      final authorization = await _authorized(scope);
      if (authorization == null) {
        await _invalidate(scope);
        return const CashFlowRefreshResult(CashFlowRefreshOutcome.unauthorized);
      }
      await _snapshotDao.replaceCashFlow(
          profileId: scope.profileId,
          summary: summary,
          fetchedAt: _now(),
          authorizationValidatedAt: authorization.authorizationValidatedAt,
          capabilityFingerprint: _fingerprint(authorization));
      final snapshot = await _snapshotDao.readCashFlow(scope);
      if (snapshot == null) {
        return const CashFlowRefreshResult(CashFlowRefreshOutcome.remoteFailure,
            failureKind: SalesReportRemoteFailureKind.malformedResponse);
      }
      return CashFlowRefreshResult(CashFlowRefreshOutcome.refreshed,
          snapshot: snapshot);
    } on SalesReportRemoteException catch (error) {
      if (error.kind == SalesReportRemoteFailureKind.unauthorized) {
        await _invalidate(scope);
        return CashFlowRefreshResult(CashFlowRefreshOutcome.unauthorized,
            failureKind: error.kind);
      }
      CashFlowReportSnapshot? preserved;
      try {
        preserved = await _snapshotDao.readCashFlow(scope);
      } on FormatException {
        preserved = null;
      }
      return CashFlowRefreshResult(CashFlowRefreshOutcome.remoteFailure,
          snapshot: preserved, failureKind: error.kind);
    }
  }

  Future<AuthorizedOperationalContextRecord?> _authorized(
      SalesReportScope scope) async {
    if (_authenticatedProfileId() != scope.profileId) return null;
    final context = await _authorizationDao.getContextRecord(
        profileId: scope.profileId,
        businessId: scope.businessId,
        branchId: scope.branchId);
    if (context?.isActive != true ||
        !context!.effectivePermissions.contains(cashFlowReportCapability)) {
      return null;
    }
    return context;
  }

  Future<void> _invalidate(SalesReportScope scope) async {
    if (_authenticatedProfileId() != scope.profileId) return;
    await _snapshotDao.invalidateCashFlowScope(
        profileId: scope.profileId,
        businessId: scope.businessId,
        branchId: scope.branchId);
  }

  String _fingerprint(AuthorizedOperationalContextRecord context) {
    final permissions = context.effectivePermissions.toSet().toList()..sort();
    return permissions.join('\u001f');
  }
}
