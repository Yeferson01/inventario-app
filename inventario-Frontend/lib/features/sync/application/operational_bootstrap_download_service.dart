import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../data/datasources/authorized_operational_context_local_dao.dart';
import '../data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import '../data/datasources/operational_bootstrap_remote_datasource.dart';
import '../data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import '../data/models/local_recovery_models.dart';
import '../data/models/operational_bootstrap_models.dart';
import 'operational_bootstrap_download_models.dart';
import 'operational_bootstrap_page_applier.dart';

typedef OperationalBootstrapRetryDelay = Future<void> Function(Duration delay);

class OperationalBootstrapDownloadService {
  OperationalBootstrapDownloadService({
    required AppDatabase database,
    required OperationalBootstrapRemoteDataSource remoteDataSource,
    required OperationalBootstrapCheckpointLocalDao checkpointDao,
    required OperationalBootstrapSeenRecordLocalDao seenRecordDao,
    required ReconciliationIssueLocalDao reconciliationIssueDao,
    required OperationalBootstrapPageApplier pageApplier,
    required AuthorizedOperationalContextLocalDao authorizationContextDao,
    this.maxTransientRetries = 2,
    this.retryDelay = _defaultRetryDelay,
  })  : _database = database,
        _remoteDataSource = remoteDataSource,
        _checkpointDao = checkpointDao,
        _seenRecordDao = seenRecordDao,
        _reconciliationIssueDao = reconciliationIssueDao,
        _pageApplier = pageApplier,
        _authorizationContextDao = authorizationContextDao;

  final AppDatabase _database;
  final OperationalBootstrapRemoteDataSource _remoteDataSource;
  final OperationalBootstrapCheckpointLocalDao _checkpointDao;
  final OperationalBootstrapSeenRecordLocalDao _seenRecordDao;
  final ReconciliationIssueLocalDao _reconciliationIssueDao;
  final OperationalBootstrapPageApplier _pageApplier;
  final AuthorizedOperationalContextLocalDao _authorizationContextDao;
  final int maxTransientRetries;
  final OperationalBootstrapRetryDelay retryDelay;

  Future<OperationalBootstrapDownloadResult> download(
    OperationalBootstrapDownloadRequest request, {
    bool restart = false,
  }) async {
    if (request.limit < 1 || request.limit > 1000) {
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.malformedResponse,
        message: 'Bootstrap page limit must be between 1 and 1000.',
      );
    }

    final existing = await _existingCheckpoints(request);
    final incomplete = existing.where((record) => !record.isComplete).toList();
    final hasRestartRequired =
        incomplete.any((record) => record.requiresRestart);

    if (hasRestartRequired && !restart) {
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.invalidToken,
        message: 'Bootstrap checkpoint requires an explicit restart.',
      );
    }

    if (!restart && incomplete.isNotEmpty) {
      return _resume(request, existing, incomplete);
    }

    return _startFresh(
      request,
      restarted: restart && existing.isNotEmpty,
    );
  }

  Future<List<OperationalBootstrapCheckpointRecord>> _existingCheckpoints(
    OperationalBootstrapDownloadRequest request,
  ) async {
    if (request.dataset != null) {
      final record = await _checkpointDao.getRecord(
        request.scopeFor(request.dataset!),
      );
      return record == null ? const [] : [record];
    }
    return _checkpointDao.listForBundle(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
      appDeviceId: request.appDeviceId,
      bundle: request.bundle,
    );
  }

  Future<OperationalBootstrapDownloadResult> _startFresh(
    OperationalBootstrapDownloadRequest request, {
    required bool restarted,
  }) async {
    final warnings = <String>[];
    OperationalBootstrapSnapshotPage response;
    try {
      response = await _pullWithRetry(
        OperationalBootstrapRemoteRequest(
          businessId: request.businessId,
          branchId: request.branchId,
          appDeviceId: request.appDeviceId,
          bundle: request.bundle,
          dataset: request.dataset,
          limit: request.limit,
        ),
      );
      await _validateApplicationScope(request, response);
    } on OperationalBootstrapException catch (error) {
      await _invalidateRevokedCoreContext(request, error);
      if (error.kind == OperationalBootstrapFailureKind.scopeMismatch) {
        await _recordScopeMismatch(request, error);
      }
      rethrow;
    }

    warnings.addAll(response.warnings);
    await _applyInitialResponse(request, response, warnings);

    for (final page in response.datasets.values) {
      if (page.hasMore) {
        await _continueDataset(
          request,
          scope: request.scopeFor(page.dataset),
          expectedSnapshotId: response.snapshotId,
          firstToken: page.nextPageToken!,
          warnings: warnings,
        );
      }
    }

    return _buildResult(
      request,
      snapshotId: response.snapshotId,
      resumed: false,
      restarted: restarted,
      warnings: warnings,
    );
  }

  Future<OperationalBootstrapDownloadResult> _resume(
    OperationalBootstrapDownloadRequest request,
    List<OperationalBootstrapCheckpointRecord> existing,
    List<OperationalBootstrapCheckpointRecord> incomplete,
  ) async {
    final snapshotIds = existing.map((record) => record.snapshotId).toSet();
    if (snapshotIds.length != 1) {
      for (final record in incomplete) {
        await _checkpointDao.markRestartRequired(
          record.scope,
          reason: 'Inconsistent snapshot IDs across bundle checkpoints.',
        );
      }
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.invalidToken,
        message: 'Bundle checkpoints do not share one resumable snapshot.',
      );
    }

    final snapshotId = snapshotIds.single;
    final warnings = <String>[];
    for (final record in incomplete) {
      final token = record.nextPageToken;
      if (token == null) {
        await _checkpointDao.markRestartRequired(
          record.scope,
          reason: 'Incomplete checkpoint has no continuation token.',
        );
        throw const OperationalBootstrapException(
          kind: OperationalBootstrapFailureKind.invalidToken,
          message: 'Incomplete checkpoint cannot be resumed without a token.',
        );
      }
      await _continueDataset(
        request,
        scope: record.scope,
        expectedSnapshotId: snapshotId,
        firstToken: token,
        warnings: warnings,
      );
    }

    return _buildResult(
      request,
      snapshotId: snapshotId,
      resumed: true,
      restarted: false,
      warnings: warnings,
    );
  }

  Future<void> _applyInitialResponse(
    OperationalBootstrapDownloadRequest request,
    OperationalBootstrapSnapshotPage response,
    List<String> warnings,
  ) async {
    try {
      await _database.transaction(() async {
        for (final page in response.datasets.values) {
          await _applyPageInTransaction(
            request,
            response,
            page,
            beginCheckpoint: true,
            warnings: warnings,
          );
        }
      });
    } catch (error) {
      if (error is OperationalBootstrapException) {
        rethrow;
      }
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.localPersistence,
        message: 'Could not persist the initial bootstrap page.',
        cause: error,
      );
    }
  }

  Future<void> _continueDataset(
    OperationalBootstrapDownloadRequest request, {
    required OperationalBootstrapScope scope,
    required String expectedSnapshotId,
    required String firstToken,
    required List<String> warnings,
  }) async {
    var token = firstToken;
    var hasMore = true;

    while (hasMore) {
      OperationalBootstrapSnapshotPage response;
      try {
        response = await _pullWithRetry(
          OperationalBootstrapRemoteRequest(
            businessId: request.businessId,
            branchId: request.branchId,
            appDeviceId: request.appDeviceId,
            bundle: request.bundle,
            dataset: scope.dataset,
            limit: request.limit,
            pageToken: token,
          ),
        );
        await _validateApplicationScope(
          request,
          response,
          expectedDataset: scope.dataset,
          expectedSnapshotId: expectedSnapshotId,
        );
      } on OperationalBootstrapException catch (error) {
        await _handleContinuationFailure(request, scope, error);
        rethrow;
      }

      final page = response.datasets[scope.dataset]!;
      warnings
        ..addAll(response.warnings)
        ..addAll(await _applyContinuationPage(request, response, page));
      hasMore = page.hasMore;
      if (hasMore) {
        token = page.nextPageToken!;
      }
    }
  }

  Future<List<String>> _applyContinuationPage(
    OperationalBootstrapDownloadRequest request,
    OperationalBootstrapSnapshotPage response,
    OperationalBootstrapDatasetPage page,
  ) async {
    final warnings = <String>[];
    final scope = request.scopeFor(page.dataset);
    try {
      await _database.transaction(() async {
        await _applyPageInTransaction(
          request,
          response,
          page,
          beginCheckpoint: false,
          warnings: warnings,
        );
      });
      return warnings;
    } catch (error) {
      final failure = error is OperationalBootstrapException
          ? error
          : OperationalBootstrapException(
              kind: OperationalBootstrapFailureKind.localPersistence,
              message: 'Could not apply bootstrap page atomically.',
              cause: error,
            );
      try {
        await _checkpointDao.markFailed(scope, error: failure);
      } catch (_) {
        // Preserve the original persistence failure.
      }
      throw failure;
    }
  }

  Future<void> _applyPageInTransaction(
    OperationalBootstrapDownloadRequest request,
    OperationalBootstrapSnapshotPage response,
    OperationalBootstrapDatasetPage page, {
    required bool beginCheckpoint,
    required List<String> warnings,
  }) async {
    final scope = request.scopeFor(page.dataset);
    if (beginCheckpoint) {
      await _checkpointDao.beginOrRestart(
        scope: scope,
        snapshotId: response.snapshotId,
        snapshotAt: response.snapshotAt,
        authorizationValidatedAt: response.authorizationValidatedAt,
      );
    }
    await _checkpointDao.markApplying(scope);

    final applyResult = await _pageApplier.applyPage(
      profileId: request.profileId,
      snapshot: response,
      page: page,
    );
    if (applyResult.seenEntityIds.isNotEmpty) {
      await _seenRecordDao.recordSeenBatch(
        applyResult.seenEntityIds
            .map(
              (entityId) => SeenRecordDraft(
                snapshotId: response.snapshotId,
                profileId: request.profileId,
                businessId: request.businessId,
                branchId: request.branchId,
                bundle: request.bundle,
                dataset: page.dataset,
                entityId: entityId,
              ),
            )
            .toList(growable: false),
      );
    }
    warnings.addAll(applyResult.warnings);

    await _checkpointDao.commitPageProgress(
      scope: scope,
      nextPageToken: page.nextPageToken,
      rowsReceived: page.count,
      authorizationValidatedAt: response.authorizationValidatedAt,
    );
    if (page.complete) {
      await _checkpointDao.markComplete(scope);
    }
  }

  Future<OperationalBootstrapSnapshotPage> _pullWithRetry(
    OperationalBootstrapRemoteRequest request,
  ) async {
    var retries = 0;
    while (true) {
      try {
        return await _remoteDataSource.pullPage(request);
      } on OperationalBootstrapException catch (error) {
        if (!error.retryable || retries >= maxTransientRetries) {
          rethrow;
        }
        retries += 1;
        await retryDelay(Duration(milliseconds: 200 * retries));
      }
    }
  }

  Future<void> _validateApplicationScope(
    OperationalBootstrapDownloadRequest request,
    OperationalBootstrapSnapshotPage response, {
    String? expectedDataset,
    String? expectedSnapshotId,
  }) async {
    final mismatches = <String>[];
    if (response.profileId != request.profileId) {
      mismatches.add('profile');
    }
    if (expectedSnapshotId != null &&
        response.snapshotId != expectedSnapshotId) {
      mismatches.add('snapshot');
    }
    if (expectedDataset != null &&
        (response.datasetRequested != expectedDataset ||
            !response.datasets.containsKey(expectedDataset))) {
      mismatches.add('dataset');
    }
    if (mismatches.isNotEmpty) {
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.scopeMismatch,
        message:
            'Bootstrap application scope mismatch: ${mismatches.join(', ')}.',
      );
    }
  }

  Future<void> _handleContinuationFailure(
    OperationalBootstrapDownloadRequest request,
    OperationalBootstrapScope scope,
    OperationalBootstrapException error,
  ) async {
    await _invalidateRevokedCoreContext(request, error);
    if (error.kind == OperationalBootstrapFailureKind.scopeMismatch) {
      await _recordScopeMismatch(request, error);
    }
    if (error.kind == OperationalBootstrapFailureKind.invalidToken) {
      await _checkpointDao.markRestartRequired(scope, reason: error.message);
      return;
    }
    await _checkpointDao.markFailed(scope, error: error);
  }

  Future<void> _invalidateRevokedCoreContext(
    OperationalBootstrapDownloadRequest request,
    OperationalBootstrapException error,
  ) async {
    if (request.bundle != 'core' ||
        (error.kind != OperationalBootstrapFailureKind.unauthorized &&
            error.kind != OperationalBootstrapFailureKind.forbidden)) {
      return;
    }
    await _authorizationContextDao.invalidateContext(
      profileId: request.profileId,
      businessId: request.businessId,
      branchId: request.branchId,
    );
  }

  Future<void> _recordScopeMismatch(
    OperationalBootstrapDownloadRequest request,
    OperationalBootstrapException error,
  ) {
    return _reconciliationIssueDao
        .openIssue(
          ReconciliationIssueDraft(
            profileId: request.profileId,
            businessId: request.businessId,
            branchId: request.branchId,
            domain: 'operational_bootstrap',
            issueType: 'scope_mismatch',
            severity: 'blocking',
            message: error.message,
            metadataJson: jsonEncode({
              'bundle': request.bundle,
              'dataset': request.dataset,
              'failure_kind': error.kind.name,
            }),
          ),
        )
        .then((_) {});
  }

  Future<OperationalBootstrapDownloadResult> _buildResult(
    OperationalBootstrapDownloadRequest request, {
    required String snapshotId,
    required bool resumed,
    required bool restarted,
    required List<String> warnings,
  }) async {
    final allRecords = await _existingCheckpoints(request);
    final records = allRecords
        .where((record) => record.snapshotId == snapshotId)
        .toList(growable: false);
    if (records.isEmpty) {
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.localPersistence,
        message: 'Bootstrap completed without a persisted checkpoint.',
      );
    }
    final completed = records.every((record) => record.isComplete);
    final authorizationValidatedAt = records
        .map((record) => record.authorizationValidatedAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);

    return OperationalBootstrapDownloadResult(
      snapshotId: snapshotId,
      bundle: request.bundle,
      dataset: request.dataset,
      pagesApplied: records.fold(0, (sum, record) => sum + record.pagesApplied),
      rowsReceived: records.fold(0, (sum, record) => sum + record.rowsReceived),
      completed: completed,
      resumed: resumed,
      restarted: restarted,
      authorizationValidatedAt: authorizationValidatedAt,
      checkpointStatus: completed
          ? OperationalBootstrapCheckpointStatus.complete
          : OperationalBootstrapCheckpointStatus.applying,
      warnings: List<String>.unmodifiable(warnings),
    );
  }

  static Future<void> _defaultRetryDelay(Duration delay) {
    return Future<void>.delayed(delay);
  }
}
