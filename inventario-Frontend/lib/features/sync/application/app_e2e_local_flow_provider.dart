import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_e2e_local_flow_models.dart';
import 'app_e2e_local_flow_service.dart';
import 'app_router_sync_bootstrap_provider.dart';
import 'local_sync_outbox_providers.dart';

final appE2ELocalFlowServiceProvider = Provider<AppE2ELocalFlowService>((ref) {
  return AppE2ELocalFlowService(
    businessSelectionService: ref.watch(appBusinessSelectionServiceProvider),
    appContextService: ref.watch(appContextServiceProvider),
    syncCoordinatorService: ref.watch(appSyncCoordinatorServiceProvider),
    installationIdStore: ref.watch(appInstallationIdStoreProvider),
  );
});

final appE2ELocalFlowResultProvider =
    FutureProvider.family<AppE2ELocalFlowResult, AppE2ELocalFlowInput>(
  (ref, input) async {
    final service = ref.watch(appE2ELocalFlowServiceProvider);

    return service.run(input);
  },
);
