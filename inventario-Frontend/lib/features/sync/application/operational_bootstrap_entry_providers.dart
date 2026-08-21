import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/authorized_operational_context_remote_datasource.dart';
import 'app_installation_id_store.dart';
import 'authorized_operational_context_service.dart';
import 'local_sync_outbox_providers.dart';
import 'operational_bootstrap_entry_models.dart';
import 'operational_bootstrap_entry_service.dart';
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
