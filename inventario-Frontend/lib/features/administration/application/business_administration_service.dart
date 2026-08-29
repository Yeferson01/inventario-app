import '../data/datasources/business_administration_remote_datasource.dart';
import '../data/models/business_administration_models.dart';

class BusinessAdministrationService {
  const BusinessAdministrationService(this._remote);

  final BusinessAdministrationRemoteDatasource _remote;

  Future<List<BusinessBranchSummary>> listBranches(String businessId) =>
      _remote.listBranches(businessId);

  Future<BusinessBranchCreationResult> createBranch(
    CreateBusinessBranchRequest request, {
    required String idempotencyKey,
  }) =>
      _remote.createBranch(request, idempotencyKey: idempotencyKey);

  Future<BusinessMemberInvitationOptions> listInvitationOptions(
    String businessId,
  ) =>
      _remote.listInvitationOptions(businessId);

  Future<AdminBusinessMemberInvitationsResponse> listBusinessInvitations(
    String businessId,
  ) =>
      _remote.listBusinessInvitations(businessId);

  Future<BusinessMemberInvitationsResponse> listMyInvitations() =>
      _remote.listMyInvitations();

  Future<IssueBusinessMemberInvitationResult> issueInvitation(
    IssueBusinessMemberInvitationRequest request, {
    required String idempotencyKey,
  }) =>
      _remote.issueInvitation(request, idempotencyKey: idempotencyKey);

  Future<AcceptedBusinessMemberInvitation> acceptInvitation(
    String invitationId,
  ) =>
      _remote.acceptInvitation(invitationId);

  Future<BusinessMemberInvitation> revokeInvitation(
    String invitationId, {
    String? reason,
  }) =>
      _remote.revokeInvitation(invitationId, reason: reason);
}
