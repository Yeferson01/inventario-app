class OperationalContextSnapshot {
  const OperationalContextSnapshot({
    required this.businesses,
    required this.profiles,
    required this.branches,
    required this.businessMembers,
    required this.roles,
    required this.permissions,
    required this.rolePermissions,
  });

  final List<Map<String, dynamic>> businesses;
  final List<Map<String, dynamic>> profiles;
  final List<Map<String, dynamic>> branches;
  final List<Map<String, dynamic>> businessMembers;
  final List<Map<String, dynamic>> roles;
  final List<Map<String, dynamic>> permissions;
  final List<Map<String, dynamic>> rolePermissions;

  int get totalRecords {
    return businesses.length +
        profiles.length +
        branches.length +
        businessMembers.length +
        roles.length +
        permissions.length +
        rolePermissions.length;
  }

  Map<String, dynamic> toJson() {
    return {
      'businesses': businesses.length,
      'profiles': profiles.length,
      'branches': branches.length,
      'business_members': businessMembers.length,
      'roles': roles.length,
      'permissions': permissions.length,
      'role_permissions': rolePermissions.length,
      'total_records': totalRecords,
    };
  }
}

class OperationalContextPullResult {
  const OperationalContextPullResult({
    required this.businessId,
    required this.profileId,
    required this.appliedBusinesses,
    required this.appliedProfiles,
    required this.appliedBranches,
    required this.appliedBusinessMembers,
    required this.appliedRoles,
    required this.appliedPermissions,
    required this.appliedRolePermissions,
  });

  final String businessId;
  final String profileId;

  final int appliedBusinesses;
  final int appliedProfiles;
  final int appliedBranches;
  final int appliedBusinessMembers;
  final int appliedRoles;
  final int appliedPermissions;
  final int appliedRolePermissions;

  int get totalApplied {
    return appliedBusinesses +
        appliedProfiles +
        appliedBranches +
        appliedBusinessMembers +
        appliedRoles +
        appliedPermissions +
        appliedRolePermissions;
  }

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'profile_id': profileId,
      'applied_businesses': appliedBusinesses,
      'applied_profiles': appliedProfiles,
      'applied_branches': appliedBranches,
      'applied_business_members': appliedBusinessMembers,
      'applied_roles': appliedRoles,
      'applied_permissions': appliedPermissions,
      'applied_role_permissions': appliedRolePermissions,
      'total_applied': totalApplied,
    };
  }
}
