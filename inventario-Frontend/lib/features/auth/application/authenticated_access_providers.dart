import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../administration/application/business_administration_providers.dart';
import '../../administration/data/models/business_administration_models.dart';
import '../../sync/application/authorized_operational_context_providers.dart';
import '../data/datasources/platform_business_invitation_remote_datasource.dart';
import '../data/models/platform_business_invitation_models.dart';
import 'authenticated_access_models.dart';
import 'authenticated_access_resolver.dart';

final platformBusinessInvitationRemoteDataSourceProvider =
    Provider<PlatformBusinessInvitationRemoteDataSource>((ref) {
  return PlatformBusinessInvitationRemoteDataSource(
    ref.watch(supabaseClientProvider),
  );
});

final authenticatedAccessResolverServiceProvider =
    Provider<AuthenticatedAccessResolver>((ref) {
  return AuthenticatedAccessResolver(
    loadContexts: ref
        .watch(authorizedOperationalContextServiceProvider)
        .listAuthorizedContexts,
    loadPlatformInvitations:
        ref.watch(platformBusinessInvitationRemoteDataSourceProvider).listMine,
    loadBusinessInvitations:
        ref.watch(businessAdministrationServiceProvider).listMyInvitations,
  );
});

final authenticatedAccessResolverProvider =
    FutureProvider.family<AuthenticatedAccessResult, String>(
        (ref, profileId) async {
  final currentProfileId = ref.watch(currentSupabaseUserProvider)?.id;
  if (currentProfileId != profileId) {
    return const AuthenticatedAccessResult(
      outcome: AuthenticatedAccessOutcome.failure,
      contexts: [],
      pendingInvitations: [],
      message: 'La sesión cambió durante la resolución de acceso.',
      invitationsAvailable: false,
    );
  }
  return ref
      .watch(authenticatedAccessResolverServiceProvider)
      .resolve(profileId);
});

typedef PlatformInvitationAcceptor = Future<AcceptedPlatformBusinessInvitation>
    Function(String invitationId);

final platformInvitationAcceptorProvider =
    Provider<PlatformInvitationAcceptor>((ref) {
  return ref.watch(platformBusinessInvitationRemoteDataSourceProvider).accept;
});

typedef BusinessInvitationAcceptor = Future<AcceptedBusinessMemberInvitation>
    Function(String invitationId);

final businessInvitationAcceptorProvider =
    Provider<BusinessInvitationAcceptor>((ref) {
  return ref.watch(businessAdministrationServiceProvider).acceptInvitation;
});
