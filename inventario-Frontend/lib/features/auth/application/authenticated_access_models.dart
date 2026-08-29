import '../../sync/data/models/authorized_operational_context_models.dart';
import '../../administration/data/models/business_administration_models.dart';
import '../data/models/platform_business_invitation_models.dart';

enum AuthenticatedAccessOutcome {
  existingContexts,
  pendingInvitations,
  existingContextsAndPendingInvitations,
  noAuthorizedAccess,
  failure,
}

class AuthenticatedAccessResult {
  const AuthenticatedAccessResult({
    required this.outcome,
    required this.contexts,
    required this.pendingInvitations,
    required this.message,
    this.pendingBusinessInvitations = const [],
    this.isTransientFailure = false,
    this.invitationsAvailable = true,
    this.platformInvitationsAvailable = true,
    this.businessInvitationsAvailable = true,
  });

  final AuthenticatedAccessOutcome outcome;
  final List<AuthorizedOperationalContext> contexts;
  final List<PlatformBusinessInvitation> pendingInvitations;
  final List<BusinessMemberInvitation> pendingBusinessInvitations;
  final String message;
  final bool isTransientFailure;
  final bool invitationsAvailable;
  final bool platformInvitationsAvailable;
  final bool businessInvitationsAvailable;

  bool get hasContexts => contexts.isNotEmpty;
  bool get hasPendingInvitations =>
      pendingInvitations.isNotEmpty || pendingBusinessInvitations.isNotEmpty;
}
