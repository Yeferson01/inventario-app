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
