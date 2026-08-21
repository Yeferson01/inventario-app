import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/authorized_operational_context_remote_datasource.dart';
import 'app_installation_id_store.dart';
import 'authorized_operational_context_service.dart';
import 'local_sync_outbox_providers.dart';
import 'operational_bootstrap_entry_models.dart';
import 'operational_bootstrap_entry_service.dart';
import 'operational_bootstrap_orchestration_models.dart';
import 'operational_bootstrap_providers.dart';

final authorizedOperationalContextRemoteDataSourceProvider =
    Provider<AuthorizedOperationalContextRemoteDataSource>((ref) {
  return AuthorizedOperationalContextRemoteDataSource(
    ref.watch(supabaseClientProvider),
  );
});

final authorizedOperationalContextServiceProvider =
    Provider<AuthorizedOperationalContextService>((ref) {
  return AuthorizedOperationalContextService(
    remoteDataSource:
        ref.watch(authorizedOperationalContextRemoteDataSourceProvider),
    authenticatedProfileId: () => ref.read(currentSupabaseUserProvider)?.id,
  );
});

final operationalBootstrapEntryServiceProvider =
    Provider<OperationalBootstrapEntryService>((ref) {
  final selectedStore = ref.watch(appSelectedSyncContextStoreProvider);
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

    final packageInfo = await PackageInfo.fromPlatform();
    return ref.watch(operationalBootstrapEntryRunnerProvider)(
      OperationalBootstrapEntryRequest(
        mode: OperationalBootstrapMode.recovery,
        selection: request.selection,
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
