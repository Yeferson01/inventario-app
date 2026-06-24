class CatalogPullRequest {
  const CatalogPullRequest({
    required this.businessId,
    this.sinceUpdatedAt,
    this.sinceCatalogVersion,
    this.pageToken,
    this.limit = 500,
  });

  final String businessId;
  final DateTime? sinceUpdatedAt;
  final int? sinceCatalogVersion;
  final Map<String, dynamic>? pageToken;
  final int limit;

  Map<String, dynamic> toRpcParams() {
    return {
      'p_business_id': businessId,
      'p_since_updated_at': sinceUpdatedAt?.toUtc().toIso8601String(),
      'p_since_catalog_version': sinceCatalogVersion,
      'p_page_token': pageToken,
      'p_limit': limit,
    };
  }
}

class CatalogPullResponse {
  const CatalogPullResponse({
    required this.records,
    required this.serverTime,
    required this.catalogVersion,
    required this.nextPageToken,
    required this.hasMore,
    required this.raw,
  });

  final List<Map<String, dynamic>> records;
  final DateTime serverTime;
  final int? catalogVersion;
  final Map<String, dynamic>? nextPageToken;
  final bool hasMore;
  final Map<String, dynamic> raw;

  factory CatalogPullResponse.fromRpc(dynamic value) {
    final map = _asMap(value);

    final records = <Map<String, dynamic>>[];
    final rawRecords = map['records'] ?? map['data'] ?? map['items'] ?? [];

    if (rawRecords is List) {
      for (final item in rawRecords) {
        if (item is Map<String, dynamic>) {
          records.add(item);
        } else if (item is Map) {
          records.add(Map<String, dynamic>.from(item));
        }
      }
    }

    final serverTime = _dateTime(map['server_time'] ?? map['serverTime']) ??
        DateTime.now().toUtc();

    final catalogVersion = _int(
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

    final hasMore = _bool(
          map['has_more'] ?? map['hasMore'] ?? map['more'],
        ) ??
        nextPageToken != null;

    return CatalogPullResponse(
      records: records,
      serverTime: serverTime,
      catalogVersion: catalogVersion,
      nextPageToken: nextPageToken,
      hasMore: hasMore,
      raw: map,
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    if (value is List) {
      return {
        'records': value,
        'server_time': DateTime.now().toUtc().toIso8601String(),
        'has_more': false,
      };
    }

    return {
      'records': <Map<String, dynamic>>[],
      'server_time': DateTime.now().toUtc().toIso8601String(),
      'has_more': false,
    };
  }

  static Map<String, dynamic>? _nullableMap(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
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

class CatalogSyncRunResult {
  const CatalogSyncRunResult({
    required this.pagesPulled,
    required this.recordsReceived,
    required this.recordsApplied,
    required this.masterProductsUpserted,
    required this.productBarcodesUpserted,
    required this.ignoredRecords,
    required this.completed,
  });

  final int pagesPulled;
  final int recordsReceived;
  final int recordsApplied;
  final int masterProductsUpserted;
  final int productBarcodesUpserted;
  final int ignoredRecords;
  final bool completed;

  Map<String, dynamic> toJson() {
    return {
      'pages_pulled': pagesPulled,
      'records_received': recordsReceived,
      'records_applied': recordsApplied,
      'master_products_upserted': masterProductsUpserted,
      'product_barcodes_upserted': productBarcodesUpserted,
      'ignored_records': ignoredRecords,
      'completed': completed,
    };
  }
}
