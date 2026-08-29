class BusinessBranchSummary {
  const BusinessBranchSummary({
    required this.id,
    required this.businessId,
    required this.name,
    required this.status,
    required this.isPrimary,
    required this.runtimeReady,
    this.address,
    this.phone,
    this.cashRegisterId,
    this.cashRegisterName,
    this.receiptSequenceId,
  });

  final String id;
  final String businessId;
  final String name;
  final String? address;
  final String? phone;
  final String status;
  final bool isPrimary;
  final String? cashRegisterId;
  final String? cashRegisterName;
  final String? receiptSequenceId;
  final bool runtimeReady;

  factory BusinessBranchSummary.fromJson(Map<String, dynamic> json) {
    return BusinessBranchSummary(
      id: _requiredString(json, 'id'),
      businessId: _requiredString(json, 'business_id'),
      name: _requiredString(json, 'name'),
      address: _nullableString(json['address']),
      phone: _nullableString(json['phone']),
      status: _requiredString(json, 'status'),
      isPrimary: json['is_primary'] == true,
      cashRegisterId: _nullableString(json['cash_register_id']),
      cashRegisterName: _nullableString(json['cash_register_name']),
      receiptSequenceId: _nullableString(json['receipt_sequence_id']),
      runtimeReady: json['runtime_ready'] == true,
    );
  }
}

class CreateBusinessBranchRequest {
  const CreateBusinessBranchRequest({
    required this.businessId,
    required this.name,
    this.address,
    this.phone,
  });

  final String businessId;
  final String name;
  final String? address;
  final String? phone;

  String get fingerprint =>
      [businessId, name.trim(), address?.trim(), phone?.trim()].join('|');
}

class BusinessBranchCreationResult {
  const BusinessBranchCreationResult({
    required this.branchId,
    required this.businessId,
    required this.name,
    required this.runtimeReady,
    required this.idempotencyKey,
  });

  final String branchId;
  final String businessId;
  final String name;
  final bool runtimeReady;
  final String idempotencyKey;

  factory BusinessBranchCreationResult.fromJson(Map<String, dynamic> json) {
    return BusinessBranchCreationResult(
      branchId: _requiredString(json, 'branch_id'),
      businessId: _requiredString(json, 'business_id'),
      name: _requiredString(json, 'name'),
      runtimeReady: json['runtime_ready'] == true,
      idempotencyKey: _requiredString(json, 'idempotency_key'),
    );
  }
}

class DelegableBusinessRole {
  const DelegableBusinessRole({required this.id, required this.name});

  final String id;
  final String name;

  factory DelegableBusinessRole.fromJson(Map<String, dynamic> json) {
    return DelegableBusinessRole(
      id: _requiredString(json, 'role_id'),
      name: _requiredString(json, 'role_name'),
    );
  }
}

class InvitableBusinessBranch {
  const InvitableBusinessBranch({
    required this.id,
    required this.name,
    required this.isPrimary,
  });

  final String id;
  final String name;
  final bool isPrimary;

  factory InvitableBusinessBranch.fromJson(Map<String, dynamic> json) {
    return InvitableBusinessBranch(
      id: _requiredString(json, 'branch_id'),
      name: _requiredString(json, 'name'),
      isPrimary: json['is_primary'] == true,
    );
  }
}

class BusinessMemberInvitationOptions {
  const BusinessMemberInvitationOptions({
    required this.profileId,
    required this.businessId,
    required this.canInviteBusinessWide,
    required this.roles,
    required this.branches,
  });

  final String profileId;
  final String businessId;
  final bool canInviteBusinessWide;
  final List<DelegableBusinessRole> roles;
  final List<InvitableBusinessBranch> branches;

  factory BusinessMemberInvitationOptions.fromJson(Map<String, dynamic> json) {
    return BusinessMemberInvitationOptions(
      profileId: _requiredString(json, 'profile_id'),
      businessId: _requiredString(json, 'business_id'),
      canInviteBusinessWide: json['can_invite_business_wide'] == true,
      roles: _mapList(json['delegable_roles'], DelegableBusinessRole.fromJson),
      branches: _mapList(
          json['invitable_branches'], InvitableBusinessBranch.fromJson),
    );
  }
}

enum BusinessMemberInvitationDeliveryState { pending, sent, failed, unknown }

enum BusinessMemberInvitationScope { business, branch }

class BusinessMemberInvitation {
  const BusinessMemberInvitation({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.email,
    required this.roleId,
    required this.roleName,
    required this.scope,
    required this.status,
    required this.deliveryStatus,
    required this.expiresAt,
    required this.isExpired,
    this.branchId,
    this.branchName,
  });

  final String id;
  final String businessId;
  final String businessName;
  final String email;
  final String roleId;
  final String roleName;
  final String? branchId;
  final String? branchName;
  final BusinessMemberInvitationScope scope;
  final String status;
  final BusinessMemberInvitationDeliveryState deliveryStatus;
  final DateTime expiresAt;
  final bool isExpired;

  bool get isPending => status == 'pending' && !isExpired;

  factory BusinessMemberInvitation.fromJson(Map<String, dynamic> json) {
    return BusinessMemberInvitation(
      id: _requiredString(json, 'invitation_id'),
      businessId: _requiredString(json, 'business_id'),
      businessName: _requiredString(json, 'business_name'),
      email: _requiredString(json, 'email'),
      roleId: _requiredString(json, 'role_id'),
      roleName: _requiredString(json, 'role_name'),
      branchId: _nullableString(json['branch_id']),
      branchName: _nullableString(json['branch_name']),
      scope: _invitationScope(json['scope']),
      status: _requiredString(json, 'status'),
      deliveryStatus: _deliveryStatus(json['delivery_status']),
      expiresAt: DateTime.parse(_requiredString(json, 'expires_at')).toUtc(),
      isExpired: json['is_expired'] == true,
    );
  }
}

class BusinessMemberInvitationsResponse {
  const BusinessMemberInvitationsResponse({
    required this.userId,
    required this.invitations,
    required this.generatedAt,
  });

  final String userId;
  final List<BusinessMemberInvitation> invitations;
  final DateTime generatedAt;

  factory BusinessMemberInvitationsResponse.fromJson(
      Map<String, dynamic> json) {
    return BusinessMemberInvitationsResponse(
      userId: _requiredString(json, 'user_id'),
      invitations:
          _mapList(json['invitations'], BusinessMemberInvitation.fromJson),
      generatedAt:
          DateTime.parse(_requiredString(json, 'generated_at')).toUtc(),
    );
  }
}

class AdminBusinessMemberInvitationsResponse {
  const AdminBusinessMemberInvitationsResponse({
    required this.profileId,
    required this.businessId,
    required this.canInviteBusinessWide,
    required this.invitations,
  });

  final String profileId;
  final String businessId;
  final bool canInviteBusinessWide;
  final List<BusinessMemberInvitation> invitations;

  factory AdminBusinessMemberInvitationsResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return AdminBusinessMemberInvitationsResponse(
      profileId: _requiredString(json, 'profile_id'),
      businessId: _requiredString(json, 'business_id'),
      canInviteBusinessWide: json['can_invite_business_wide'] == true,
      invitations:
          _mapList(json['invitations'], BusinessMemberInvitation.fromJson),
    );
  }
}

class IssueBusinessMemberInvitationRequest {
  const IssueBusinessMemberInvitationRequest({
    required this.businessId,
    required this.email,
    required this.roleId,
    this.branchId,
  });

  final String businessId;
  final String email;
  final String roleId;
  final String? branchId;

  String get fingerprint =>
      [businessId, email.trim().toLowerCase(), roleId, branchId].join('|');
}

class IssueBusinessMemberInvitationResult {
  const IssueBusinessMemberInvitationResult({
    required this.invitation,
    required this.deliveryAttempted,
    required this.deliveryStatus,
    required this.existingUserNotificationRequired,
  });

  final BusinessMemberInvitation invitation;
  final bool deliveryAttempted;
  final BusinessMemberInvitationDeliveryState deliveryStatus;
  final bool existingUserNotificationRequired;

  String get userMessage {
    if (deliveryStatus == BusinessMemberInvitationDeliveryState.sent) {
      return 'Invitación enviada.';
    }
    if (deliveryStatus == BusinessMemberInvitationDeliveryState.failed) {
      return 'La invitación fue creada, pero el correo no pudo enviarse.';
    }
    return 'La invitación quedó disponible para el usuario.';
  }

  factory IssueBusinessMemberInvitationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final invitation = BusinessMemberInvitation.fromJson(
      _requiredMap(json['invitation'], 'invitation'),
    );
    final delivery = json['delivery'];
    final deliveryValue = delivery is Map
        ? Map<String, dynamic>.from(delivery)['delivery_status']
        : json['delivery_status'];
    return IssueBusinessMemberInvitationResult(
      invitation: invitation,
      deliveryAttempted: json['delivery_attempted'] == true,
      deliveryStatus: deliveryValue == null
          ? invitation.deliveryStatus
          : _deliveryStatus(deliveryValue),
      existingUserNotificationRequired:
          json['existing_user_notification_required'] == true,
    );
  }
}

class AcceptedBusinessMemberInvitation {
  const AcceptedBusinessMemberInvitation({
    required this.invitationId,
    required this.profileId,
    required this.businessId,
    required this.roleId,
    required this.membershipId,
    this.branchId,
  });

  final String invitationId;
  final String profileId;
  final String businessId;
  final String? branchId;
  final String roleId;
  final String membershipId;

  factory AcceptedBusinessMemberInvitation.fromJson(Map<String, dynamic> json) {
    return AcceptedBusinessMemberInvitation(
      invitationId: _requiredString(json, 'invitation_id'),
      profileId: _requiredString(json, 'profile_id'),
      businessId: _requiredString(json, 'business_id'),
      branchId: _nullableString(json['branch_id']),
      roleId: _requiredString(json, 'role_id'),
      membershipId: _requiredString(json, 'membership_id'),
    );
  }
}

BusinessMemberInvitationDeliveryState _deliveryStatus(Object? raw) {
  return switch (raw) {
    'pending' => BusinessMemberInvitationDeliveryState.pending,
    'sent' => BusinessMemberInvitationDeliveryState.sent,
    'failed' => BusinessMemberInvitationDeliveryState.failed,
    _ => BusinessMemberInvitationDeliveryState.unknown,
  };
}

BusinessMemberInvitationScope _invitationScope(Object? raw) {
  return switch (raw) {
    'business' => BusinessMemberInvitationScope.business,
    'branch' => BusinessMemberInvitationScope.branch,
    _ => throw const FormatException('Alcance de invitación inválido.'),
  };
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Respuesta administrativa inválida: falta $key.');
  }
  return value;
}

String? _nullableString(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) return null;
  return raw;
}

Map<String, dynamic> _requiredMap(Object? raw, String key) {
  if (raw is! Map) {
    throw FormatException('Respuesta administrativa inválida: falta $key.');
  }
  return Map<String, dynamic>.from(raw);
}

List<T> _mapList<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
  if (raw is! List) {
    throw const FormatException('Respuesta administrativa inválida.');
  }
  return raw.map((item) => parse(_requiredMap(item, 'item'))).toList();
}
