import '../../sync/data/datasources/authorized_operational_context_local_dao.dart';
import '../../sync/data/models/local_recovery_models.dart';
import '../data/datasources/profitability_report_remote_datasource.dart';
import '../data/datasources/report_snapshot_local_dao.dart';
import '../data/models/profitability_report_models.dart';
import '../data/models/sales_report_models.dart';

enum ProfitabilityCacheReadOutcome { available, noCache, unauthorized }

class ProfitabilityCacheReadResult {
  const ProfitabilityCacheReadResult({required this.outcome, this.snapshot});

  final ProfitabilityCacheReadOutcome outcome;
  final ProfitabilityReportSnapshot? snapshot;
}

enum ProfitabilityRefreshOutcome { refreshed, unauthorized, remoteFailure }

class ProfitabilityRefreshResult {
  const ProfitabilityRefreshResult({
    required this.outcome,
    this.snapshot,
    this.preservedCache,
    this.failureKind,
  });

  final ProfitabilityRefreshOutcome outcome;
  final ProfitabilityReportSnapshot? snapshot;
  final ProfitabilityReportSnapshot? preservedCache;
  final ProfitabilityReportRemoteFailureKind? failureKind;
}

class ProfitabilityReportService {
  ProfitabilityReportService({
    required String? Function() authenticatedProfileId,
    required AuthorizedOperationalContextLocalDao authorizationDao,
    required ReportSnapshotLocalDao snapshotDao,
    required ProfitabilityReportRemoteDatasource remoteDatasource,
    DateTime Function()? now,
  })  : _authenticatedProfileId = authenticatedProfileId,
        _authorizationDao = authorizationDao,
        _snapshotDao = snapshotDao,
        _remoteDatasource = remoteDatasource,
        _now = now ?? (() => DateTime.now().toUtc());

  final String? Function() _authenticatedProfileId;
  final AuthorizedOperationalContextLocalDao _authorizationDao;
  final ReportSnapshotLocalDao _snapshotDao;
  final ProfitabilityReportRemoteDatasource _remoteDatasource;
  final DateTime Function() _now;

  Future<ProfitabilityCacheReadResult> readCached(
      SalesReportScope scope) async {
    if (await _authorizedContext(scope) == null) {
      await _invalidateWhenCurrentProfile(scope);
      return const ProfitabilityCacheReadResult(
        outcome: ProfitabilityCacheReadOutcome.unauthorized,
      );
    }
    try {
      final snapshot = await _snapshotDao.readProfitability(scope);
      return ProfitabilityCacheReadResult(
        outcome: snapshot == null
            ? ProfitabilityCacheReadOutcome.noCache
            : ProfitabilityCacheReadOutcome.available,
        snapshot: snapshot,
      );
    } on FormatException {
      return const ProfitabilityCacheReadResult(
        outcome: ProfitabilityCacheReadOutcome.noCache,
      );
    }
  }

  Future<ProfitabilityRefreshResult> refresh(SalesReportScope scope) async {
    var authorization = await _authorizedContext(scope);
    if (authorization == null) {
      await _invalidateWhenCurrentProfile(scope);
      return const ProfitabilityRefreshResult(
        outcome: ProfitabilityRefreshOutcome.unauthorized,
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
        return const ProfitabilityRefreshResult(
          outcome: ProfitabilityRefreshOutcome.unauthorized,
        );
      }
      await _snapshotDao.replaceProfitability(
        profileId: scope.profileId,
        summary: summary,
        fetchedAt: _now().toUtc(),
        authorizationValidatedAt: authorization.authorizationValidatedAt,
        capabilityFingerprint: _capabilityFingerprint(authorization),
      );
      final snapshot = await _snapshotDao.readProfitability(scope);
      if (snapshot == null) {
        return const ProfitabilityRefreshResult(
          outcome: ProfitabilityRefreshOutcome.remoteFailure,
          failureKind: ProfitabilityReportRemoteFailureKind.malformedResponse,
        );
      }
      return ProfitabilityRefreshResult(
        outcome: ProfitabilityRefreshOutcome.refreshed,
        snapshot: snapshot,
      );
    } on ProfitabilityReportRemoteException catch (error) {
      if (error.kind == ProfitabilityReportRemoteFailureKind.unauthorized) {
        await _snapshotDao.invalidateProfitabilityScope(
          profileId: scope.profileId,
          businessId: scope.businessId,
          branchId: scope.branchId,
        );
        return ProfitabilityRefreshResult(
          outcome: ProfitabilityRefreshOutcome.unauthorized,
          failureKind: error.kind,
        );
      }
      if (await _authorizedContext(scope) == null) {
        await _invalidateWhenCurrentProfile(scope);
        return ProfitabilityRefreshResult(
          outcome: ProfitabilityRefreshOutcome.unauthorized,
          failureKind: error.kind,
        );
      }
      ProfitabilityReportSnapshot? preservedCache;
      try {
        preservedCache = await _snapshotDao.readProfitability(scope);
      } on FormatException {
        preservedCache = null;
      }
      return ProfitabilityRefreshResult(
        outcome: ProfitabilityRefreshOutcome.remoteFailure,
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
        !context.effectivePermissions.contains(salesReportCapability) ||
        !context.effectivePermissions.contains(profitabilityCostCapability)) {
      return null;
    }
    return context;
  }

  Future<void> _invalidateWhenCurrentProfile(SalesReportScope scope) async {
    if (_authenticatedProfileId() != scope.profileId) return;
    await _snapshotDao.invalidateProfitabilityScope(
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
