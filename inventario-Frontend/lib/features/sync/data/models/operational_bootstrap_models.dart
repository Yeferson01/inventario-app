enum OperationalBootstrapFailureKind {
  networkTransient,
  unauthorized,
  forbidden,
  invalidToken,
  malformedResponse,
  scopeMismatch,
  localPersistence,
  remoteFailure,
}

class OperationalBootstrapException implements Exception {
  const OperationalBootstrapException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final OperationalBootstrapFailureKind kind;
  final String message;
  final Object? cause;

  bool get retryable =>
      kind == OperationalBootstrapFailureKind.networkTransient;

  @override
  String toString() => 'OperationalBootstrapException($kind): $message';
}

enum OperationalBootstrapRecordState {
  present,
  tombstone,
  unspecified;

  static OperationalBootstrapRecordState fromJson(Object? value) {
    return switch (value) {
      'present' => OperationalBootstrapRecordState.present,
      'tombstone' => OperationalBootstrapRecordState.tombstone,
      null => OperationalBootstrapRecordState.unspecified,
      _ => throw OperationalBootstrapException(
          kind: OperationalBootstrapFailureKind.malformedResponse,
          message: 'Unsupported bootstrap record state: $value',
        ),
    };
  }
}

class OperationalBootstrapRow {
  OperationalBootstrapRow._({
    required this.data,
    required this.state,
  });

  factory OperationalBootstrapRow.fromJson(Object? value) {
    final data = _jsonMap(value, 'dataset row');
    return OperationalBootstrapRow._(
      data: Map<String, Object?>.unmodifiable(data),
      state: OperationalBootstrapRecordState.fromJson(
        data['_bootstrap_record_state'],
      ),
    );
  }

  final Map<String, Object?> data;
  final OperationalBootstrapRecordState state;

  String? get entityId {
    final value = data['id'];
    return value is String && value.isNotEmpty ? value : null;
  }
}

class OperationalBootstrapDatasetPage {
  const OperationalBootstrapDatasetPage({
    required this.dataset,
    required this.rows,
    required this.count,
    required this.hasMore,
    required this.complete,
    required this.authoritativeScopeComplete,
    required this.pageSize,
    required this.nextPageToken,
  });

  factory OperationalBootstrapDatasetPage.fromJson(
    String mapKey,
    Object? value,
  ) {
    final json = _jsonMap(value, 'dataset $mapKey');
    final dataset = _requiredString(json, 'dataset');
    if (dataset != mapKey) {
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.malformedResponse,
        message: 'Dataset map key $mapKey does not match payload $dataset.',
      );
    }

    final rawRows = json['rows'];
    if (rawRows is! List) {
      throw _malformed('datasets.$dataset.rows must be a list.');
    }
    final rows =
        rawRows.map(OperationalBootstrapRow.fromJson).toList(growable: false);
    final count = _requiredInt(json, 'count');
    if (count != rows.length) {
      throw _malformed(
        'datasets.$dataset.count does not match the number of rows.',
      );
    }

    final hasMore = _requiredBool(json, 'has_more');
    final complete = _requiredBool(json, 'complete');
    final authoritativeScopeComplete =
        _requiredBool(json, 'authoritative_scope_complete');
    final nextPageToken = _optionalString(json, 'next_page_token');

    if (hasMore && nextPageToken == null) {
      throw _malformed(
        'datasets.$dataset has_more=true requires next_page_token.',
      );
    }
    if (!hasMore && nextPageToken != null) {
      throw _malformed(
        'datasets.$dataset returned a token although has_more=false.',
      );
    }
    if (complete == hasMore || authoritativeScopeComplete == hasMore) {
      throw _malformed(
        'datasets.$dataset has inconsistent completion flags.',
      );
    }

    return OperationalBootstrapDatasetPage(
      dataset: dataset,
      rows: rows,
      count: count,
      hasMore: hasMore,
      complete: complete,
      authoritativeScopeComplete: authoritativeScopeComplete,
      pageSize: _requiredInt(json, 'page_size'),
      nextPageToken: nextPageToken,
    );
  }

  final String dataset;
  final List<OperationalBootstrapRow> rows;
  final int count;
  final bool hasMore;
  final bool complete;
  final bool authoritativeScopeComplete;
  final int pageSize;
  final String? nextPageToken;
}

class OperationalBootstrapSnapshotPage {
  const OperationalBootstrapSnapshotPage({
    required this.snapshotId,
    required this.snapshotAt,
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.appDeviceId,
    required this.bundle,
    required this.datasetRequested,
    required this.datasets,
    required this.snapshotComplete,
    required this.requestedDatasetsComplete,
    required this.authorizationValidatedAt,
    required this.generatedAt,
    required this.syncCursorRead,
    required this.syncCursorAdvanced,
    required this.consistency,
    required this.warnings,
  });

  factory OperationalBootstrapSnapshotPage.fromRpc(Object? value) {
    final json = _jsonMap(value, 'RPC response');
    final rawDatasets = _jsonMap(json['datasets'], 'datasets');
    if (rawDatasets.isEmpty) {
      throw _malformed('The bootstrap response contains no datasets.');
    }
    final datasets = <String, OperationalBootstrapDatasetPage>{};
    for (final entry in rawDatasets.entries) {
      datasets[entry.key] = OperationalBootstrapDatasetPage.fromJson(
        entry.key,
        entry.value,
      );
    }

    return OperationalBootstrapSnapshotPage(
      snapshotId: _requiredString(json, 'snapshot_id'),
      snapshotAt: _requiredDateTime(json, 'snapshot_at'),
      profileId: _requiredString(json, 'profile_id'),
      businessId: _requiredString(json, 'business_id'),
      branchId: _requiredString(json, 'branch_id'),
      appDeviceId: _requiredString(json, 'app_device_id'),
      bundle: _requiredString(json, 'bundle'),
      datasetRequested: _optionalString(json, 'dataset_requested'),
      datasets: Map<String, OperationalBootstrapDatasetPage>.unmodifiable(
        datasets,
      ),
      snapshotComplete: _optionalBool(json, 'snapshot_complete'),
      requestedDatasetsComplete:
          _requiredBool(json, 'requested_datasets_complete'),
      authorizationValidatedAt:
          _requiredDateTime(json, 'authorization_validated_at'),
      generatedAt: _requiredDateTime(json, 'generated_at'),
      syncCursorRead: _requiredBool(json, 'sync_cursor_read'),
      syncCursorAdvanced: _requiredBool(json, 'sync_cursor_advanced'),
      consistency: Map<String, Object?>.unmodifiable(
        _jsonMap(json['consistency'], 'consistency'),
      ),
      warnings: _stringList(json['warnings'], 'warnings'),
    );
  }

  final String snapshotId;
  final DateTime snapshotAt;
  final String profileId;
  final String businessId;
  final String branchId;
  final String appDeviceId;
  final String bundle;
  final String? datasetRequested;
  final Map<String, OperationalBootstrapDatasetPage> datasets;
  final bool? snapshotComplete;
  final bool requestedDatasetsComplete;
  final DateTime authorizationValidatedAt;
  final DateTime generatedAt;
  final bool syncCursorRead;
  final bool syncCursorAdvanced;
  final Map<String, Object?> consistency;
  final List<String> warnings;
}

class OperationalBootstrapRemoteRequest {
  const OperationalBootstrapRemoteRequest({
    required this.businessId,
    required this.branchId,
    required this.appDeviceId,
    required this.bundle,
    this.dataset,
    this.limit = 500,
    this.pageToken,
  });

  final String businessId;
  final String branchId;
  final String appDeviceId;
  final String bundle;
  final String? dataset;
  final int limit;
  final String? pageToken;

  Map<String, Object?> toRpcParams() => {
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_app_device_id': appDeviceId,
        'p_bundle': bundle,
        'p_dataset': dataset,
        'p_limit_per_dataset': limit,
        'p_page_token': pageToken,
      };
}

OperationalBootstrapException _malformed(String message) {
  return OperationalBootstrapException(
    kind: OperationalBootstrapFailureKind.malformedResponse,
    message: message,
  );
}

Map<String, Object?> _jsonMap(Object? value, String field) {
  if (value is! Map) {
    throw _malformed('$field must be a JSON object.');
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String _requiredString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String || value.isEmpty) {
    throw _malformed('$field must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is! String || value.isEmpty) {
    throw _malformed('$field must be null or a non-empty string.');
  }
  return value;
}

int _requiredInt(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! int) {
    throw _malformed('$field must be an integer.');
  }
  return value;
}

bool _requiredBool(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! bool) {
    throw _malformed('$field must be a boolean.');
  }
  return value;
}

bool? _optionalBool(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value == null) {
    return null;
  }
  if (value is! bool) {
    throw _malformed('$field must be null or a boolean.');
  }
  return value;
}

DateTime _requiredDateTime(Map<String, Object?> json, String field) {
  final value = json[field];
  if (value is! String) {
    throw _malformed('$field must be an ISO-8601 string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw _malformed('$field is not a valid ISO-8601 timestamp.');
  }
  return parsed.toUtc();
}

List<String> _stringList(Object? value, String field) {
  if (value == null) {
    return const [];
  }
  if (value is! List || value.any((item) => item is! String)) {
    throw _malformed('$field must be a list of strings.');
  }
  return List<String>.unmodifiable(value.cast<String>());
}
