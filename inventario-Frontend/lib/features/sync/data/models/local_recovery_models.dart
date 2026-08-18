class OperationalBootstrapScope {
  const OperationalBootstrapScope({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.appDeviceId,
    required this.bundle,
    required this.dataset,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String appDeviceId;
  final String bundle;
  final String dataset;
}

enum OperationalBootstrapCheckpointStatus {
  started,
  applying,
  complete,
  failed,
  restartRequired;

  static OperationalBootstrapCheckpointStatus fromStorage(Object? value) {
    return switch (value) {
      'started' => OperationalBootstrapCheckpointStatus.started,
      'applying' => OperationalBootstrapCheckpointStatus.applying,
      'complete' => OperationalBootstrapCheckpointStatus.complete,
      'failed' => OperationalBootstrapCheckpointStatus.failed,
      'restart_required' =>
        OperationalBootstrapCheckpointStatus.restartRequired,
      _ => throw StateError('Unsupported bootstrap checkpoint status: $value'),
    };
  }

  String get storageValue => switch (this) {
        OperationalBootstrapCheckpointStatus.restartRequired =>
          'restart_required',
        _ => name,
      };
}

class OperationalBootstrapCheckpointRecord {
  const OperationalBootstrapCheckpointRecord({
    required this.scope,
    required this.snapshotId,
    required this.snapshotAt,
    required this.nextPageToken,
    required this.status,
    required this.rowsReceived,
    required this.pagesApplied,
    required this.authorizationValidatedAt,
    required this.retryCount,
    required this.convergenceStatus,
    required this.lastError,
  });

  factory OperationalBootstrapCheckpointRecord.fromRow(
    Map<String, dynamic> row,
  ) {
    return OperationalBootstrapCheckpointRecord(
      scope: OperationalBootstrapScope(
        profileId: row['profile_id'] as String,
        businessId: row['business_id'] as String,
        branchId: row['branch_id'] as String,
        appDeviceId: row['app_device_id'] as String,
        bundle: row['bundle'] as String,
        dataset: row['dataset'] as String,
      ),
      snapshotId: row['snapshot_id'] as String,
      snapshotAt: _recoveryDateTime(row['snapshot_at'], 'snapshot_at'),
      nextPageToken: row['next_page_token'] as String?,
      status: OperationalBootstrapCheckpointStatus.fromStorage(row['status']),
      rowsReceived: row['rows_received'] as int,
      pagesApplied: row['pages_applied'] as int,
      authorizationValidatedAt: _recoveryDateTime(
        row['authorization_validated_at'],
        'authorization_validated_at',
      ),
      retryCount: row['retry_count'] as int,
      convergenceStatus: row['convergence_status'] as String,
      lastError: row['last_error'] as String?,
    );
  }

  final OperationalBootstrapScope scope;
  final String snapshotId;
  final DateTime snapshotAt;
  final String? nextPageToken;
  final OperationalBootstrapCheckpointStatus status;
  final int rowsReceived;
  final int pagesApplied;
  final DateTime authorizationValidatedAt;
  final int retryCount;
  final String convergenceStatus;
  final String? lastError;

  bool get isComplete =>
      status == OperationalBootstrapCheckpointStatus.complete;
  bool get requiresRestart =>
      status == OperationalBootstrapCheckpointStatus.restartRequired;
  bool get isResumable => !isComplete && !requiresRestart;
}

class SeenRecordDraft {
  const SeenRecordDraft({
    required this.snapshotId,
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.bundle,
    required this.dataset,
    required this.entityId,
  });

  final String snapshotId;
  final String profileId;
  final String businessId;
  final String branchId;
  final String bundle;
  final String dataset;
  final String entityId;
}

class ReconciliationIssueDraft {
  const ReconciliationIssueDraft({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.domain,
    required this.issueType,
    required this.severity,
    required this.message,
    this.entityType,
    this.entityId,
    this.metadataJson,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String domain;
  final String? entityType;
  final String? entityId;
  final String issueType;
  final String severity;
  final String message;
  final String? metadataJson;
}

class AuthorizedOperationalContextProjection {
  const AuthorizedOperationalContextProjection({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.effectivePermissions,
    required this.effectiveRoles,
    required this.applicableMembershipIds,
    required this.authorizationValidatedAt,
    required this.snapshotId,
    this.status = 'active',
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final List<String> effectivePermissions;
  final List<String> effectiveRoles;
  final List<String> applicableMembershipIds;
  final DateTime authorizationValidatedAt;
  final String? snapshotId;
  final String status;
}

class AuthorizedOperationalContextRecord {
  const AuthorizedOperationalContextRecord({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.effectivePermissions,
    required this.effectiveRoles,
    required this.applicableMembershipIds,
    required this.authorizationValidatedAt,
    required this.snapshotId,
    required this.status,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final List<String> effectivePermissions;
  final List<String> effectiveRoles;
  final List<String> applicableMembershipIds;
  final DateTime authorizationValidatedAt;
  final String? snapshotId;
  final String status;

  bool get isActive => status == 'active';
}

DateTime _recoveryDateTime(Object? value, String field) {
  if (value is DateTime) {
    return value.toUtc();
  }
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) {
      return parsed.toUtc();
    }
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  throw StateError('Invalid $field in bootstrap checkpoint.');
}
