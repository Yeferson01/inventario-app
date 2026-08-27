import 'dart:convert';

enum CatalogReadinessStatus {
  uninitialized,
  initializing,
  ready,
  readyWithSyncError,
  failedBeforeReady,
}

class CatalogReadiness {
  const CatalogReadiness({
    required this.status,
    required this.isSyncing,
    required this.hasResumeCheckpoint,
    this.lastError,
    this.lastCompletedAt,
    this.lastServerTime,
  });

  factory CatalogReadiness.fromSyncState(Map<String, dynamic>? state) {
    if (state == null) {
      return const CatalogReadiness(
        status: CatalogReadinessStatus.uninitialized,
        isSyncing: false,
        hasResumeCheckpoint: false,
      );
    }

    final lastCompletedAt = _dateTime(state['last_catalog_pull_at']);
    final lastServerTime = _dateTime(state['last_server_time']);
    final committedSince = _dateTime(state['last_since_updated_at']);
    final lastError = _nonEmptyString(state['last_error']);
    final rawPageToken = state['last_page_token'];
    final hasResumeCheckpoint = _hasPageToken(rawPageToken);
    final hasTrustedInitialCompletion = lastCompletedAt != null &&
        (!hasResumeCheckpoint ||
            (_isSignedCatalogToken(rawPageToken) &&
                !_sameInstant(committedSince, lastServerTime)));
    final isSyncing = _bool(state['is_syncing']);

    final status = hasTrustedInitialCompletion
        ? lastError == null
            ? CatalogReadinessStatus.ready
            : CatalogReadinessStatus.readyWithSyncError
        : isSyncing
            ? CatalogReadinessStatus.initializing
            : lastError != null
                ? CatalogReadinessStatus.failedBeforeReady
                : hasResumeCheckpoint
                    ? CatalogReadinessStatus.initializing
                    : CatalogReadinessStatus.uninitialized;

    return CatalogReadiness(
      status: status,
      isSyncing: isSyncing,
      hasResumeCheckpoint: hasResumeCheckpoint,
      lastError: lastError,
      lastCompletedAt: hasTrustedInitialCompletion ? lastCompletedAt : null,
      lastServerTime: lastServerTime,
    );
  }

  final CatalogReadinessStatus status;
  final bool isSyncing;
  final bool hasResumeCheckpoint;
  final String? lastError;
  final DateTime? lastCompletedAt;
  final DateTime? lastServerTime;

  bool get isReady =>
      status == CatalogReadinessStatus.ready ||
      status == CatalogReadinessStatus.readyWithSyncError;

  bool get isInitializing => status == CatalogReadinessStatus.initializing;
}

DateTime? _dateTime(Object? value) {
  if (value is DateTime) return value.toUtc();
  if (value is int) {
    return DateTime.fromMicrosecondsSinceEpoch(value, isUtc: true);
  }
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toUtc();
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _bool(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  return value?.toString().toLowerCase() == 'true';
}

bool _hasPageToken(Object? value) {
  if (value == null) return false;
  if (value is Map) return value.isNotEmpty;
  return value.toString().trim().isNotEmpty;
}

bool _isSignedCatalogToken(Object? value) {
  Object? decoded = value;
  if (value is String) {
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return false;
    }
  }
  if (decoded is! Map) return false;
  return decoded['token_version'] == 1 &&
      decoded['token'] is String &&
      (decoded['token'] as String).isNotEmpty;
}

bool _sameInstant(DateTime? left, DateTime? right) {
  if (left == null || right == null) return left == right;
  return left.microsecondsSinceEpoch == right.microsecondsSinceEpoch;
}
