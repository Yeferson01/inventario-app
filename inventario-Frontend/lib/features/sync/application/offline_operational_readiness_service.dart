import '../../cash/data/datasources/cash_session_local_dao.dart';
import '../data/datasources/authorized_operational_context_local_dao.dart';
import '../data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import '../data/models/local_recovery_models.dart';
import '../data/models/runtime_setup_models.dart';
import 'app_runtime_context_store.dart';
import 'cash_pos_snapshot_applier.dart';
import 'operational_bootstrap_service.dart';

enum OfflineOperationalReadinessOutcome {
  ready,
  authorizationRevoked,
  recoveryRequired,
  invalidContext,
}

class OfflineOperationalReadinessRequest {
  const OfflineOperationalReadinessRequest({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.installationId,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String installationId;
}

class OfflineOperationalReadinessResult {
  const OfflineOperationalReadinessResult({
    required this.outcome,
    required this.reason,
    this.authorizationValidatedAt,
    this.appDeviceId,
    this.missingDatasets = const [],
    this.blockingIssueCount = 0,
  });

  final OfflineOperationalReadinessOutcome outcome;
  final String reason;
  final DateTime? authorizationValidatedAt;
  final String? appDeviceId;
  final List<String> missingDatasets;
  final int blockingIssueCount;

  bool get offlineReady => outcome == OfflineOperationalReadinessOutcome.ready;
}

class OfflineOperationalReadinessService {
  OfflineOperationalReadinessService({
    required String? Function() authenticatedProfileId,
    required AuthorizedOperationalContextLocalDao authorizationDao,
    required AppRuntimeContextStore runtimeStore,
    required OperationalBootstrapCheckpointLocalDao checkpointDao,
    required ReconciliationIssueLocalDao issueDao,
    required CashSessionLocalDao cashSessionDao,
  })  : _authenticatedProfileId = authenticatedProfileId,
        _authorizationDao = authorizationDao,
        _runtimeStore = runtimeStore,
        _checkpointDao = checkpointDao,
        _issueDao = issueDao,
        _cashSessionDao = cashSessionDao;

  final String? Function() _authenticatedProfileId;
  final AuthorizedOperationalContextLocalDao _authorizationDao;
  final AppRuntimeContextStore _runtimeStore;
  final OperationalBootstrapCheckpointLocalDao _checkpointDao;
  final ReconciliationIssueLocalDao _issueDao;
  final CashSessionLocalDao _cashSessionDao;

  Future<OfflineOperationalReadinessResult> evaluate(
    OfflineOperationalReadinessRequest request,
  ) async {
    if (_blank(request.profileId) ||
        _blank(request.businessId) ||
        _blank(request.branchId) ||
        _blank(request.installationId) ||
        _authenticatedProfileId() != request.profileId) {
      return const OfflineOperationalReadinessResult(
        outcome: OfflineOperationalReadinessOutcome.invalidContext,
        reason: 'authenticated_scope_mismatch',
      );
    }

    final authorization = await _authorizationDao.getContextRecord(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
    );
    if (authorization == null) {
      return const OfflineOperationalReadinessResult(
        outcome: OfflineOperationalReadinessOutcome.recoveryRequired,
        reason: 'authorization_projection_missing',
      );
    }
    if (!authorization.isActive) {
      return OfflineOperationalReadinessResult(
        outcome: OfflineOperationalReadinessOutcome.authorizationRevoked,
        reason: 'authorization_revoked',
        authorizationValidatedAt: authorization.authorizationValidatedAt,
      );
    }

    final runtime = await _runtimeStore.getContext(
      businessId: request.businessId,
      branchId: request.branchId,
      installationId: request.installationId,
    );
    if (!_runtimeMatches(request, runtime)) {
      return OfflineOperationalReadinessResult(
        outcome: OfflineOperationalReadinessOutcome.recoveryRequired,
        reason: 'runtime_missing_or_out_of_scope',
        authorizationValidatedAt: authorization.authorizationValidatedAt,
      );
    }

    final permissions = authorization.effectivePermissions.toSet();
    final requiresProducts = permissions.any(
      OperationalBootstrapService.productPermissions.contains,
    );
    final requiresCash = permissions.any(
      OperationalBootstrapService.cashPermissions.contains,
    );
    final appDeviceId = runtime!.appDeviceId.trim();
    if (requiresCash && _blank(runtime.cashRegisterId)) {
      return OfflineOperationalReadinessResult(
        outcome: OfflineOperationalReadinessOutcome.recoveryRequired,
        reason: 'cash_runtime_missing',
        authorizationValidatedAt: authorization.authorizationValidatedAt,
        appDeviceId: appDeviceId,
      );
    }

    final missingDatasets = <String>[];
    for (final required in _requiredDatasets(
      requiresProducts: requiresProducts,
      requiresCash: requiresCash,
    )) {
      final checkpoint = await _checkpointDao.getRecord(
        OperationalBootstrapScope(
          profileId: request.profileId,
          businessId: request.businessId,
          branchId: request.branchId,
          appDeviceId: appDeviceId,
          bundle: required.bundle,
          dataset: required.dataset,
        ),
      );
      if (checkpoint == null ||
          !checkpoint.isComplete ||
          checkpoint.convergenceStatus != 'complete') {
        missingDatasets.add('${required.bundle}/${required.dataset}');
      }
    }

    final blockingIssues = await _issueDao.getOpenBlockingIssues(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
    );
    if (missingDatasets.isNotEmpty || blockingIssues.isNotEmpty) {
      return OfflineOperationalReadinessResult(
        outcome: OfflineOperationalReadinessOutcome.recoveryRequired,
        reason: blockingIssues.isNotEmpty
            ? 'blocking_reconciliation_issues'
            : 'required_datasets_incomplete',
        authorizationValidatedAt: authorization.authorizationValidatedAt,
        appDeviceId: appDeviceId,
        missingDatasets: List.unmodifiable(missingDatasets),
        blockingIssueCount: blockingIssues.length,
      );
    }

    if (requiresCash) {
      final cashRegister = await _cashSessionDao.getCashRegisterById(
        id: runtime.cashRegisterId!.trim(),
        businessId: request.businessId,
        branchId: request.branchId,
      );
      if (cashRegister == null || cashRegister['status'] != 'active') {
        return OfflineOperationalReadinessResult(
          outcome: OfflineOperationalReadinessOutcome.recoveryRequired,
          reason: 'canonical_cash_register_not_ready',
          authorizationValidatedAt: authorization.authorizationValidatedAt,
          appDeviceId: appDeviceId,
        );
      }
    }

    return OfflineOperationalReadinessResult(
      outcome: OfflineOperationalReadinessOutcome.ready,
      reason: 'offline_ready',
      authorizationValidatedAt: authorization.authorizationValidatedAt,
      appDeviceId: appDeviceId,
    );
  }

  bool _runtimeMatches(
    OfflineOperationalReadinessRequest request,
    AppRuntimeContext? runtime,
  ) {
    return runtime != null &&
        runtime.profileId == request.profileId &&
        runtime.businessId == request.businessId &&
        runtime.branchId == request.branchId &&
        runtime.installationId == request.installationId &&
        !_blank(runtime.appDeviceId);
  }

  List<({String bundle, String dataset})> _requiredDatasets({
    required bool requiresProducts,
    required bool requiresCash,
  }) {
    return [
      (bundle: 'core', dataset: 'context'),
      if (requiresProducts)
        for (final dataset in OperationalBootstrapService.productDatasets)
          (bundle: 'product_operational', dataset: dataset),
      if (requiresCash)
        for (final dataset in CashPosSnapshotApplier.datasets)
          (bundle: 'cash_pos', dataset: dataset),
    ];
  }
}

bool _blank(String? value) => value == null || value.trim().isEmpty;
