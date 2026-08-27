import 'dart:convert';

import '../../../core/logging/app_logger.dart';
import '../data/datasources/catalog_remote_datasource.dart';
import '../data/models/catalog_remote_models.dart';
import '../data/repositories/catalog_local_repository.dart';

class CatalogSyncService {
  CatalogSyncService({
    required CatalogRemoteDataSource remoteDataSource,
    required CatalogSyncLocalStore localRepository,
  })  : _remoteDataSource = remoteDataSource,
        _localRepository = localRepository;

  static final DateTime _catalogEpoch = DateTime.parse('1970-01-01T00:00:00Z');

  final CatalogRemoteDataSource _remoteDataSource;
  final CatalogSyncLocalStore _localRepository;
  final Map<_CatalogPullKey, Future<CatalogSyncRunResult>> _activePulls = {};
  Future<void> _pullQueue = Future<void>.value();

  Future<CatalogSyncRunResult> pullCatalogDelta({
    required String businessId,
    int pageLimit = 500,
    int maxPages = 20,
  }) {
    if (pageLimit <= 0 || maxPages <= 0) {
      throw ArgumentError('pageLimit and maxPages must be greater than zero.');
    }

    final key = _CatalogPullKey(businessId, pageLimit, maxPages);
    final active = _activePulls[key];
    if (active != null) return active;

    final run = _pullQueue.then(
      (_) => _pullCatalogDelta(
        businessId: businessId,
        pageLimit: pageLimit,
        maxPages: maxPages,
      ),
    );
    _activePulls[key] = run;
    _pullQueue = run.then<void>(
      (_) {},
      onError: (_, __) {},
    );
    run.then<void>(
      (_) => _removeActivePull(key, run),
      onError: (_, __) => _removeActivePull(key, run),
    );
    return run;
  }

  Future<CatalogSyncRunResult> _pullCatalogDelta({
    required String businessId,
    required int pageLimit,
    required int maxPages,
  }) async {
    await _localRepository.markCatalogSyncStarted(businessId);

    var pagesPulled = 0;
    var recordsReceived = 0;
    var masterProductsUpserted = 0;
    var productBarcodesUpserted = 0;
    var ignoredRecords = 0;
    var tombstonesApplied = 0;
    var staleRecordsIgnored = 0;
    var dirtyRecordsSkipped = 0;
    var resumed = false;
    var tokenRestartUsed = false;
    DateTime? committedSince;
    DateTime? windowUpperBound;
    Map<String, dynamic>? pageToken;

    try {
      final syncState = await _localRepository.getCatalogSyncState(businessId);
      committedSince = _dateTime(syncState?['last_since_updated_at']);
      pageToken = _decodePageToken(syncState?['last_page_token']);
      windowUpperBound =
          pageToken == null ? null : _dateTime(syncState?['last_server_time']);

      if (pageToken != null && !_isSignedCatalogToken(pageToken)) {
        // Legacy clients advanced the committed cursor on every page. A full
        // replay is the only safe way to retire potentially skipped state.
        await _localRepository.resetCatalogSyncResume(
          businessId: businessId,
          clearCommittedCursor: true,
        );
        committedSince = null;
        windowUpperBound = null;
        pageToken = null;
      } else if (pageToken != null && windowUpperBound == null) {
        await _localRepository.resetCatalogSyncResume(
          businessId: businessId,
          clearCommittedCursor: false,
        );
        pageToken = null;
      } else if (pageToken != null) {
        resumed = true;
      }

      var hasMore = true;

      while (hasMore && pagesPulled < maxPages) {
        CatalogPullResponse response;
        try {
          response = await _remoteDataSource.pullProductCatalogDelta(
            CatalogPullRequest(
              businessId: businessId,
              sinceUpdatedAt: committedSince,
              pageToken: pageToken,
              limit: pageLimit,
              includeDeleted: true,
            ),
          );
        } on CatalogPageTokenRejectedException {
          if (pageToken == null || tokenRestartUsed) {
            rethrow;
          }

          tokenRestartUsed = true;
          resumed = true;
          await _localRepository.resetCatalogSyncResume(
            businessId: businessId,
            clearCommittedCursor: false,
          );
          pageToken = null;
          windowUpperBound = null;
          continue;
        }

        _validateWindow(
          response: response,
          committedSince: committedSince,
          expectedUpperBound: windowUpperBound,
        );

        windowUpperBound ??= response.serverTime;
        pagesPulled++;
        recordsReceived += response.records.length;
        hasMore = response.hasMore;
        final stopsAtBudget = hasMore && pagesPulled >= maxPages;

        final applyResult = await _localRepository.applyCatalogDeltaPage(
          businessId: businessId,
          records: response.records,
          committedSince: committedSince,
          windowUpperBound: windowUpperBound,
          catalogVersion: response.catalogVersion,
          pageToken: response.nextPageToken,
          completed: response.complete,
          isSyncing: hasMore && !stopsAtBudget,
        );

        masterProductsUpserted += applyResult.masterProductsUpserted;
        productBarcodesUpserted += applyResult.productBarcodesUpserted;
        ignoredRecords += applyResult.ignoredRecords;
        tombstonesApplied += applyResult.tombstonesApplied;
        staleRecordsIgnored += applyResult.staleRecordsIgnored;
        dirtyRecordsSkipped += applyResult.dirtyRecordsSkipped;
        pageToken = response.nextPageToken;

        AppLogger.info(
          'Catalog pull page applied: page=$pagesPulled '
          'records=${response.records.length} hasMore=$hasMore',
        );
      }

      final completed = !hasMore;
      if (!completed) {
        AppLogger.warning(
          'Catalog pull paused at maxPages=$maxPages; resume state was preserved.',
        );
      }

      return CatalogSyncRunResult(
        pagesPulled: pagesPulled,
        recordsReceived: recordsReceived,
        recordsApplied: masterProductsUpserted + productBarcodesUpserted,
        masterProductsUpserted: masterProductsUpserted,
        productBarcodesUpserted: productBarcodesUpserted,
        ignoredRecords: ignoredRecords,
        tombstonesApplied: tombstonesApplied,
        staleRecordsIgnored: staleRecordsIgnored,
        dirtyRecordsSkipped: dirtyRecordsSkipped,
        status: completed
            ? CatalogSyncRunStatus.complete
            : CatalogSyncRunStatus.incomplete,
        resumed: resumed,
        committedCursorAdvanced: completed,
        nextPageTokenPresent: pageToken != null,
      );
    } catch (error, stackTrace) {
      await _localRepository.markCatalogSyncFailed(
        businessId: businessId,
        error: error,
      );

      AppLogger.error(
        'Catalog pull failed',
        error: error,
        stackTrace: stackTrace,
      );

      return CatalogSyncRunResult(
        pagesPulled: pagesPulled,
        recordsReceived: recordsReceived,
        recordsApplied: masterProductsUpserted + productBarcodesUpserted,
        masterProductsUpserted: masterProductsUpserted,
        productBarcodesUpserted: productBarcodesUpserted,
        ignoredRecords: ignoredRecords,
        tombstonesApplied: tombstonesApplied,
        staleRecordsIgnored: staleRecordsIgnored,
        dirtyRecordsSkipped: dirtyRecordsSkipped,
        status: CatalogSyncRunStatus.failed,
        resumed: resumed,
        committedCursorAdvanced: false,
        nextPageTokenPresent: pageToken != null,
        failureClassification: _failureClassification(error),
        failureMessage: error.toString(),
      );
    }
  }

  void _validateWindow({
    required CatalogPullResponse response,
    required DateTime? committedSince,
    required DateTime? expectedUpperBound,
  }) {
    final expectedSince = committedSince ?? _catalogEpoch;
    if (!_sameInstant(response.sinceUpdatedAt, expectedSince)) {
      throw const CatalogPullProtocolException(
        'Catalog pull response changed the committed window cursor.',
      );
    }

    if (expectedUpperBound != null &&
        !_sameInstant(response.serverTime, expectedUpperBound)) {
      throw const CatalogPullProtocolException(
        'Catalog pull response changed the active window upper bound.',
      );
    }
  }

  bool _sameInstant(DateTime left, DateTime right) =>
      left.toUtc().microsecondsSinceEpoch ==
      right.toUtc().microsecondsSinceEpoch;

  bool _isSignedCatalogToken(Map<String, dynamic> token) =>
      token['token_version'] == 1 &&
      token['token'] is String &&
      (token['token'] as String).isNotEmpty;

  Map<String, dynamic>? _decodePageToken(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is String && value.trim().isNotEmpty) {
      dynamic decoded;
      try {
        decoded = jsonDecode(value);
      } on FormatException {
        return const {'invalid_legacy_token': true};
      }

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }

    return const {'invalid_legacy_token': true};
  }

  DateTime? _dateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value.toUtc();
    }

    return DateTime.tryParse(value.toString())?.toUtc();
  }

  String _failureClassification(Object error) {
    if (error is CatalogPageTokenRejectedException) {
      return 'invalid_page_token';
    }
    if (error is CatalogPullProtocolException ||
        error is FormatException ||
        error is ArgumentError) {
      return 'malformed_page';
    }
    return 'transient_or_unknown';
  }

  void _removeActivePull(
    _CatalogPullKey key,
    Future<CatalogSyncRunResult> run,
  ) {
    if (identical(_activePulls[key], run)) {
      _activePulls.remove(key);
    }
  }
}

class _CatalogPullKey {
  const _CatalogPullKey(this.businessId, this.pageLimit, this.maxPages);

  final String businessId;
  final int pageLimit;
  final int maxPages;

  @override
  bool operator ==(Object other) =>
      other is _CatalogPullKey &&
      businessId == other.businessId &&
      pageLimit == other.pageLimit &&
      maxPages == other.maxPages;

  @override
  int get hashCode => Object.hash(businessId, pageLimit, maxPages);
}
