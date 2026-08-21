import 'operational_integration_failure.dart';

class AuthorizedOperationalRole {
  const AuthorizedOperationalRole({
    required this.roleId,
    required this.roleName,
    required this.isSystemRole,
    required this.membershipIds,
  });

  factory AuthorizedOperationalRole.fromJson(Object? value) {
    final json = _map(value, 'effective role');
    return AuthorizedOperationalRole(
      roleId: _requiredString(json, 'role_id'),
      roleName: _requiredString(json, 'role_name'),
      isSystemRole: _requiredBool(json, 'is_system_role'),
      membershipIds: _stringList(json, 'membership_ids'),
    );
  }

  final String roleId;
  final String roleName;
  final bool isSystemRole;
  final List<String> membershipIds;

  Map<String, Object?> toJson() => {
        'role_id': roleId,
        'role_name': roleName,
        'is_system_role': isSystemRole,
        'membership_ids': membershipIds,
      };
}

class AuthorizedOperationalContext {
  const AuthorizedOperationalContext({
    required this.profileId,
    required this.businessId,
    required this.businessName,
    required this.businessStatus,
    required this.businessUpdatedAt,
    required this.branchId,
    required this.branchName,
    required this.branchStatus,
    required this.branchUpdatedAt,
    required this.membershipIds,
    required this.membershipsUpdatedAt,
    required this.effectiveRoles,
    required this.effectivePermissions,
  });

  factory AuthorizedOperationalContext.fromJson(Object? value) {
    final json = _map(value, 'authorized operational context');
    final rawRoles = json['effective_roles'];
    if (rawRoles is! List) {
      throw _malformed('effective_roles must be a JSON array.');
    }
    return AuthorizedOperationalContext(
      profileId: _requiredString(json, 'profile_id'),
      businessId: _requiredString(json, 'business_id'),
      businessName: _requiredString(json, 'business_name'),
      businessStatus: _requiredString(json, 'business_status'),
      businessUpdatedAt: _requiredDate(json, 'business_updated_at'),
      branchId: _requiredString(json, 'branch_id'),
      branchName: _requiredString(json, 'branch_name'),
      branchStatus: _requiredString(json, 'branch_status'),
      branchUpdatedAt: _requiredDate(json, 'branch_updated_at'),
      membershipIds: _stringList(json, 'membership_ids'),
      membershipsUpdatedAt: _optionalDate(
        json['memberships_updated_at'],
        'memberships_updated_at',
      ),
      effectiveRoles: rawRoles
          .map(AuthorizedOperationalRole.fromJson)
          .toList(growable: false),
      effectivePermissions: _stringList(json, 'effective_permissions'),
    );
  }

  final String profileId;
  final String businessId;
  final String businessName;
  final String businessStatus;
  final DateTime businessUpdatedAt;
  final String branchId;
  final String branchName;
  final String branchStatus;
  final DateTime branchUpdatedAt;
  final List<String> membershipIds;
  final DateTime? membershipsUpdatedAt;
  final List<AuthorizedOperationalRole> effectiveRoles;
  final List<String> effectivePermissions;

  bool get canRequestAdministrativeSetup =>
      effectivePermissions.contains('settings.business');

  String get scopeKey => '$businessId/$branchId';

  Map<String, Object?> toJson() => {
        'profile_id': profileId,
        'business_id': businessId,
        'business_name': businessName,
        'business_status': businessStatus,
        'business_updated_at': businessUpdatedAt.toIso8601String(),
        'branch_id': branchId,
        'branch_name': branchName,
        'branch_status': branchStatus,
        'branch_updated_at': branchUpdatedAt.toIso8601String(),
        'membership_ids': membershipIds,
        'memberships_updated_at': membershipsUpdatedAt?.toIso8601String(),
        'effective_roles': effectiveRoles.map((role) => role.toJson()).toList(),
        'effective_permissions': effectivePermissions,
      };
}

class AuthorizedOperationalContextsResponse {
  const AuthorizedOperationalContextsResponse({
    required this.profileId,
    required this.contexts,
    required this.generatedAt,
  });

  factory AuthorizedOperationalContextsResponse.fromRpc(Object? value) {
    final json = _map(value, 'authorized operational contexts response');
    final rawContexts = json['contexts'];
    if (rawContexts is! List) {
      throw _malformed('contexts must be a JSON array.');
    }
    return AuthorizedOperationalContextsResponse(
      profileId: _requiredString(json, 'profile_id'),
      contexts: rawContexts
          .map(AuthorizedOperationalContext.fromJson)
          .toList(growable: false),
      generatedAt: _requiredDate(json, 'generated_at'),
    );
  }

  final String profileId;
  final List<AuthorizedOperationalContext> contexts;
  final DateTime generatedAt;
}

OperationalIntegrationException _malformed(String message) {
  return OperationalIntegrationException(
    kind: OperationalIntegrationFailureKind.malformedResponse,
    message: message,
  );
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map) throw _malformed('$field must be a JSON object.');
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw _malformed('$key must be a non-empty string.');
  }
  return value.trim();
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw _malformed('$key must be a boolean.');
  return value;
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw _malformed('$key must be a JSON string array.');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = _optionalDate(json[key], key);
  if (value == null) throw _malformed('$key must be an ISO-8601 timestamp.');
  return value;
}

DateTime? _optionalDate(Object? value, String key) {
  if (value == null) return null;
  if (value is! String) {
    throw _malformed('$key must be an ISO-8601 string or null.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw _malformed('$key is not a valid timestamp.');
  return parsed.toUtc();
}
