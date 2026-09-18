import '../../auth/application/authenticated_access_models.dart';
import 'operational_bootstrap_entry_models.dart';

typedef PostInvitationAccessRefresh = Future<AuthenticatedAccessResult>
    Function();
typedef PostInvitationEntryRunner = Future<OperationalBootstrapEntryResult>
    Function(OperationalContextSelection selection);

class PostInvitationBootstrapStabilizationResult {
  const PostInvitationBootstrapStabilizationResult({
    required this.access,
    required this.selection,
    required this.accessAttempts,
    required this.entryAttempts,
    this.entry,
  });

  final AuthenticatedAccessResult access;
  final OperationalContextSelection? selection;
  final int accessAttempts;
  final int entryAttempts;
  final OperationalBootstrapEntryResult? entry;
}

class PostInvitationBootstrapStabilizationService {
  const PostInvitationBootstrapStabilizationService({
    required PostInvitationAccessRefresh refreshAccess,
    required PostInvitationEntryRunner runEntry,
  })  : _refreshAccess = refreshAccess,
        _runEntry = runEntry;

  final PostInvitationAccessRefresh _refreshAccess;
  final PostInvitationEntryRunner _runEntry;

  Future<PostInvitationBootstrapStabilizationResult> stabilize({
    required String profileId,
    required String businessId,
    String? branchId,
  }) async {
    late AuthenticatedAccessResult access;
    var accessAttempts = 0;
    OperationalContextSelection? selection;
    for (var attempt = 0; attempt < 2; attempt += 1) {
      accessAttempts += 1;
      access = await _refreshAccess();
      selection = _selectionFromAccess(
        access,
        profileId: profileId,
        businessId: businessId,
        branchId: branchId,
      );
      if (selection != null ||
          _containsAcceptedContext(
            access,
            profileId: profileId,
            businessId: businessId,
            branchId: branchId,
          )) {
        break;
      }
      if (access.outcome == AuthenticatedAccessOutcome.failure &&
          !access.isTransientFailure) {
        break;
      }
    }

    if (selection == null) {
      return PostInvitationBootstrapStabilizationResult(
        access: access,
        selection: null,
        accessAttempts: accessAttempts,
        entryAttempts: 0,
      );
    }

    var entryAttempts = 1;
    var entry = await _runEntry(selection);
    if (entry.outcome == OperationalBootstrapEntryOutcome.transientFailure) {
      entryAttempts += 1;
      entry = await _runEntry(selection);
    }
    return PostInvitationBootstrapStabilizationResult(
      access: access,
      selection: selection,
      accessAttempts: accessAttempts,
      entryAttempts: entryAttempts,
      entry: entry,
    );
  }

  bool _containsAcceptedContext(
    AuthenticatedAccessResult access, {
    required String profileId,
    required String businessId,
    String? branchId,
  }) {
    return access.contexts.any(
      (context) =>
          context.profileId == profileId &&
          context.businessId == businessId &&
          (branchId == null || context.branchId == branchId),
    );
  }

  OperationalContextSelection? _selectionFromAccess(
    AuthenticatedAccessResult access, {
    required String profileId,
    required String businessId,
    String? branchId,
  }) {
    final contexts = access.contexts
        .where(
          (context) =>
              context.profileId == profileId &&
              context.businessId == businessId &&
              (branchId == null || context.branchId == branchId),
        )
        .toList(growable: false);
    if (contexts.length != 1) return null;
    return OperationalContextSelection(
      businessId: contexts.single.businessId,
      branchId: contexts.single.branchId,
    );
  }
}
