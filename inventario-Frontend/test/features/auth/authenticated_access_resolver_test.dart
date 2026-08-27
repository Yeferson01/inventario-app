import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_models.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_resolver.dart';
import 'package:inventario_frontend/features/auth/data/datasources/platform_business_invitation_remote_datasource.dart';
import 'package:inventario_frontend/features/auth/data/models/platform_business_invitation_models.dart';
import 'package:inventario_frontend/features/sync/data/models/authorized_operational_context_models.dart';

void main() {
  const profileId = 'profile-a';

  test('no contexts plus pending invitations resolves private onboarding',
      () async {
    final resolver = AuthenticatedAccessResolver(
      loadContexts: () async => const [],
      loadInvitations: () async => _response(
        profileId,
        [_invitation('invite-a'), _invitation('invite-b')],
      ),
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
      loadInvitations: () async => _response(
        profileId,
        [_invitation('invite-b')],
      ),
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
      loadInvitations: () async => throw const PlatformInvitationException(
        kind: PlatformInvitationFailureKind.network,
        message: 'offline',
      ),
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
      loadInvitations: () async => _response(profileId, const []),
    );

    final result = await resolver.resolve(profileId);

    expect(result.outcome, AuthenticatedAccessOutcome.noAuthorizedAccess);
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
