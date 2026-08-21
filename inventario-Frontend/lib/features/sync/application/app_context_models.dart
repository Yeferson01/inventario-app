class AppPermissionSet {
  const AppPermissionSet(this.values);

  final Set<String> values;

  bool has(String permission) {
    return values.contains(permission);
  }

  bool hasAny(Iterable<String> permissions) {
    return permissions.any(values.contains);
  }

  bool hasAll(Iterable<String> permissions) {
    return permissions.every(values.contains);
  }

  List<String> sorted() {
    return values.toList()..sort();
  }

  Map<String, dynamic> toJson() {
    return {
      'values': sorted(),
    };
  }

  factory AppPermissionSet.fromIterable(Iterable<String> values) {
    return AppPermissionSet(
      values
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet(),
    );
  }
}

class AppCurrentContext {
  const AppCurrentContext({
    required this.businessId,
    required this.installationId,
    required this.isOnline,
    required this.permissions,
    this.effectiveRoles = const [],
    this.applicableMembershipIds = const [],
    this.authorizationContextReady = false,
    this.authorizationValidatedAt,
    this.branchId,
    this.profileId,
    this.appDeviceId,
    this.roleId,
    this.roleName,
    this.cashRegisterId,
    this.cashSessionId,
    this.receiptSequenceId,
    this.lastSyncStatus,
  });

  final String businessId;
  final String installationId;
  final bool isOnline;
  final AppPermissionSet permissions;
  final List<String> effectiveRoles;
  final List<String> applicableMembershipIds;
  final bool authorizationContextReady;
  final DateTime? authorizationValidatedAt;

  final String? branchId;
  final String? profileId;
  final String? appDeviceId;
  final String? roleId;
  final String? roleName;

  final String? cashRegisterId;
  final String? cashSessionId;
  final String? receiptSequenceId;

  final String? lastSyncStatus;

  bool hasPermission(String permission) {
    return authorizationContextReady && permissions.has(permission);
  }

  bool hasAnyPermission(Iterable<String> values) {
    return authorizationContextReady && permissions.hasAny(values);
  }

  bool hasAllPermissions(Iterable<String> values) {
    return authorizationContextReady && permissions.hasAll(values);
  }

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      'profile_id': profileId,
      'installation_id': installationId,
      'app_device_id': appDeviceId,
      'role_id': roleId,
      'role_name': roleName,
      'permissions': permissions.sorted(),
      'effective_roles': effectiveRoles,
      'applicable_membership_ids': applicableMembershipIds,
      'authorization_context_ready': authorizationContextReady,
      'authorization_validated_at': authorizationValidatedAt?.toIso8601String(),
      'is_online': isOnline,
      'cash_register_id': cashRegisterId,
      'cash_session_id': cashSessionId,
      'receipt_sequence_id': receiptSequenceId,
      'last_sync_status': lastSyncStatus,
    };
  }
}
