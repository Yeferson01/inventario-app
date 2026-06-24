import 'dart:convert';

import '../../../core/logging/app_logger.dart';
import '../data/datasources/catalog_remote_datasource.dart';
import '../data/models/catalog_remote_models.dart';
import '../data/repositories/catalog_local_repository.dart';

class CatalogSyncService {
  CatalogSyncService({
    required CatalogRemoteDataSource remoteDataSource,
    required CatalogLocalRepository localRepository,
  })  : _remoteDataSource = remoteDataSource,
        _localRepository = localRepository;

  final CatalogRemoteDataSource _remoteDataSource;
  final CatalogLocalRepository _localRepository;

  Future<CatalogSyncRunResult> pullCatalogDelta({
    required String businessId,
    int pageLimit = 500,
    int maxPages = 20,
  }) async {
    await _localRepository.markCatalogSyncStarted(businessId);

    var pagesPulled = 0;
    var recordsReceived = 0;
    var masterProductsUpserted = 0;
    var productBarcodesUpserted = 0;
    var ignoredRecords = 0;

    try {
      final syncState = await _localRepository.getCatalogSyncState(businessId);

      DateTime? sinceUpdatedAt;

      Map<String, dynamic>? pageToken;

      if (syncState != null) {
        sinceUpdatedAt = _dateTime(
          syncState['last_since_updated_at'] ??
              syncState['last_server_time'] ??
              syncState['last_catalog_pull_at'],
        );

        pageToken = _decodePageToken(syncState['last_page_token']);
      }

      var hasMore = true;

      while (hasMore && pagesPulled < maxPages) {
        final request = CatalogPullRequest(
          businessId: businessId,
          sinceUpdatedAt: sinceUpdatedAt,
          pageToken: pageToken,
          limit: pageLimit,
          includeDeleted: false,
        );

        final response =
            await _remoteDataSource.pullProductCatalogDelta(request);
        pagesPulled++;
        recordsReceived += response.records.length;

        final applyResult =
            await _localRepository.applyCatalogDeltaResponse(response.raw);

        masterProductsUpserted += applyResult.masterProductsUpserted;
        productBarcodesUpserted += applyResult.productBarcodesUpserted;
        ignoredRecords += applyResult.ignoredRecords;

        await _localRepository.saveCatalogSyncSuccess(
          businessId: businessId,
          serverTime: response.serverTime,
          catalogVersion: response.catalogVersion,
          pageToken: response.nextPageToken,
        );

        pageToken = response.nextPageToken;
        hasMore = response.hasMore && pageToken != null;

        AppLogger.info(
          'Catalog pull page applied: page=$pagesPulled '
          'records=${response.records.length} hasMore=$hasMore',
        );
      }

      final completed = !hasMore;

      if (!completed) {
        AppLogger.warning(
          'Catalog pull stopped before completion because maxPages=$maxPages was reached.',
        );
      }

      return CatalogSyncRunResult(
        pagesPulled: pagesPulled,
        recordsReceived: recordsReceived,
        recordsApplied: masterProductsUpserted + productBarcodesUpserted,
        masterProductsUpserted: masterProductsUpserted,
        productBarcodesUpserted: productBarcodesUpserted,
        ignoredRecords: ignoredRecords,
        completed: completed,
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

      rethrow;
    }
  }

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
      final decoded = jsonDecode(value);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }

    return null;
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
}
