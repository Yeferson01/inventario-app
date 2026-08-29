import '../../administration/data/datasources/business_administration_remote_datasource.dart';
import '../../administration/data/models/business_administration_models.dart';
import '../../sync/data/models/authorized_operational_context_models.dart';
import '../../sync/data/models/operational_integration_failure.dart';
import '../data/datasources/platform_business_invitation_remote_datasource.dart';
import '../data/models/platform_business_invitation_models.dart';
import 'authenticated_access_models.dart';

typedef AuthorizedContextsLoader = Future<List<AuthorizedOperationalContext>>
    Function();
typedef PlatformInvitationsLoader
    = Future<MyPlatformBusinessInvitationsResponse> Function();
typedef BusinessInvitationsLoader = Future<BusinessMemberInvitationsResponse>
    Function();

class AuthenticatedAccessResolver {
  const AuthenticatedAccessResolver({
    required AuthorizedContextsLoader loadContexts,
    required PlatformInvitationsLoader loadPlatformInvitations,
    required BusinessInvitationsLoader loadBusinessInvitations,
  })  : _loadContexts = loadContexts,
        _loadPlatformInvitations = loadPlatformInvitations,
        _loadBusinessInvitations = loadBusinessInvitations;

  final AuthorizedContextsLoader _loadContexts;
  final PlatformInvitationsLoader _loadPlatformInvitations;
  final BusinessInvitationsLoader _loadBusinessInvitations;

  Future<AuthenticatedAccessResult> resolve(String profileId) async {
    List<AuthorizedOperationalContext> contexts;
    try {
      contexts = await _loadContexts();
    } on OperationalIntegrationException catch (error) {
      return _failure(
        error.message,
        transient:
            error.kind == OperationalIntegrationFailureKind.networkTransient,
      );
    } catch (_) {
      return _failure('No se pudo resolver el acceso operacional.');
    }

    var platformAvailable = true;
    var businessAvailable = true;
    var transient = false;
    List<PlatformBusinessInvitation> platformPending = const [];
    List<BusinessMemberInvitation> businessPending = const [];

    try {
      final response = await _loadPlatformInvitations();
      if (response.userId != profileId) {
        return _failure(
          'La respuesta de invitaciones no corresponde a la sesión.',
        );
      }
      platformPending = response.invitations
          .where((invitation) => invitation.isPending)
          .toList(growable: false);
    } on PlatformInvitationException catch (error) {
      platformAvailable = false;
      transient = error.kind == PlatformInvitationFailureKind.network;
    } catch (_) {
      platformAvailable = false;
    }

    try {
      final response = await _loadBusinessInvitations();
      if (response.userId != profileId) {
        return _failure(
          'La respuesta de invitaciones de negocio no corresponde a la sesión.',
        );
      }
      businessPending = response.invitations
          .where((invitation) => invitation.isPending)
          .toList(growable: false);
    } on BusinessAdministrationException catch (error) {
      businessAvailable = false;
      transient =
          transient || error.kind == BusinessAdministrationFailureKind.network;
    } catch (_) {
      businessAvailable = false;
    }

    final hasContexts = contexts.isNotEmpty;
    final hasInvitations =
        platformPending.isNotEmpty || businessPending.isNotEmpty;
    if (!hasContexts &&
        !hasInvitations &&
        (!platformAvailable || !businessAvailable)) {
      return AuthenticatedAccessResult(
        outcome: AuthenticatedAccessOutcome.failure,
        contexts: const [],
        pendingInvitations: const [],
        message: 'No se pudo comprobar completamente el acceso privado.',
        isTransientFailure: transient,
        invitationsAvailable: false,
        platformInvitationsAvailable: platformAvailable,
        businessInvitationsAvailable: businessAvailable,
      );
    }

    final outcome = hasContexts
        ? hasInvitations
            ? AuthenticatedAccessOutcome.existingContextsAndPendingInvitations
            : AuthenticatedAccessOutcome.existingContexts
        : hasInvitations
            ? AuthenticatedAccessOutcome.pendingInvitations
            : AuthenticatedAccessOutcome.noAuthorizedAccess;
    final allInvitationsAvailable = platformAvailable && businessAvailable;
    return AuthenticatedAccessResult(
      outcome: outcome,
      contexts: List.unmodifiable(contexts),
      pendingInvitations: List.unmodifiable(platformPending),
      pendingBusinessInvitations: List.unmodifiable(businessPending),
      message: allInvitationsAvailable
          ? _messageFor(outcome)
          : 'El acceso disponible se conserva; algunas invitaciones no pudieron actualizarse.',
      isTransientFailure: transient,
      invitationsAvailable: allInvitationsAvailable,
      platformInvitationsAvailable: platformAvailable,
      businessInvitationsAvailable: businessAvailable,
    );
  }

  AuthenticatedAccessResult _failure(
    String message, {
    bool transient = false,
  }) {
    return AuthenticatedAccessResult(
      outcome: AuthenticatedAccessOutcome.failure,
      contexts: const [],
      pendingInvitations: const [],
      message: message,
      isTransientFailure: transient,
      invitationsAvailable: false,
      platformInvitationsAvailable: false,
      businessInvitationsAvailable: false,
    );
  }

  String _messageFor(AuthenticatedAccessOutcome outcome) {
    return switch (outcome) {
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
    };
  }
}
