import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import 'app_installation_id_store.dart';
import 'app_sync_coordinator_models.dart';
import 'local_sync_outbox_providers.dart';

class AppRouterSyncBootstrapData {
  const AppRouterSyncBootstrapData({
    required this.hasAuthenticatedUser,
    this.input,
  });

  final bool hasAuthenticatedUser;
  final AppSyncCoordinatorInput? input;

  bool get canRunShellSync {
    return hasAuthenticatedUser && input != null;
  }
}

final appInstallationIdStoreProvider = Provider<AppInstallationIdStore>((ref) {
  return AppInstallationIdStore();
});

final appRouterSyncBootstrapProvider =
    FutureProvider<AppRouterSyncBootstrapData>((ref) async {
  final supabase = ref.watch(supabaseClientProvider);
  final user = supabase.auth.currentUser;

  if (user == null) {
    return const AppRouterSyncBootstrapData(
      hasAuthenticatedUser: false,
    );
  }

  final selectedContextStore = ref.watch(appSelectedSyncContextStoreProvider);
  final selectedContext = await selectedContextStore.getSelectedContext();

  if (selectedContext == null) {
    return const AppRouterSyncBootstrapData(
      hasAuthenticatedUser: true,
    );
  }

  final installationIdStore = ref.watch(appInstallationIdStoreProvider);
  final installationId = await installationIdStore.getOrCreateInstallationId();

  final isOnline = await _isCurrentlyOnline();
  final packageInfo = await PackageInfo.fromPlatform();

  final input = AppSyncCoordinatorInput(
    businessId: selectedContext.businessId,
    branchId: selectedContext.branchId,
    profileId: selectedContext.profileId ?? user.id,
    installationId: installationId,
    isOnline: isOnline,
    deviceName: _deviceName(),
    platform: defaultTargetPlatform.name,
    appVersion: packageInfo.version,
    osVersion: null,
    metadata: const {
      'source': 'router_shell_bootstrap',
    },
  );

  return AppRouterSyncBootstrapData(
    hasAuthenticatedUser: true,
    input: input,
  );
});

Future<bool> _isCurrentlyOnline() async {
  final result = await Connectivity().checkConnectivity();

  return result.any((item) => item != ConnectivityResult.none);
}

String _deviceName() {
  if (kIsWeb) {
    return 'Web';
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return 'Android device';
    case TargetPlatform.iOS:
      return 'iOS device';
    case TargetPlatform.macOS:
      return 'macOS device';
    case TargetPlatform.windows:
      return 'Windows device';
    case TargetPlatform.linux:
      return 'Linux device';
    case TargetPlatform.fuchsia:
      return 'Fuchsia device';
  }
}
