import 'operational_bootstrap_models.dart';

class CoreContextSnapshot {
  const CoreContextSnapshot({
    required this.profileId,
    required this.business,
    required this.branch,
    required this.appDevice,
    required this.applicableMembershipIds,
    required this.effectiveRoles,
    required this.effectivePermissions,
    required this.authorizationValidatedAt,
  });

  factory CoreContextSnapshot.fromBootstrapRow(
    OperationalBootstrapRow row,
  ) {
    final json = row.data;
    final profileId = _requiredString(json, 'profile_id');
    final business = CoreBusinessSnapshot.fromJson(
      _requiredMap(json, 'business'),
    );
    final branch = CoreBranchSnapshot.fromJson(
      _requiredMap(json, 'branch'),
    );
    final appDevice = CoreAppDeviceContext.fromJson(
      _requiredMap(json, 'app_device'),
    );
    final memberships = _requiredMapList(json, 'memberships')
        .map(CoreMembershipContext.fromJson)
        .toList(growable: false);
    final roles = _requiredMapList(json, 'effective_roles')
        .map(CoreEffectiveRole.fromJson)
        .toList(growable: false);
    final permissions = _requiredStringList(json, 'effective_permissions');

    if (branch.businessId != business.id ||
        appDevice.businessId != business.id ||
        appDevice.branchId != branch.id ||
        appDevice.profileId != profileId ||
        appDevice.status != 'active') {
      throw _malformed('Core context contains inconsistent tenant scope.');
    }
    for (final membership in memberships) {
      if (membership.profileId != profileId ||
          membership.businessId != business.id ||
          membership.status != 'active' ||
          (membership.branchId != null && membership.branchId != branch.id)) {
        throw _malformed(
          'Core membership does not apply to the requested context.',
        );
      }
    }
    for (final role in roles) {
      if (role.businessId != null && role.businessId != business.id) {
        throw _malformed('Core effective role belongs to another business.');
      }
    }

    return CoreContextSnapshot(
      profileId: profileId,
      business: business,
      branch: branch,
      appDevice: appDevice,
      applicableMembershipIds: memberships
          .map((membership) => membership.id)
          .toList(growable: false),
      effectiveRoles: roles,
      effectivePermissions: permissions,
      authorizationValidatedAt: _requiredDateTime(
        json,
        'authorization_validated_at',
      ),
    );
  }

  final String profileId;
  final CoreBusinessSnapshot business;
  final CoreBranchSnapshot branch;
  final CoreAppDeviceContext appDevice;
  final List<String> applicableMembershipIds;
  final List<CoreEffectiveRole> effectiveRoles;
  final List<String> effectivePermissions;
  final DateTime authorizationValidatedAt;
}

class CoreBusinessSnapshot {
  const CoreBusinessSnapshot({
    required this.id,
    required this.name,
    required this.subscriptionPlan,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    this.businessType,
    this.ownerName,
    this.phone,
    this.email,
    this.address,
  });

  factory CoreBusinessSnapshot.fromJson(Map<String, Object?> json) {
    return CoreBusinessSnapshot(
      id: _requiredString(json, 'id'),
      name: _requiredString(json, 'name'),
      businessType: _optionalString(json['business_type']),
      ownerName: _optionalString(json['owner_name']),
      phone: _optionalString(json['phone']),
      email: _optionalString(json['email']),
      address: _optionalString(json['address']),
      subscriptionPlan: _requiredString(json, 'subscription_plan'),
      status: _requiredString(json, 'status'),
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
      deletedAt: _optionalDateTime(json['deleted_at'], 'deleted_at'),
    );
  }

  final String id;
  final String name;
  final String? businessType;
  final String? ownerName;
  final String? phone;
  final String? email;
  final String? address;
  final String subscriptionPlan;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class CoreBranchSnapshot {
  const CoreBranchSnapshot({
    required this.id,
    required this.businessId,
    required this.name,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    this.address,
    this.phone,
  });

  factory CoreBranchSnapshot.fromJson(Map<String, Object?> json) {
    return CoreBranchSnapshot(
      id: _requiredString(json, 'id'),
      businessId: _requiredString(json, 'business_id'),
      name: _requiredString(json, 'name'),
      address: _optionalString(json['address']),
      phone: _optionalString(json['phone']),
      status: _requiredString(json, 'status'),
      createdAt: _requiredDateTime(json, 'created_at'),
      updatedAt: _requiredDateTime(json, 'updated_at'),
      deletedAt: _optionalDateTime(json['deleted_at'], 'deleted_at'),
    );
  }

  final String id;
  final String businessId;
  final String name;
  final String? address;
  final String? phone;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
}

class CoreAppDeviceContext {
  const CoreAppDeviceContext({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.profileId,
    required this.status,
  });

  factory CoreAppDeviceContext.fromJson(Map<String, Object?> json) {
    return CoreAppDeviceContext(
      id: _requiredString(json, 'id'),
      businessId: _requiredString(json, 'business_id'),
      branchId: _requiredString(json, 'branch_id'),
      profileId: _requiredString(json, 'profile_id'),
      status: _requiredString(json, 'status'),
    );
  }

  final String id;
  final String businessId;
  final String branchId;
  final String profileId;
  final String status;
}

class CoreMembershipContext {
  const CoreMembershipContext({
    required this.id,
    required this.businessId,
    required this.profileId,
    required this.roleId,
    required this.status,
    this.branchId,
  });

  factory CoreMembershipContext.fromJson(Map<String, Object?> json) {
    return CoreMembershipContext(
      id: _requiredString(json, 'id'),
      businessId: _requiredString(json, 'business_id'),
      profileId: _requiredString(json, 'profile_id'),
      branchId: _optionalString(json['branch_id']),
      roleId: _requiredString(json, 'role_id'),
      status: _requiredString(json, 'status'),
    );
  }

  final String id;
  final String businessId;
  final String profileId;
  final String? branchId;
  final String roleId;
  final String status;
}

class CoreEffectiveRole {
  const CoreEffectiveRole({
    required this.id,
    required this.name,
    required this.isSystemRole,
    this.businessId,
  });

  factory CoreEffectiveRole.fromJson(Map<String, Object?> json) {
    final isSystemRole = json['is_system_role'];
    if (isSystemRole is! bool) {
      throw _malformed('effective_roles.is_system_role must be boolean.');
    }
    return CoreEffectiveRole(
      id: _requiredString(json, 'role_id'),
      name: _requiredString(json, 'role_name'),
      businessId: _optionalString(json['business_id']),
      isSystemRole: isSystemRole,
    );
  }

  final String id;
  final String name;
  final String? businessId;
  final bool isSystemRole;
}

OperationalBootstrapException _malformed(String message) {
  return OperationalBootstrapException(
    kind: OperationalBootstrapFailureKind.malformedResponse,
    message: message,
  );
}

Map<String, Object?> _requiredMap(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value is! Map) {
    throw _malformed('$key must be a JSON object.');
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

List<Map<String, Object?>> _requiredMapList(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value is! List) {
    throw _malformed('$key must be a JSON array.');
  }
  return value.map((item) {
    if (item is! Map) {
      throw _malformed('$key entries must be JSON objects.');
    }
    return item.map((key, value) => MapEntry(key.toString(), value));
  }).toList(growable: false);
}

List<String> _requiredStringList(
  Map<String, Object?> json,
  String key,
) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw _malformed('$key must be a JSON string array.');
  }
  return value.cast<String>().toList(growable: false);
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) {
    throw _malformed('$key must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw _malformed('Expected a non-empty string or null.');
  }
  return value.trim();
}

DateTime _requiredDateTime(Map<String, Object?> json, String key) {
  final value = _optionalDateTime(json[key], key);
  if (value == null) {
    throw _malformed('$key must be an ISO-8601 timestamp.');
  }
  return value;
}

DateTime? _optionalDateTime(Object? value, String key) {
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw _malformed('$key must be an ISO-8601 string or null.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw _malformed('$key is not a valid ISO-8601 timestamp.');
  }
  return parsed.toUtc();
}
