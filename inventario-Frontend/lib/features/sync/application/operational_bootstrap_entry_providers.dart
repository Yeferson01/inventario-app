import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../../cash/application/cash_session_local_provider.dart';
import '../../auth/application/authenticated_access_models.dart';
import '../../auth/application/authenticated_access_providers.dart';
import 'app_installation_id_store.dart';
import 'authorized_operational_context_providers.dart';
import 'cash_repair_context_service.dart';
import 'local_sync_outbox_providers.dart';
import 'operational_bootstrap_entry_models.dart';
import 'operational_bootstrap_entry_service.dart';
import 'operational_bootstrap_orchestration_models.dart';
import 'operational_bootstrap_providers.dart';
import '../data/models/authorized_operational_context_models.dart';

class ProductiveOperationalSelectionIntent {
  const ProductiveOperationalSelectionIntent({
    required this.profileId,
    required this.businessId,
    required this.branchId,
  });

  final String profileId;
  final String businessId;
  final String branchId;

  OperationalContextSelection get selection => OperationalContextSelection(
        businessId: businessId,
        branchId: branchId,
      );
}

class ProductiveOperationalSelectionIntentNotifier
    extends Notifier<ProductiveOperationalSelectionIntent?> {
  @override
  ProductiveOperationalSelectionIntent? build() => null;

  bool requestSwitch({
    required String currentProfileId,
    required String currentBusinessId,
    required AuthorizedOperationalContext target,
  }) {
    if (target.profileId != currentProfileId ||
        target.businessId != currentBusinessId) {
      return false;
    }

    state = ProductiveOperationalSelectionIntent(
      profileId: target.profileId,
      businessId: target.businessId,
      branchId: target.branchId,
    );
    return true;
  }
}

final productiveOperationalSelectionIntentProvider = NotifierProvider<
    ProductiveOperationalSelectionIntentNotifier,
    ProductiveOperationalSelectionIntent?>(
  ProductiveOperationalSelectionIntentNotifier.new,
);

List<AuthorizedOperationalContext> scopedOperationalBranchContexts({
  required Iterable<AuthorizedOperationalContext> contexts,
  required String profileId,
  required String businessId,
}) {
  final byBranchId = <String, AuthorizedOperationalContext>{};
  for (final context in contexts) {
    if (context.profileId != profileId ||
        context.businessId != businessId ||
        context.businessStatus != 'active' ||
        context.branchStatus != 'active') {
      continue;
    }
    byBranchId[context.branchId] = context;
  }

  final result = byBranchId.values.toList(growable: false)
    ..sort((left, right) => left.branchName.compareTo(right.branchName));
  return List<AuthorizedOperationalContext>.unmodifiable(result);
}

final operationalBootstrapEntryServiceProvider =
    Provider<OperationalBootstrapEntryService>((ref) {
  final selectedStore = ref.watch(appSelectedSyncContextStoreProvider);
  final runtimeStore = ref.watch(appRuntimeContextStoreProvider);
  final installationStore = AppInstallationIdStore();
  return OperationalBootstrapEntryService(
    authenticatedProfileId: () => ref.read(currentSupabaseUserProvider)?.id,
    discover: ref
        .watch(authorizedOperationalContextServiceProvider)
        .listAuthorizedContexts,
    installationId: installationStore.getOrCreateInstallationId,
    registerDevice: ref
        .watch(runtimeSetupRemoteDataSourceProvider)
        .registerOrUpdateAppDevice,
    resolveRuntime: ref.watch(runtimeResolutionServiceProvider).resolve,
    bootstrap: ref.watch(operationalBootstrapServiceProvider).run,
    readSelectedContext: (profileId) =>
        selectedStore.getSelectedContext(profileId: profileId),
    writeSelectedContext: selectedStore.saveSelectedContext,
    clearSelectedContext: (profileId) =>
        selectedStore.clearSelectedContext(profileId: profileId),
    writeRuntimeContext: runtimeStore.saveContext,
  );
});

typedef OperationalBootstrapEntryRunner
    = Future<OperationalBootstrapEntryResult> Function(
  OperationalBootstrapEntryRequest request,
);

final operationalBootstrapEntryRunnerProvider =
    Provider<OperationalBootstrapEntryRunner>((ref) {
  return ref.watch(operationalBootstrapEntryServiceProvider).run;
});

final cashRepairContextServiceProvider = Provider<CashRepairContextService>((
  ref,
) {
  final cashSessionService = ref.watch(cashSessionLocalServiceProvider);
  final issueDao = ref.watch(reconciliationIssueLocalDaoProvider);
  return CashRepairContextService(
    authenticatedProfileId: () => ref.read(currentSupabaseUserProvider)?.id,
    resolveRuntime: ref.watch(runtimeResolutionServiceProvider).resolve,
    recoverCash: (request) =>
        ref.watch(cashPosRecoveryServiceProvider).recover(request),
    loadOpenBlockingIssues:
        ref.watch(reconciliationIssueLocalDaoProvider).getOpenBlockingIssues,
    loadOpenSessions: ref
        .watch(cashPosReconciliationLocalDaoProvider)
        .openSessionsForRegister,
    writeRuntimeContext: ref.watch(appRuntimeContextStoreProvider).saveContext,
    convergeCashSessions: ({
      required businessId,
      required branchId,
      required cashRegisterId,
      required authoritativeOpenCashSessionId,
    }) async {
      await cashSessionService.convergeAuthoritativeOpenSession(
        businessId: businessId,
        branchId: branchId,
        cashRegisterId: cashRegisterId,
        authoritativeOpenCashSessionId: authoritativeOpenCashSessionId,
      );
    },
    resolveOpenSessionConflict: ({
      required profileId,
      required businessId,
      required branchId,
      required cashSessionId,
    }) =>
        issueDao.resolveOpenIssue(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
      domain: 'cash_pos',
      issueType: 'cash_open_session_conflict',
      entityType: 'cash_sessions',
      entityId: cashSessionId,
    ),
  );
});

class ProductiveOperationalEntryRequest {
  const ProductiveOperationalEntryRequest({
    required this.profileId,
    this.selection,
  });

  final String profileId;
  final OperationalContextSelection? selection;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ProductiveOperationalEntryRequest &&
            profileId == other.profileId &&
            selection?.businessId == other.selection?.businessId &&
            selection?.branchId == other.selection?.branchId;
  }

  @override
  int get hashCode => Object.hash(
        profileId,
        selection?.businessId,
        selection?.branchId,
      );
}

final productiveOperationalEntryProvider = FutureProvider.family<
    OperationalBootstrapEntryResult, ProductiveOperationalEntryRequest>(
  (ref, request) async {
    final authenticatedProfileId = ref.watch(currentSupabaseUserProvider)?.id;
    if (authenticatedProfileId != request.profileId) {
      return const OperationalBootstrapEntryResult(
        outcome: OperationalBootstrapEntryOutcome.authorizationRevoked,
        contexts: [],
        message: 'The authenticated profile changed during operational entry.',
        offlineReady: false,
        canRequestAdministrativeSetup: false,
      );
    }

    final access = await ref.watch(
      authenticatedAccessResolverProvider(request.profileId).future,
    );
    if (access.outcome == AuthenticatedAccessOutcome.failure) {
      return OperationalBootstrapEntryResult(
        outcome: access.isTransientFailure
            ? OperationalBootstrapEntryOutcome.transientFailure
            : OperationalBootstrapEntryOutcome.failed,
        contexts: access.contexts,
        profileId: request.profileId,
        message: access.message,
        offlineReady: false,
        canRequestAdministrativeSetup: false,
      );
    }

    final packageInfo = await PackageInfo.fromPlatform();
    return ref.watch(operationalBootstrapEntryRunnerProvider)(
      OperationalBootstrapEntryRequest(
        mode: OperationalBootstrapMode.recovery,
        selection: request.selection,
        discoveredContexts: access.contexts,
        deviceName: _productiveDeviceName(),
        platform: defaultTargetPlatform.name,
        appVersion: packageInfo.version,
        metadata: const {
          'source': 'productive_operational_entry',
        },
      ),
    );
  },
);

final productiveCachedContextAvailabilityProvider =
    FutureProvider.family<bool, String>((ref, profileId) async {
  final authenticatedProfileId = ref.watch(currentSupabaseUserProvider)?.id;
  if (authenticatedProfileId != profileId) {
    return false;
  }

  final selected = await ref
      .watch(appSelectedSyncContextStoreProvider)
      .getSelectedContext(profileId: profileId);
  final branchId = selected?.branchId;
  if (selected == null || branchId == null || branchId.trim().isEmpty) {
    return false;
  }

  final projection = await ref
      .watch(authorizedOperationalContextLocalDaoProvider)
      .getContextRecord(
        profileId: profileId,
        businessId: selected.businessId,
        branchId: branchId,
      );

  return projection?.isActive == true;
});

String _productiveDeviceName() {
  if (kIsWeb) {
    return 'Web';
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android device',
    TargetPlatform.iOS => 'iOS device',
    TargetPlatform.macOS => 'macOS device',
    TargetPlatform.windows => 'Windows device',
    TargetPlatform.linux => 'Linux device',
    TargetPlatform.fuchsia => 'Fuchsia device',
  };
}
