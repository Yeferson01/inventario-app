class PlatformBusinessInvitation {
  const PlatformBusinessInvitation({
    required this.invitationId,
    required this.businessId,
    required this.branchId,
    required this.businessName,
    required this.branchName,
    required this.status,
    required this.expiresAt,
    required this.isExpired,
    required this.createdAt,
    this.acceptedAt,
  });

  factory PlatformBusinessInvitation.fromJson(Object? value) {
    final json = _map(value, 'platform invitation');
    return PlatformBusinessInvitation(
      invitationId: _requiredString(json, 'invitation_id'),
      businessId: _requiredString(json, 'business_id'),
      branchId: _requiredString(json, 'branch_id'),
      businessName: _requiredString(json, 'business_name'),
      branchName: _requiredString(json, 'branch_name'),
      status: _requiredString(json, 'status'),
      expiresAt: _requiredDate(json, 'expires_at'),
      isExpired: _requiredBool(json, 'is_expired'),
      createdAt: _requiredDate(json, 'created_at'),
      acceptedAt: _optionalDate(json['accepted_at'], 'accepted_at'),
    );
  }

  final String invitationId;
  final String businessId;
  final String branchId;
  final String businessName;
  final String branchName;
  final String status;
  final DateTime expiresAt;
  final bool isExpired;
  final DateTime createdAt;
  final DateTime? acceptedAt;

  bool get isPending => status == 'pending' && !isExpired;
}

class MyPlatformBusinessInvitationsResponse {
  const MyPlatformBusinessInvitationsResponse({
    required this.userId,
    required this.invitations,
    required this.generatedAt,
  });

  factory MyPlatformBusinessInvitationsResponse.fromRpc(Object? value) {
    final json = _map(value, 'platform invitations response');
    final rawInvitations = json['invitations'];
    if (rawInvitations is! List) {
      throw const FormatException('invitations must be a JSON array.');
    }
    return MyPlatformBusinessInvitationsResponse(
      userId: _requiredString(json, 'user_id'),
      invitations: rawInvitations
          .map(PlatformBusinessInvitation.fromJson)
          .toList(growable: false),
      generatedAt: _requiredDate(json, 'generated_at'),
    );
  }

  final String userId;
  final List<PlatformBusinessInvitation> invitations;
  final DateTime generatedAt;
}

class AcceptedPlatformBusinessInvitation {
  const AcceptedPlatformBusinessInvitation({
    required this.invitationId,
    required this.businessId,
    required this.branchId,
    required this.invitationStatus,
  });

  factory AcceptedPlatformBusinessInvitation.fromRpc(Object? value) {
    final json = _map(value, 'accepted platform invitation');
    return AcceptedPlatformBusinessInvitation(
      invitationId: _requiredString(json, 'invitation_id'),
      businessId: _requiredString(json, 'business_id'),
      branchId: _requiredString(json, 'branch_id'),
      invitationStatus: _requiredString(json, 'invitation_status'),
    );
  }

  final String invitationId;
  final String businessId;
  final String branchId;
  final String invitationStatus;
}

Map<String, Object?> _map(Object? value, String label) {
  if (value is! Map) {
    throw FormatException('$label must be a JSON object.');
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value.trim();
}

bool _requiredBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean.');
  return value;
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = _optionalDate(json[key], key);
  if (value == null) throw FormatException('$key must be an ISO-8601 date.');
  return value;
}

DateTime? _optionalDate(Object? value, String key) {
  if (value == null) return null;
  if (value is! String) throw FormatException('$key must be a date or null.');
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw FormatException('$key must be an ISO-8601 date.');
  return parsed.toUtc();
}
