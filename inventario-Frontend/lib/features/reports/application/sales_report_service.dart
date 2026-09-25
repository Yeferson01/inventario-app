import '../data/datasources/report_snapshot_local_dao.dart';
import '../data/datasources/sales_report_remote_datasource.dart';
import '../data/models/sales_report_models.dart';
import '../../sync/data/datasources/authorized_operational_context_local_dao.dart';
import '../../sync/data/models/local_recovery_models.dart';

enum SalesReportCacheReadOutcome { available, noCache, unauthorized }

class SalesReportCacheReadResult {
  const SalesReportCacheReadResult({
    required this.outcome,
    this.snapshot,
  });

  final SalesReportCacheReadOutcome outcome;
  final SalesReportSnapshot? snapshot;
}

enum SalesReportRefreshOutcome { refreshed, unauthorized, remoteFailure }

class SalesReportRefreshResult {
  const SalesReportRefreshResult({
    required this.outcome,
    this.snapshot,
    this.preservedCache,
    this.failureKind,
  });

  final SalesReportRefreshOutcome outcome;
  final SalesReportSnapshot? snapshot;
  final SalesReportSnapshot? preservedCache;
  final SalesReportRemoteFailureKind? failureKind;
}

class SalesReportService {
  SalesReportService({
    required String? Function() authenticatedProfileId,
    required AuthorizedOperationalContextLocalDao authorizationDao,
    required ReportSnapshotLocalDao snapshotDao,
    required SalesReportRemoteDatasource remoteDatasource,
    DateTime Function()? now,
  })  : _authenticatedProfileId = authenticatedProfileId,
        _authorizationDao = authorizationDao,
        _snapshotDao = snapshotDao,
        _remoteDatasource = remoteDatasource,
        _now = now ?? (() => DateTime.now().toUtc());

  final String? Function() _authenticatedProfileId;
  final AuthorizedOperationalContextLocalDao _authorizationDao;
  final ReportSnapshotLocalDao _snapshotDao;
  final SalesReportRemoteDatasource _remoteDatasource;
  final DateTime Function() _now;

  Future<SalesReportCacheReadResult> readCached(
    SalesReportScope scope,
  ) async {
    final authorization = await _authorizedContext(scope);
    if (authorization == null) {
      await _invalidateWhenCurrentProfile(scope);
      return const SalesReportCacheReadResult(
        outcome: SalesReportCacheReadOutcome.unauthorized,
      );
    }
    try {
      final snapshot = await _snapshotDao.readSalesSummary(scope);
      return SalesReportCacheReadResult(
        outcome: snapshot == null
            ? SalesReportCacheReadOutcome.noCache
            : SalesReportCacheReadOutcome.available,
        snapshot: snapshot,
      );
    } on FormatException {
      return const SalesReportCacheReadResult(
        outcome: SalesReportCacheReadOutcome.noCache,
      );
    }
  }

  Future<SalesReportRefreshResult> refresh(SalesReportScope scope) async {
    var authorization = await _authorizedContext(scope);
    if (authorization == null) {
      await _invalidateWhenCurrentProfile(scope);
      return const SalesReportRefreshResult(
        outcome: SalesReportRefreshOutcome.unauthorized,
      );
    }

    try {
      final summary = await _remoteDatasource.loadSummary(
        businessId: scope.businessId,
        branchId: scope.branchId,
        period: scope.period,
      );

      authorization = await _authorizedContext(scope);
      if (authorization == null) {
        await _invalidateWhenCurrentProfile(scope);
        return const SalesReportRefreshResult(
          outcome: SalesReportRefreshOutcome.unauthorized,
        );
      }

      final fetchedAt = _now().toUtc();
      await _snapshotDao.replaceSalesSummary(
        profileId: scope.profileId,
        summary: summary,
        fetchedAt: fetchedAt,
        authorizationValidatedAt: authorization.authorizationValidatedAt,
        capabilityFingerprint: _capabilityFingerprint(authorization),
      );
      final snapshot = await _snapshotDao.readSalesSummary(scope);
      if (snapshot == null) {
        return const SalesReportRefreshResult(
          outcome: SalesReportRefreshOutcome.remoteFailure,
          failureKind: SalesReportRemoteFailureKind.malformedResponse,
        );
      }
      return SalesReportRefreshResult(
        outcome: SalesReportRefreshOutcome.refreshed,
        snapshot: snapshot,
      );
    } on SalesReportRemoteException catch (error) {
      if (error.kind == SalesReportRemoteFailureKind.unauthorized) {
        await _snapshotDao.invalidateScope(
          profileId: scope.profileId,
          businessId: scope.businessId,
          branchId: scope.branchId,
        );
        return SalesReportRefreshResult(
          outcome: SalesReportRefreshOutcome.unauthorized,
          failureKind: error.kind,
        );
      }
      SalesReportSnapshot? preservedCache;
      try {
        preservedCache = await _snapshotDao.readSalesSummary(scope);
      } on FormatException {
        preservedCache = null;
      }
      return SalesReportRefreshResult(
        outcome: SalesReportRefreshOutcome.remoteFailure,
        preservedCache: preservedCache,
        failureKind: error.kind,
      );
    }
  }

  Future<AuthorizedOperationalContextRecord?> _authorizedContext(
    SalesReportScope scope,
  ) async {
    if (_authenticatedProfileId() != scope.profileId) return null;
    final context = await _authorizationDao.getContextRecord(
      profileId: scope.profileId,
      businessId: scope.businessId,
      branchId: scope.branchId,
    );
    if (context == null ||
        !context.isActive ||
        !context.effectivePermissions.contains(salesReportCapability)) {
      return null;
    }
    return context;
  }

  Future<void> _invalidateWhenCurrentProfile(SalesReportScope scope) async {
    if (_authenticatedProfileId() != scope.profileId) return;
    await _snapshotDao.invalidateScope(
      profileId: scope.profileId,
      businessId: scope.businessId,
      branchId: scope.branchId,
    );
  }

  String _capabilityFingerprint(
    AuthorizedOperationalContextRecord authorization,
  ) {
    final permissions = authorization.effectivePermissions.toSet().toList()
      ..sort();
    return permissions.join('\u001f');
  }
}
