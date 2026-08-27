import '../../sync/data/models/authorized_operational_context_models.dart';
import '../../sync/data/models/operational_integration_failure.dart';
import '../data/datasources/platform_business_invitation_remote_datasource.dart';
import '../data/models/platform_business_invitation_models.dart';
import 'authenticated_access_models.dart';

typedef AuthorizedContextsLoader = Future<List<AuthorizedOperationalContext>>
    Function();
typedef PlatformInvitationsLoader
    = Future<MyPlatformBusinessInvitationsResponse> Function();

class AuthenticatedAccessResolver {
  const AuthenticatedAccessResolver({
    required AuthorizedContextsLoader loadContexts,
    required PlatformInvitationsLoader loadInvitations,
  })  : _loadContexts = loadContexts,
        _loadInvitations = loadInvitations;

  final AuthorizedContextsLoader _loadContexts;
  final PlatformInvitationsLoader _loadInvitations;

  Future<AuthenticatedAccessResult> resolve(String profileId) async {
    List<AuthorizedOperationalContext> contexts;
    try {
      contexts = await _loadContexts();
    } on OperationalIntegrationException catch (error) {
      return AuthenticatedAccessResult(
        outcome: AuthenticatedAccessOutcome.failure,
        contexts: const [],
        pendingInvitations: const [],
        message: error.message,
        isTransientFailure:
            error.kind == OperationalIntegrationFailureKind.networkTransient,
        invitationsAvailable: false,
      );
    } catch (_) {
      return const AuthenticatedAccessResult(
        outcome: AuthenticatedAccessOutcome.failure,
        contexts: [],
        pendingInvitations: [],
        message: 'No se pudo resolver el acceso operacional.',
        invitationsAvailable: false,
      );
    }

    MyPlatformBusinessInvitationsResponse invitationResponse;
    try {
      invitationResponse = await _loadInvitations();
    } on PlatformInvitationException catch (error) {
      if (contexts.isNotEmpty) {
        return AuthenticatedAccessResult(
          outcome: AuthenticatedAccessOutcome.existingContexts,
          contexts: List.unmodifiable(contexts),
          pendingInvitations: const [],
          message:
              'El contexto operativo sigue disponible; las invitaciones no pudieron actualizarse.',
          isTransientFailure:
              error.kind == PlatformInvitationFailureKind.network,
          invitationsAvailable: false,
        );
      }
      return AuthenticatedAccessResult(
        outcome: AuthenticatedAccessOutcome.failure,
        contexts: const [],
        pendingInvitations: const [],
        message: error.message,
        isTransientFailure: error.kind == PlatformInvitationFailureKind.network,
        invitationsAvailable: false,
      );
    } catch (_) {
      return AuthenticatedAccessResult(
        outcome: contexts.isEmpty
            ? AuthenticatedAccessOutcome.failure
            : AuthenticatedAccessOutcome.existingContexts,
        contexts: List.unmodifiable(contexts),
        pendingInvitations: const [],
        message: contexts.isEmpty
            ? 'No se pudo resolver el acceso privado.'
            : 'El contexto operativo sigue disponible; las invitaciones no pudieron actualizarse.',
        invitationsAvailable: false,
      );
    }

    if (invitationResponse.userId != profileId) {
      return const AuthenticatedAccessResult(
        outcome: AuthenticatedAccessOutcome.failure,
        contexts: [],
        pendingInvitations: [],
        message: 'La respuesta de invitaciones no corresponde a la sesión.',
        invitationsAvailable: false,
      );
    }

    final pending = invitationResponse.invitations
        .where((invitation) => invitation.isPending)
        .toList(growable: false);
    final outcome = contexts.isNotEmpty
        ? pending.isNotEmpty
            ? AuthenticatedAccessOutcome.existingContextsAndPendingInvitations
            : AuthenticatedAccessOutcome.existingContexts
        : pending.isNotEmpty
            ? AuthenticatedAccessOutcome.pendingInvitations
            : AuthenticatedAccessOutcome.noAuthorizedAccess;

    return AuthenticatedAccessResult(
      outcome: outcome,
      contexts: List.unmodifiable(contexts),
      pendingInvitations: List.unmodifiable(pending),
      message: switch (outcome) {
        AuthenticatedAccessOutcome.existingContexts =>
          'La cuenta tiene contextos operacionales autorizados.',
        AuthenticatedAccessOutcome.pendingInvitations =>
          'La cuenta tiene invitaciones privadas pendientes.',
        AuthenticatedAccessOutcome.existingContextsAndPendingInvitations =>
          'La cuenta tiene contextos e invitaciones privadas pendientes.',
        AuthenticatedAccessOutcome.noAuthorizedAccess =>
          'La cuenta no tiene acceso operacional autorizado.',
        AuthenticatedAccessOutcome.failure =>
          'No se pudo resolver el acceso privado.',
      },
    );
  }
}
