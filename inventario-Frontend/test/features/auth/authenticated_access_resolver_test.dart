import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_models.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_resolver.dart';
import 'package:inventario_frontend/features/auth/data/datasources/platform_business_invitation_remote_datasource.dart';
import 'package:inventario_frontend/features/auth/data/models/platform_business_invitation_models.dart';
import 'package:inventario_frontend/features/sync/data/models/authorized_operational_context_models.dart';
import 'package:inventario_frontend/features/administration/data/datasources/business_administration_remote_datasource.dart';
import 'package:inventario_frontend/features/administration/data/models/business_administration_models.dart';

void main() {
  const profileId = 'profile-a';

  test('no contexts plus pending invitations resolves private onboarding',
      () async {
    final resolver = AuthenticatedAccessResolver(
      loadContexts: () async => const [],
      loadPlatformInvitations: () async => _response(
        profileId,
        [_invitation('invite-a'), _invitation('invite-b')],
      ),
      loadBusinessInvitations: () async =>
          _businessResponse(profileId, const []),
    );

    final result = await resolver.resolve(profileId);

    expect(result.outcome, AuthenticatedAccessOutcome.pendingInvitations);
    expect(result.pendingInvitations.map((item) => item.invitationId), [
      'invite-a',
      'invite-b',
    ]);
  });

  test('existing context and pending invitation remain available together',
      () async {
    final resolver = AuthenticatedAccessResolver(
      loadContexts: () async => [_context(profileId)],
      loadPlatformInvitations: () async => _response(
        profileId,
        [_invitation('invite-b')],
      ),
      loadBusinessInvitations: () async =>
          _businessResponse(profileId, const []),
    );

    final result = await resolver.resolve(profileId);

    expect(
      result.outcome,
      AuthenticatedAccessOutcome.existingContextsAndPendingInvitations,
    );
    expect(result.contexts, hasLength(1));
    expect(result.pendingInvitations, hasLength(1));
    expect(result.message.toLowerCase(), isNot(contains('not authorized')));
  });

  test('invitation network failure does not block an existing context',
      () async {
    final resolver = AuthenticatedAccessResolver(
      loadContexts: () async => [_context(profileId)],
      loadPlatformInvitations: () async =>
          throw const PlatformInvitationException(
        kind: PlatformInvitationFailureKind.network,
        message: 'offline',
      ),
      loadBusinessInvitations: () async =>
          _businessResponse(profileId, const []),
    );

    final result = await resolver.resolve(profileId);

    expect(result.outcome, AuthenticatedAccessOutcome.existingContexts);
    expect(result.invitationsAvailable, isFalse);
    expect(result.isTransientFailure, isTrue);
    expect(result.message.toLowerCase(), isNot(contains('unauthorized')));
  });

  test('no contexts and no invitations resolves unauthorized account',
      () async {
    final resolver = AuthenticatedAccessResolver(
      loadContexts: () async => const [],
      loadPlatformInvitations: () async => _response(profileId, const []),
      loadBusinessInvitations: () async =>
          _businessResponse(profileId, const []),
    );

    final result = await resolver.resolve(profileId);

    expect(result.outcome, AuthenticatedAccessOutcome.noAuthorizedAccess);
  });

  test('business invitation alone remains a valid private access path',
      () async {
    final resolver = AuthenticatedAccessResolver(
      loadContexts: () async => const [],
      loadPlatformInvitations: () async => _response(profileId, const []),
      loadBusinessInvitations: () async => _businessResponse(
        profileId,
        [_businessInvitation('member-invite-a')],
      ),
    );

    final result = await resolver.resolve(profileId);

    expect(result.outcome, AuthenticatedAccessOutcome.pendingInvitations);
    expect(result.pendingInvitations, isEmpty);
    expect(result.pendingBusinessInvitations.single.id, 'member-invite-a');
  });

  test('business invitation lookup failure preserves an existing context',
      () async {
    final resolver = AuthenticatedAccessResolver(
      loadContexts: () async => [_context(profileId)],
      loadPlatformInvitations: () async => _response(profileId, const []),
      loadBusinessInvitations: () async =>
          throw const BusinessAdministrationException(
        BusinessAdministrationFailureKind.network,
        'offline',
      ),
    );

    final result = await resolver.resolve(profileId);

    expect(result.outcome, AuthenticatedAccessOutcome.existingContexts);
    expect(result.businessInvitationsAvailable, isFalse);
    expect(result.isTransientFailure, isTrue);
  });

  test('platform and business invitations coexist without model confusion',
      () async {
    final resolver = AuthenticatedAccessResolver(
      loadContexts: () async => [_context(profileId)],
      loadPlatformInvitations: () async =>
          _response(profileId, [_invitation('platform-a')]),
      loadBusinessInvitations: () async => _businessResponse(
        profileId,
        [_businessInvitation('business-a')],
      ),
    );

    final result = await resolver.resolve(profileId);

    expect(
      result.outcome,
      AuthenticatedAccessOutcome.existingContextsAndPendingInvitations,
    );
    expect(result.pendingInvitations.single.invitationId, 'platform-a');
    expect(result.pendingBusinessInvitations.single.id, 'business-a');
  });
}

MyPlatformBusinessInvitationsResponse _response(
  String profileId,
  List<PlatformBusinessInvitation> invitations,
) {
  return MyPlatformBusinessInvitationsResponse(
    userId: profileId,
    invitations: invitations,
    generatedAt: DateTime.utc(2026, 8, 26),
  );
}

PlatformBusinessInvitation _invitation(String id) {
  return PlatformBusinessInvitation(
    invitationId: id,
    businessId: 'business-$id',
    branchId: 'branch-$id',
    businessName: 'Business $id',
    branchName: 'Principal',
    status: 'pending',
    expiresAt: DateTime.utc(2026, 9),
    isExpired: false,
    createdAt: DateTime.utc(2026, 8, 26),
  );
}

BusinessMemberInvitationsResponse _businessResponse(
  String profileId,
  List<BusinessMemberInvitation> invitations,
) {
  return BusinessMemberInvitationsResponse(
    userId: profileId,
    invitations: invitations,
    generatedAt: DateTime.utc(2026, 8, 28),
  );
}

BusinessMemberInvitation _businessInvitation(String id) {
  return BusinessMemberInvitation(
    id: id,
    businessId: 'business-$id',
    businessName: 'Business $id',
    email: 'user@example.com',
    roleId: 'role-a',
    roleName: 'cashier',
    branchId: 'branch-a',
    branchName: 'Principal',
    scope: BusinessMemberInvitationScope.branch,
    status: 'pending',
    deliveryStatus: BusinessMemberInvitationDeliveryState.sent,
    expiresAt: DateTime.utc(2099),
    isExpired: false,
  );
}

AuthorizedOperationalContext _context(String profileId) {
  return AuthorizedOperationalContext(
    profileId: profileId,
    businessId: 'business-a',
    businessName: 'Business A',
    businessStatus: 'active',
    businessUpdatedAt: DateTime.utc(2026, 8, 26),
    branchId: 'branch-a',
    branchName: 'Principal',
    branchStatus: 'active',
    branchUpdatedAt: DateTime.utc(2026, 8, 26),
    membershipIds: const ['membership-a'],
    membershipsUpdatedAt: DateTime.utc(2026, 8, 26),
    effectiveRoles: const [],
    effectivePermissions: const ['inventory.read'],
  );
}
