class CatalogPullRequest {
  const CatalogPullRequest({
    required this.businessId,
    this.sinceUpdatedAt,
    this.pageToken,
    this.limit = 1000,
    this.includeDeleted = false,
  });

  final String businessId;
  final DateTime? sinceUpdatedAt;
  final Map<String, dynamic>? pageToken;
  final int limit;
  final bool includeDeleted;

  Map<String, dynamic> toRpcParams() {
    return {
      'p_business_id': businessId,
      'p_since_updated_at': sinceUpdatedAt?.toUtc().toIso8601String(),
      'p_limit': limit,
      'p_page_token': pageToken ?? <String, dynamic>{},
      'p_include_deleted': includeDeleted,
    };
  }
}

class CatalogPullResponse {
  const CatalogPullResponse({
    required this.records,
    required this.serverTime,
    required this.sinceUpdatedAt,
    required this.catalogVersion,
    required this.nextPageToken,
    required this.hasMore,
    required this.complete,
    required this.raw,
  });

  final List<Map<String, dynamic>> records;
  final DateTime serverTime;
  final DateTime sinceUpdatedAt;
  final int? catalogVersion;
  final Map<String, dynamic>? nextPageToken;
  final bool hasMore;
  final bool complete;
  final Map<String, dynamic> raw;

  factory CatalogPullResponse.fromRpc(dynamic value) {
    if (value is! Map) {
      throw const CatalogPullProtocolException(
        'Catalog pull response must be a JSON object.',
      );
    }

    final map = Map<String, dynamic>.from(value);

    final records = <Map<String, dynamic>>[];
    final rawRecords = map['records'] ?? map['data'] ?? map['items'] ?? [];

    if (rawRecords is! List) {
      throw const CatalogPullProtocolException(
        'Catalog pull records must be a JSON array.',
      );
    }

    for (final item in rawRecords) {
      if (item is Map<String, dynamic>) {
        records.add(item);
      } else if (item is Map) {
        records.add(Map<String, dynamic>.from(item));
      } else {
        throw const CatalogPullProtocolException(
          'Catalog pull contains a malformed record.',
        );
      }
    }

    final serverTime = _dateTime(
      map['window_upper_bound'] ??
          map['windowUpperBound'] ??
          map['server_time'] ??
          map['serverTime'],
    );
    final sinceUpdatedAt = _dateTime(
      map['since_updated_at'] ?? map['sinceUpdatedAt'],
    );

    if (serverTime == null || sinceUpdatedAt == null) {
      throw const CatalogPullProtocolException(
        'Catalog pull response is missing its window bounds.',
      );
    }

    final catalogVersion = _int(
      map['current_catalog_version'] ??
          map['catalog_version'] ??
          map['catalogVersion'] ??
          map['last_catalog_version'],
    );

    final nextPageToken = _nullableMap(
      map['next_page_token'] ??
          map['nextPageToken'] ??
          map['page_token'] ??
          map['pageToken'],
    );

    final hasMore = _bool(map['has_more'] ?? map['hasMore'] ?? map['more']);

    if (hasMore == null) {
      throw const CatalogPullProtocolException(
        'Catalog pull response is missing has_more.',
      );
    }

    if (hasMore && nextPageToken == null) {
      throw const CatalogPullProtocolException(
        'Catalog pull response has more rows but no continuation token.',
      );
    }

    if (!hasMore && nextPageToken != null) {
      throw const CatalogPullProtocolException(
        'Catalog pull response is complete but still has a continuation token.',
      );
    }

    final complete = _bool(map['complete']) ?? !hasMore;

    if (complete == hasMore) {
      throw const CatalogPullProtocolException(
        'Catalog pull response has inconsistent completion metadata.',
      );
    }

    return CatalogPullResponse(
      records: records,
      serverTime: serverTime,
      sinceUpdatedAt: sinceUpdatedAt,
      catalogVersion: catalogVersion,
      nextPageToken: nextPageToken,
      hasMore: hasMore,
      complete: complete,
      raw: map,
    );
  }

  static Map<String, dynamic>? _nullableMap(dynamic value) {
    if (value == null) {
      return null;
    }

    Map<String, dynamic>? map;

    if (value is Map<String, dynamic>) {
      map = value;
    } else if (value is Map) {
      map = Map<String, dynamic>.from(value);
    }

    if (map == null || map.isEmpty) {
      return null;
    }

    return map;
  }

  static DateTime? _dateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value.toUtc();
    }

    return DateTime.tryParse(value.toString())?.toUtc();
  }

  static int? _int(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString());
  }

  static bool? _bool(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is bool) {
      return value;
    }

    if (value is int) {
      return value != 0;
    }

    final text = value.toString().trim().toLowerCase();

    if (text == 'true' || text == '1' || text == 'yes') {
      return true;
    }

    if (text == 'false' || text == '0' || text == 'no') {
      return false;
    }

    return null;
  }
}

class CatalogPullProtocolException implements Exception {
  const CatalogPullProtocolException(this.message);

  final String message;

  @override
  String toString() => 'CatalogPullProtocolException: $message';
}

enum CatalogSyncRunStatus {
  complete,
  incomplete,
  failed,
}

class CatalogSyncRunResult {
  const CatalogSyncRunResult({
    required this.pagesPulled,
    required this.recordsReceived,
    required this.recordsApplied,
    required this.masterProductsUpserted,
    required this.productBarcodesUpserted,
    required this.ignoredRecords,
    required this.status,
    required this.resumed,
    required this.committedCursorAdvanced,
    required this.nextPageTokenPresent,
    this.tombstonesApplied = 0,
    this.staleRecordsIgnored = 0,
    this.dirtyRecordsSkipped = 0,
    this.failureClassification,
    this.failureMessage,
  });

  final int pagesPulled;
  final int recordsReceived;
  final int recordsApplied;
  final int masterProductsUpserted;
  final int productBarcodesUpserted;
  final int ignoredRecords;
  final int tombstonesApplied;
  final int staleRecordsIgnored;
  final int dirtyRecordsSkipped;
  final CatalogSyncRunStatus status;
  final bool resumed;
  final bool committedCursorAdvanced;
  final bool nextPageTokenPresent;
  final String? failureClassification;
  final String? failureMessage;

  bool get completed => status == CatalogSyncRunStatus.complete;

  Map<String, dynamic> toJson() {
    return {
      'pages_pulled': pagesPulled,
      'records_received': recordsReceived,
      'records_applied': recordsApplied,
      'master_products_upserted': masterProductsUpserted,
      'product_barcodes_upserted': productBarcodesUpserted,
      'ignored_records': ignoredRecords,
      'tombstones_applied': tombstonesApplied,
      'stale_records_ignored': staleRecordsIgnored,
      'dirty_records_skipped': dirtyRecordsSkipped,
      'status': status.name,
      'completed': completed,
      'resumed': resumed,
      'committed_cursor_advanced': committedCursorAdvanced,
      'next_page_token_present': nextPageTokenPresent,
      'failure_classification': failureClassification,
      'failure_message': failureMessage,
    };
  }
}
