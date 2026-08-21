import 'dart:async';
import 'dart:convert';

import '../../../core/logging/app_logger.dart';
import '../data/datasources/authorized_operational_context_local_dao.dart';
import '../data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import '../data/models/cash_pos_recovery_models.dart';
import '../data/models/inventory_balance_reconciliation_models.dart';
import '../data/models/local_recovery_models.dart';
import '../data/models/operational_bootstrap_models.dart';
import 'cash_pos_recovery_service.dart';
import 'cash_pos_snapshot_applier.dart';
import 'inventory_balance_reconciliation_service.dart';
import 'operational_bootstrap_download_models.dart';
import 'operational_bootstrap_download_service.dart';
import 'operational_bootstrap_orchestration_models.dart';

typedef AuthenticatedProfileIdResolver = FutureOr<String?> Function();
typedef OperationalBootstrapProgressListener = void Function(
  OperationalBootstrapProgress progress,
);
typedef OperationalBootstrapDownloadRunner
    = Future<OperationalBootstrapDownloadResult> Function(
  OperationalBootstrapDownloadRequest request, {
  bool restart,
});
typedef InventoryBalanceReconciliationRunner
    = Future<InventoryBalanceReconciliationResult> Function(
  InventoryBalanceReconciliationRequest request, {
  bool restart,
});
typedef CashPosRecoveryRunner = Future<CashPosRecoveryResult> Function(
  CashPosRecoveryRequest request, {
  bool restart,
});

/// Coordinates one explicit operational bootstrap/recovery request.
///
/// This is intentionally separate from scheduled incremental sync. During a
/// recovery retry, a complete core checkpoint is reused only when the exact
/// profile/business/branch/device scope still has an incomplete checkpoint.
/// Complete product datasets are then skipped, while the affected dataset or
/// bundle resumes (or restarts explicitly when its token requires it).
class OperationalBootstrapService {
  factory OperationalBootstrapService({
    required OperationalBootstrapDownloadService downloadService,
    required InventoryBalanceReconciliationService inventoryService,
    required CashPosRecoveryService cashPosRecoveryService,
    required AuthorizedOperationalContextLocalDao authorizationContextDao,
    required OperationalBootstrapCheckpointLocalDao checkpointDao,
    required ReconciliationIssueLocalDao issueDao,
    required AuthenticatedProfileIdResolver authenticatedProfileId,
    OperationalBootstrapProgressListener? onProgress,
  }) {
    return OperationalBootstrapService.withRunners(
      download: downloadService.download,
      reconcileInventory: inventoryService.reconcile,
      recoverCashPos: cashPosRecoveryService.recover,
      authorizationContextDao: authorizationContextDao,
      checkpointDao: checkpointDao,
      issueDao: issueDao,
      authenticatedProfileId: authenticatedProfileId,
      onProgress: onProgress,
    );
  }

  OperationalBootstrapService.withRunners({
    required OperationalBootstrapDownloadRunner download,
    required InventoryBalanceReconciliationRunner reconcileInventory,
    required CashPosRecoveryRunner recoverCashPos,
    required AuthorizedOperationalContextLocalDao authorizationContextDao,
    required OperationalBootstrapCheckpointLocalDao checkpointDao,
    required ReconciliationIssueLocalDao issueDao,
    required AuthenticatedProfileIdResolver authenticatedProfileId,
    OperationalBootstrapProgressListener? onProgress,
  })  : _download = download,
        _reconcileInventory = reconcileInventory,
        _recoverCashPos = recoverCashPos,
        _authorizationContextDao = authorizationContextDao,
        _checkpointDao = checkpointDao,
        _issueDao = issueDao,
        _authenticatedProfileId = authenticatedProfileId,
        _onProgress = onProgress;

  static const productPermissions = {
    'sales.create',
    'inventory.read',
    'inventory.purchase',
  };

  static const cashPermissions = {
    'cash.read',
    'cash.open',
    'cash.close',
    'sales.create',
  };

  static const productDatasets = [
    'categories',
    'products',
    'product_barcodes',
    'product_stock_balances',
  ];

  final OperationalBootstrapDownloadRunner _download;
  final InventoryBalanceReconciliationRunner _reconcileInventory;
  final CashPosRecoveryRunner _recoverCashPos;
  final AuthorizedOperationalContextLocalDao _authorizationContextDao;
  final OperationalBootstrapCheckpointLocalDao _checkpointDao;
  final ReconciliationIssueLocalDao _issueDao;
  final AuthenticatedProfileIdResolver _authenticatedProfileId;
  final OperationalBootstrapProgressListener? _onProgress;

  Future<OperationalBootstrapResult> run(
    OperationalBootstrapRequest request,
  ) async {
    final state = _OperationalBootstrapRunState(request);
    _progress(OperationalBootstrapProgressStage.validatingContext);

    final validationFailure = await _validateInput(request);
    if (validationFailure != null) {
      _progress(
        OperationalBootstrapProgressStage.error,
        message: validationFailure,
      );
      return _result(
        state,
        outcome: OperationalBootstrapOutcome.failed,
        message: validationFailure,
      );
    }

    state.resumeExistingRun =
        request.mode != OperationalBootstrapMode.refresh &&
            await _hasIncompleteCheckpoint(request);

    try {
      _progress(
        OperationalBootstrapProgressStage.core,
        bundle: 'core',
        dataset: 'context',
      );
      final reusedCore =
          state.resumeExistingRun && await _canReuseCoreCheckpoint(request);
      if (!reusedCore) {
        final core = await _downloadWithScopedRestart(
          OperationalBootstrapDownloadRequest(
            profileId: request.profileId,
            businessId: request.businessId,
            branchId: request.branchId,
            appDeviceId: request.appDeviceId,
            bundle: 'core',
            limit: request.pageLimit,
          ),
        );
        state
          ..warnings.addAll(core.warnings)
          ..recoveredCounts['core.context'] = core.rowsReceived;
      } else {
        state.warnings.add(
          'Resumed the existing recovery run from its complete core checkpoint.',
        );
      }

      final authorization = await _authorizationContextDao.getContextRecord(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
      );
      if (authorization == null || !authorization.isActive) {
        return _authorizationRevoked(
          state,
          'The selected operational context is no longer authorized.',
        );
      }
      state.authorization = authorization;

      final permissions = authorization.effectivePermissions.toSet();
      state
        ..requiresProducts = permissions.any(productPermissions.contains)
        ..requiresCash = permissions.any(cashPermissions.contains)
        ..runtimeSetupAllowed = permissions.contains('settings.business');
      state.requiredBundles
        ..add('core')
        ..addAll([
          if (state.requiresProducts) 'product_operational',
          if (state.requiresCash) 'cash_pos',
        ]);

      if (!request.runtime.runtimeReady ||
          (state.requiresCash && _blank(request.runtime.cashRegisterId))) {
        _progress(
          OperationalBootstrapProgressStage.blocked,
          message: 'Canonical runtime setup is required.',
        );
        await _loadCheckpointSummaries(state);
        return _result(
          state,
          outcome: OperationalBootstrapOutcome.runtimeSetupRequired,
          message: state.runtimeSetupAllowed
              ? 'Canonical runtime setup is required and may be requested by this context.'
              : 'Canonical runtime setup requires an authorized administrative action.',
        );
      }

      state.completedBundles.add('core');

      if (state.requiresProducts) {
        _progress(
          OperationalBootstrapProgressStage.products,
          bundle: 'product_operational',
        );
        for (final dataset in productDatasets.take(3)) {
          _progress(
            OperationalBootstrapProgressStage.products,
            bundle: 'product_operational',
            dataset: dataset,
          );
          if (state.resumeExistingRun &&
              await _isCheckpointConverged(
                request,
                bundle: 'product_operational',
                dataset: dataset,
              )) {
            continue;
          }
          final download = await _downloadWithScopedRestart(
            OperationalBootstrapDownloadRequest(
              profileId: request.profileId,
              businessId: request.businessId,
              branchId: request.branchId,
              appDeviceId: request.appDeviceId,
              bundle: 'product_operational',
              dataset: dataset,
              limit: request.pageLimit,
            ),
          );
          state
            ..warnings.addAll(download.warnings)
            ..recoveredCounts['product_operational.$dataset'] =
                download.rowsReceived;
        }

        _progress(
          OperationalBootstrapProgressStage.inventory,
          bundle: 'product_operational',
          dataset: 'product_stock_balances',
        );
        final inventoryAlreadyConverged = state.resumeExistingRun &&
            await _isCheckpointConverged(
              request,
              bundle: 'product_operational',
              dataset: 'product_stock_balances',
            );
        if (!inventoryAlreadyConverged) {
          final inventory = await _reconcileInventoryWithScopedRestart(
            InventoryBalanceReconciliationRequest(
              profileId: request.profileId,
              businessId: request.businessId,
              branchId: request.branchId,
              appDeviceId: request.appDeviceId,
              pageLimit: request.pageLimit,
            ),
          );
          state
            ..recoveredCounts['inventory.movements_checked'] =
                inventory.movementsChecked
            ..recoveredCounts['inventory.balances_reconciled'] =
                inventory.balancesReconciled;
          if (!inventory.converged || inventory.blockingIssues > 0) {
            return _blocked(
              state,
              'Inventory balance convergence is blocked.',
            );
          }
        }

        final preCashBlockers = await _loadBlockingIssues(request);
        if (preCashBlockers.isNotEmpty) {
          state.blockingIssues
            ..clear()
            ..addAll(preCashBlockers);
          return _blocked(
            state,
            'Operational reconciliation has blocking issues.',
          );
        }
        state.completedBundles.add('product_operational');
      }

      if (state.requiresCash) {
        _progress(
          OperationalBootstrapProgressStage.cash,
          bundle: 'cash_pos',
        );
        final cash = await _recoverCashWithScopedRestart(
          CashPosRecoveryRequest(
            profileId: request.profileId,
            businessId: request.businessId,
            branchId: request.branchId,
            appDeviceId: request.appDeviceId,
            canonicalCashRegisterId: request.runtime.cashRegisterId!,
            pageLimit: request.pageLimit,
          ),
        );
        state
          ..canonicalCashRegisterId = cash.canonicalCashRegisterId
          ..openCashSessionId = cash.openCashSessionId
          ..recoveredCounts['cash_pos.sales'] = cash.recoveredSalesCount;
        if (!cash.completed ||
            !cash.cashContextReady ||
            cash.blockingIssues > 0) {
          return _blocked(
            state,
            'Cash/POS recovery is blocked.',
          );
        }
        state.completedBundles.add('cash_pos');
      }

      _progress(OperationalBootstrapProgressStage.finalizing);
      state.blockingIssues.addAll(await _loadBlockingIssues(request));
      await _loadCheckpointSummaries(state);
      final checkpointsComplete = state.checkpoints.every(
        (checkpoint) =>
            checkpoint.complete && checkpoint.convergenceStatus == 'complete',
      );
      final bundlesComplete = state.requiredBundles.every(
        state.completedBundles.contains,
      );
      if (state.blockingIssues.isNotEmpty ||
          !checkpointsComplete ||
          !bundlesComplete) {
        return _blocked(
          state,
          'Operational recovery did not satisfy every offline-ready invariant.',
          reloadIssues: false,
          reloadCheckpoints: false,
        );
      }

      _progress(OperationalBootstrapProgressStage.ready);
      return _result(
        state,
        outcome: OperationalBootstrapOutcome.ready,
        offlineReady: true,
        message: 'The selected operational context is ready for offline use.',
      );
    } on OperationalBootstrapException catch (error) {
      if (error.kind == OperationalBootstrapFailureKind.unauthorized ||
          error.kind == OperationalBootstrapFailureKind.forbidden) {
        await _authorizationContextDao.invalidateContext(
          profileId: request.profileId,
          businessId: request.businessId,
          branchId: request.branchId,
        );
        return _authorizationRevoked(state, error.message);
      }
      if (error.kind == OperationalBootstrapFailureKind.networkTransient) {
        return _transient(state, error.message);
      }
      AppLogger.error('Operational bootstrap failed: ${error.kind.name}');
      _progress(
        OperationalBootstrapProgressStage.error,
        message: error.message,
      );
      await _loadCheckpointSummaries(state);
      return _result(
        state,
        outcome: OperationalBootstrapOutcome.failed,
        message: error.message,
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'Unexpected operational bootstrap failure.',
        error: error,
        stackTrace: stackTrace,
      );
      _progress(
        OperationalBootstrapProgressStage.error,
        message: 'Unexpected operational recovery failure.',
      );
      await _loadCheckpointSummaries(state);
      return _result(
        state,
        outcome: OperationalBootstrapOutcome.failed,
        message: 'Operational recovery failed unexpectedly.',
      );
    }
  }

  Future<String?> _validateInput(OperationalBootstrapRequest request) async {
    if ([
      request.profileId,
      request.businessId,
      request.branchId,
      request.installationId,
      request.appDeviceId,
    ].any(_blank)) {
      return 'Operational bootstrap requires an explicit complete scope.';
    }
    if (request.pageLimit < 1 || request.pageLimit > 1000) {
      return 'Operational bootstrap page limit must be between 1 and 1000.';
    }
    final authenticatedProfileId = await _authenticatedProfileId();
    if (authenticatedProfileId == null ||
        authenticatedProfileId != request.profileId) {
      return 'The authenticated user does not match the requested profile.';
    }
    final runtime = request.runtime;
    if (runtime.businessId != request.businessId ||
        runtime.branchId != request.branchId ||
        runtime.installationId != request.installationId ||
        runtime.appDeviceId != request.appDeviceId) {
      return 'The resolved runtime does not match the selected context.';
    }
    return null;
  }

  Future<OperationalBootstrapDownloadResult> _downloadWithScopedRestart(
    OperationalBootstrapDownloadRequest request,
  ) async {
    try {
      return await _download(request, restart: false);
    } on OperationalBootstrapException catch (error) {
      if (error.kind != OperationalBootstrapFailureKind.invalidToken) rethrow;
      return _download(request, restart: true);
    }
  }

  Future<InventoryBalanceReconciliationResult>
      _reconcileInventoryWithScopedRestart(
    InventoryBalanceReconciliationRequest request,
  ) async {
    try {
      return await _reconcileInventory(request, restart: false);
    } on OperationalBootstrapException catch (error) {
      if (error.kind != OperationalBootstrapFailureKind.invalidToken) rethrow;
      return _reconcileInventory(request, restart: true);
    }
  }

  Future<CashPosRecoveryResult> _recoverCashWithScopedRestart(
    CashPosRecoveryRequest request,
  ) async {
    try {
      return await _recoverCashPos(request, restart: false);
    } on OperationalBootstrapException catch (error) {
      if (error.kind != OperationalBootstrapFailureKind.invalidToken) rethrow;
      return _recoverCashPos(request, restart: true);
    }
  }

  Future<bool> _hasIncompleteCheckpoint(
    OperationalBootstrapRequest request,
  ) async {
    for (final bundle in const ['core', 'product_operational', 'cash_pos']) {
      final records = await _checkpointDao.listForBundle(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
        appDeviceId: request.appDeviceId,
        bundle: bundle,
      );
      if (records.any((record) => !record.isComplete)) return true;
    }
    return false;
  }

  Future<bool> _canReuseCoreCheckpoint(
    OperationalBootstrapRequest request,
  ) async {
    final record = await _checkpointDao.getRecord(
      _scope(request, bundle: 'core', dataset: 'context'),
    );
    final authorization = await _authorizationContextDao.getContextRecord(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
    );
    return record?.isComplete == true &&
        record!.convergenceStatus == 'complete' &&
        authorization?.isActive == true &&
        authorization!.snapshotId == record.snapshotId;
  }

  Future<bool> _isCheckpointConverged(
    OperationalBootstrapRequest request, {
    required String bundle,
    required String dataset,
  }) async {
    final record = await _checkpointDao.getRecord(
      _scope(request, bundle: bundle, dataset: dataset),
    );
    return record?.isComplete == true &&
        record!.convergenceStatus == 'complete';
  }

  Future<OperationalBootstrapResult> _blocked(
    _OperationalBootstrapRunState state,
    String message, {
    bool reloadIssues = true,
    bool reloadCheckpoints = true,
  }) async {
    if (reloadIssues) {
      state.blockingIssues
        ..clear()
        ..addAll(await _loadBlockingIssues(state.request));
    }
    if (reloadCheckpoints) await _loadCheckpointSummaries(state);
    _progress(
      OperationalBootstrapProgressStage.blocked,
      message: message,
    );
    return _result(
      state,
      outcome: OperationalBootstrapOutcome.recoveryBlocked,
      message: message,
    );
  }

  Future<OperationalBootstrapResult> _transient(
    _OperationalBootstrapRunState state,
    String message,
  ) async {
    final cached = await _authorizationContextDao.getContextRecord(
      profileId: state.request.profileId,
      businessId: state.request.businessId,
      branchId: state.request.branchId,
    );
    if (state.authorization == null && cached?.isActive == true) {
      state.authorization = cached;
      final permissions = cached!.effectivePermissions.toSet();
      state
        ..requiresProducts = permissions.any(productPermissions.contains)
        ..requiresCash = permissions.any(cashPermissions.contains);
      state.requiredBundles
        ..clear()
        ..add('core')
        ..addAll([
          if (state.requiresProducts) 'product_operational',
          if (state.requiresCash) 'cash_pos',
        ]);
    }
    await _loadCheckpointSummaries(state);
    final hasCachedAuthorization = state.authorization?.isActive == true;
    _progress(
      OperationalBootstrapProgressStage.error,
      message: message,
    );
    return _result(
      state,
      outcome: hasCachedAuthorization
          ? OperationalBootstrapOutcome.networkUnavailableWithCachedContext
          : OperationalBootstrapOutcome.transientFailure,
      message: hasCachedAuthorization
          ? 'Network unavailable; a previously validated context remains cached, but no TTL decision was made.'
          : 'Network unavailable and no validated cached context was found.',
    );
  }

  Future<OperationalBootstrapResult> _authorizationRevoked(
    _OperationalBootstrapRunState state,
    String message,
  ) async {
    state.authorization = await _authorizationContextDao.getContextRecord(
      profileId: state.request.profileId,
      businessId: state.request.businessId,
      branchId: state.request.branchId,
    );
    await _loadCheckpointSummaries(state);
    _progress(
      OperationalBootstrapProgressStage.blocked,
      message: message,
    );
    return _result(
      state,
      outcome: OperationalBootstrapOutcome.authorizationRevoked,
      message: message,
    );
  }

  Future<List<OperationalBootstrapBlockingIssue>> _loadBlockingIssues(
    OperationalBootstrapRequest request,
  ) async {
    final rows = await _issueDao.getOpenBlockingIssues(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
    );
    return rows.map(_issueFromRow).toList(growable: false);
  }

  OperationalBootstrapBlockingIssue _issueFromRow(
    Map<String, dynamic> row,
  ) {
    return OperationalBootstrapBlockingIssue(
      issueType: row['issue_type']?.toString() ?? 'unknown',
      domain: row['domain']?.toString() ?? 'unknown',
      entityType: _optionalString(row['entity_type']),
      entityId: _optionalString(row['entity_id']),
      message: _bounded(row['message']?.toString() ?? 'Recovery blocker.'),
      metadata: _safeMetadata(row['metadata_json']),
    );
  }

  Map<String, Object?> _safeMetadata(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final safe = <String, Object?>{};
      for (final entry in decoded.entries.take(20)) {
        final key = entry.key.toString();
        final lower = key.toLowerCase();
        if (lower.contains('token') ||
            lower.contains('secret') ||
            lower.contains('payload')) {
          continue;
        }
        final value = entry.value;
        if (value == null || value is num || value is bool) {
          safe[key] = value;
        } else if (value is String) {
          safe[key] = _bounded(value, 256);
        }
      }
      return Map.unmodifiable(safe);
    } on FormatException {
      return const {};
    }
  }

  Future<void> _loadCheckpointSummaries(
    _OperationalBootstrapRunState state,
  ) async {
    final required = <({String bundle, String dataset})>[
      (bundle: 'core', dataset: 'context'),
      if (state.requiresProducts)
        for (final dataset in productDatasets)
          (bundle: 'product_operational', dataset: dataset),
      if (state.requiresCash)
        for (final dataset in CashPosSnapshotApplier.datasets)
          (bundle: 'cash_pos', dataset: dataset),
    ];
    state.checkpoints.clear();
    for (final item in required) {
      final record = await _checkpointDao.getRecord(
        _scope(
          state.request,
          bundle: item.bundle,
          dataset: item.dataset,
        ),
      );
      state.checkpoints.add(
        record == null
            ? OperationalBootstrapCheckpointSummary.missing(
                bundle: item.bundle,
                dataset: item.dataset,
              )
            : OperationalBootstrapCheckpointSummary.fromRecord(record),
      );
    }
  }

  OperationalBootstrapScope _scope(
    OperationalBootstrapRequest request, {
    required String bundle,
    required String dataset,
  }) {
    return OperationalBootstrapScope(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
      appDeviceId: request.appDeviceId,
      bundle: bundle,
      dataset: dataset,
    );
  }

  OperationalBootstrapResult _result(
    _OperationalBootstrapRunState state, {
    required OperationalBootstrapOutcome outcome,
    required String message,
    bool offlineReady = false,
  }) {
    return OperationalBootstrapResult(
      outcome: outcome,
      profileId: state.request.profileId,
      businessId: state.request.businessId,
      branchId: state.request.branchId,
      appDeviceId: state.request.appDeviceId,
      requiredBundles: List.unmodifiable(state.requiredBundles),
      completedBundles: List.unmodifiable(state.completedBundles),
      authorizationValidatedAt: state.authorization?.authorizationValidatedAt,
      canonicalCashRegisterId:
          state.canonicalCashRegisterId ?? state.request.runtime.cashRegisterId,
      openCashSessionId:
          state.openCashSessionId ?? state.request.runtime.cashSessionId,
      blockingIssues: List.unmodifiable(state.blockingIssues),
      warnings: List.unmodifiable(state.warnings),
      recoveredCounts: Map.unmodifiable(state.recoveredCounts),
      checkpoints: List.unmodifiable(state.checkpoints),
      offlineReady: offlineReady,
      runtimeSetupAllowed: state.runtimeSetupAllowed,
      message: message,
    );
  }

  void _progress(
    OperationalBootstrapProgressStage stage, {
    String? bundle,
    String? dataset,
    String? message,
  }) {
    _onProgress?.call(
      OperationalBootstrapProgress(
        stage: stage,
        bundle: bundle,
        dataset: dataset,
        message: message,
      ),
    );
  }

  bool _blank(String? value) => value == null || value.trim().isEmpty;

  String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String _bounded(String value, [int max = 500]) {
    return value.length <= max ? value : value.substring(0, max);
  }
}

class _OperationalBootstrapRunState {
  _OperationalBootstrapRunState(this.request);

  final OperationalBootstrapRequest request;
  final List<String> requiredBundles = [];
  final List<String> completedBundles = [];
  final List<OperationalBootstrapBlockingIssue> blockingIssues = [];
  final List<String> warnings = [];
  final Map<String, int> recoveredCounts = {};
  final List<OperationalBootstrapCheckpointSummary> checkpoints = [];
  AuthorizedOperationalContextRecord? authorization;
  bool resumeExistingRun = false;
  bool requiresProducts = false;
  bool requiresCash = false;
  bool runtimeSetupAllowed = false;
  String? canonicalCashRegisterId;
  String? openCashSessionId;
}
