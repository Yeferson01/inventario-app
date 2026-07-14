class AppBusinessSelectionOption {
  const AppBusinessSelectionOption({
    required this.membershipId,
    required this.businessId,
    required this.businessName,
    required this.profileId,
    required this.roleId,
    required this.roleName,
    this.branchId,
    this.branchName,
  });

  final String membershipId;
  final String businessId;
  final String businessName;
  final String profileId;
  final String roleId;
  final String roleName;

  final String? branchId;
  final String? branchName;

  bool get hasBranch => branchId != null && branchId!.trim().isNotEmpty;

  String get displayName {
    if (branchName != null && branchName!.trim().isNotEmpty) {
      return '$businessName / $branchName';
    }

    return businessName;
  }

  Map<String, dynamic> toJson() {
    return {
      'membership_id': membershipId,
      'business_id': businessId,
      'business_name': businessName,
      'branch_id': branchId,
      'branch_name': branchName,
      'profile_id': profileId,
      'role_id': roleId,
      'role_name': roleName,
      'display_name': displayName,
    };
  }

  factory AppBusinessSelectionOption.fromRow(Map<String, dynamic> row) {
    return AppBusinessSelectionOption(
      membershipId: _requiredString(row, 'membership_id'),
      businessId: _requiredString(row, 'business_id'),
      businessName: _string(row['business_name']) ?? 'Negocio sin nombre',
      branchId: _string(row['branch_id']),
      branchName: _string(row['branch_name']),
      profileId: _requiredString(row, 'profile_id'),
      roleId: _requiredString(row, 'role_id'),
      roleName: _string(row['role_name']) ?? 'sin_rol',
    );
  }

  static String _requiredString(Map<String, dynamic> row, String key) {
    final value = _string(row[key]);

    if (value == null) {
      throw StateError('Opción de negocio inválida. Falta $key.');
    }

    return value;
  }

  static String? _string(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }
}

class AppBusinessSelectionResult {
  const AppBusinessSelectionResult({
    required this.selected,
    required this.savedBusinessId,
    required this.savedProfileId,
    this.savedBranchId,
  });

  final AppBusinessSelectionOption selected;
  final String savedBusinessId;
  final String savedProfileId;
  final String? savedBranchId;

  Map<String, dynamic> toJson() {
    return {
      'selected': selected.toJson(),
      'saved_business_id': savedBusinessId,
      'saved_branch_id': savedBranchId,
      'saved_profile_id': savedProfileId,
    };
  }
}
