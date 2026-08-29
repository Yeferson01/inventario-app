import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../administration/application/business_administration_providers.dart';
import '../../sync/application/app_current_context_provider.dart';
import '../../sync/application/app_router_sync_bootstrap_provider.dart';
import '../../sync/application/operational_bootstrap_entry_providers.dart';
import 'authenticated_access_providers.dart';
import 'productive_auth_service.dart';

enum ProductiveAuthPhase {
  initializing,
  unauthenticated,
  authenticated,
  passwordSetupRequired,
}

class ProductiveAuthSessionState {
  const ProductiveAuthSessionState({
    required this.phase,
    this.session,
    this.lastEvent,
    this.streamError,
  });

  const ProductiveAuthSessionState.unauthenticated()
      : this(phase: ProductiveAuthPhase.unauthenticated);

  final ProductiveAuthPhase phase;
  final Session? session;
  final AuthChangeEvent? lastEvent;
  final Object? streamError;

  User? get user => session?.user;
  bool get isAuthenticated => user != null;
}

final productiveAuthServiceProvider = Provider<ProductiveAuthService>((ref) {
  return ProductiveAuthService(ref.watch(supabaseAuthProvider));
});

final productiveAuthStateChangesProvider = supabaseAuthStateProvider;

final productiveAuthSessionProvider =
    Provider<ProductiveAuthSessionState>((ref) {
  final auth = ref.watch(supabaseAuthProvider);
  final change = ref.watch(productiveAuthStateChangesProvider);
  final authState = change.value;
  final session = authState?.session ?? auth.currentSession;
  final event = authState?.event;
  final user = session?.user;

  if (user == null) {
    return ProductiveAuthSessionState(
      phase: ProductiveAuthPhase.unauthenticated,
      lastEvent: event,
      streamError: change.error,
    );
  }

  final metadataRequiresPassword =
      user.userMetadata?['platform_invitation_requires_password_setup'] == true;
  final requiresPassword =
      event == AuthChangeEvent.passwordRecovery || metadataRequiresPassword;

  return ProductiveAuthSessionState(
    phase: requiresPassword
        ? ProductiveAuthPhase.passwordSetupRequired
        : ProductiveAuthPhase.authenticated,
    session: session,
    lastEvent: event,
    streamError: change.error,
  );
});

typedef ProductiveSignIn = Future<void> Function({
  required String email,
  required String password,
});
typedef ProductivePasswordRecovery = Future<void> Function(String email);
typedef ProductivePasswordUpdate = Future<void> Function(String password);
typedef ProductiveSignOut = Future<void> Function();

final productiveSignInProvider = Provider<ProductiveSignIn>((ref) {
  return ref.watch(productiveAuthServiceProvider).signInWithPassword;
});

final productivePasswordRecoveryProvider =
    Provider<ProductivePasswordRecovery>((ref) {
  return (email) =>
      ref.watch(productiveAuthServiceProvider).sendPasswordRecovery(
            email: email,
            redirectTo: AppConfig.authRedirectUrl,
          );
});

final productivePasswordUpdateProvider =
    Provider<ProductivePasswordUpdate>((ref) {
  return ref.watch(productiveAuthServiceProvider).updatePassword;
});

final productiveSignOutProvider = Provider<ProductiveSignOut>((ref) {
  return () async {
    await ref.read(productiveAuthServiceProvider).signOut();
    ref.invalidate(authenticatedAccessResolverProvider);
    ref.invalidate(productiveOperationalEntryProvider);
    ref.invalidate(productiveCachedContextAvailabilityProvider);
    ref.invalidate(appRouterSyncBootstrapProvider);
    ref.invalidate(appCurrentContextProvider);
    ref.invalidate(administrationCurrentContextProvider);
    ref.invalidate(businessBranchAdministrationProvider);
    ref.invalidate(businessInvitationOptionsProvider);
    ref.invalidate(adminBusinessInvitationsProvider);
    ref.invalidate(myBusinessMemberInvitationsProvider);
  };
});
