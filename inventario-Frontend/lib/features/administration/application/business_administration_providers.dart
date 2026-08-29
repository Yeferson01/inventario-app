import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/device_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../sync/application/app_context_models.dart';
import '../../sync/application/app_current_context_provider.dart';
import '../data/datasources/business_administration_remote_datasource.dart';
import '../data/models/business_administration_models.dart';
import 'business_administration_service.dart';
import 'business_administration_submission_controllers.dart';

final businessAdministrationRemoteDatasourceProvider =
    Provider<BusinessAdministrationRemoteDatasource>((ref) {
  return BusinessAdministrationRemoteDatasource(
    ref.watch(supabaseClientProvider),
  );
});

final businessAdministrationServiceProvider =
    Provider<BusinessAdministrationService>((ref) {
  return BusinessAdministrationService(
    ref.watch(businessAdministrationRemoteDatasourceProvider),
  );
});

final branchCreationControllerProvider =
    Provider.autoDispose<BranchCreationController>((ref) {
  return BranchCreationController(
      ref.watch(businessAdministrationServiceProvider));
});

final businessInvitationIssueControllerProvider =
    Provider.autoDispose<BusinessInvitationIssueController>((ref) {
  return BusinessInvitationIssueController(
    ref.watch(businessAdministrationServiceProvider),
  );
});

final administrationCurrentContextProvider =
    FutureProvider.autoDispose<AppCurrentContext?>((ref) async {
  final installationId = await ref.watch(installationIdProvider.future);
  return ref.watch(
    appCurrentContextProvider(
      AppCurrentContextRequest(installationId: installationId, isOnline: true),
    ).future,
  );
});

enum BusinessBranchAdministrationAvailabilityKind {
  notApplicable,
  available,
  unauthorizedScope,
  retryableFailure,
}

class BusinessBranchAdministrationAvailability {
  const BusinessBranchAdministrationAvailability._({
    required this.kind,
    this.branches = const [],
  });

  const BusinessBranchAdministrationAvailability.notApplicable()
      : this._(
          kind: BusinessBranchAdministrationAvailabilityKind.notApplicable,
        );

  const BusinessBranchAdministrationAvailability.available(
    List<BusinessBranchSummary> branches,
  ) : this._(
          kind: BusinessBranchAdministrationAvailabilityKind.available,
          branches: branches,
        );

  const BusinessBranchAdministrationAvailability.unauthorizedScope()
      : this._(
          kind: BusinessBranchAdministrationAvailabilityKind.unauthorizedScope,
        );

  const BusinessBranchAdministrationAvailability.retryableFailure()
      : this._(
          kind: BusinessBranchAdministrationAvailabilityKind.retryableFailure,
        );

  final BusinessBranchAdministrationAvailabilityKind kind;
  final List<BusinessBranchSummary> branches;
}

class BusinessBranchAdministrationRequest {
  const BusinessBranchAdministrationRequest({
    required this.profileId,
    required this.businessId,
    required this.hasLocalSettingsBranches,
  });

  factory BusinessBranchAdministrationRequest.fromContext(
    AppCurrentContext context,
  ) {
    return BusinessBranchAdministrationRequest(
      profileId: context.profileId ?? '',
      businessId: context.businessId,
      hasLocalSettingsBranches: context.hasPermission('settings.branches'),
    );
  }

  final String profileId;
  final String businessId;
  final bool hasLocalSettingsBranches;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is BusinessBranchAdministrationRequest &&
            runtimeType == other.runtimeType &&
            profileId == other.profileId &&
            businessId == other.businessId &&
            hasLocalSettingsBranches == other.hasLocalSettingsBranches;
  }

  @override
  int get hashCode => Object.hash(
        profileId,
        businessId,
        hasLocalSettingsBranches,
      );
}

final businessBranchAdministrationProvider = FutureProvider.family<
    BusinessBranchAdministrationAvailability,
    BusinessBranchAdministrationRequest>((ref, request) async {
  final currentProfileId = ref.watch(currentSupabaseUserProvider)?.id;
  if (!request.hasLocalSettingsBranches ||
      request.profileId.isEmpty ||
      currentProfileId != request.profileId) {
    return const BusinessBranchAdministrationAvailability.notApplicable();
  }

  try {
    final branches = await ref
        .watch(businessAdministrationServiceProvider)
        .listBranches(request.businessId);
    return BusinessBranchAdministrationAvailability.available(branches);
  } on BusinessAdministrationException catch (error) {
    if (error.kind == BusinessAdministrationFailureKind.unauthorized) {
      return const BusinessBranchAdministrationAvailability.unauthorizedScope();
    }
    return const BusinessBranchAdministrationAvailability.retryableFailure();
  } catch (_) {
    return const BusinessBranchAdministrationAvailability.retryableFailure();
  }
});

final businessInvitationOptionsProvider = FutureProvider.autoDispose
    .family<BusinessMemberInvitationOptions, String>((ref, businessId) async {
  ref.watch(currentSupabaseUserProvider);
  return ref
      .watch(businessAdministrationServiceProvider)
      .listInvitationOptions(businessId);
});

final adminBusinessInvitationsProvider = FutureProvider.autoDispose
    .family<AdminBusinessMemberInvitationsResponse, String>(
        (ref, businessId) async {
  ref.watch(currentSupabaseUserProvider);
  return ref
      .watch(businessAdministrationServiceProvider)
      .listBusinessInvitations(businessId);
});

final myBusinessMemberInvitationsProvider = FutureProvider.autoDispose
    .family<BusinessMemberInvitationsResponse, String>((ref, profileId) async {
  final currentProfileId = ref.watch(currentSupabaseUserProvider)?.id;
  if (currentProfileId == null || currentProfileId != profileId) {
    throw const BusinessAdministrationException(
      BusinessAdministrationFailureKind.unauthorized,
      'La sesión cambió. Vuelve a iniciar sesión.',
    );
  }
  final result = await ref
      .watch(businessAdministrationServiceProvider)
      .listMyInvitations();
  if (result.userId != profileId) {
    throw const BusinessAdministrationException(
      BusinessAdministrationFailureKind.unauthorized,
      'La respuesta no corresponde a la sesión activa.',
    );
  }
  return result;
});
