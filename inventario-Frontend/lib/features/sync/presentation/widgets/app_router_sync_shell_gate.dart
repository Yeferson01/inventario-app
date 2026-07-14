import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/supabase/supabase_client_provider.dart';
import '../../application/app_router_sync_bootstrap_provider.dart';
import '../../application/app_sync_coordinator_models.dart';
import 'app_sync_lifecycle_gate.dart';
import 'business_context_required_gate.dart';

class AppRouterSyncShellGate extends ConsumerWidget {
  const AppRouterSyncShellGate({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bootstrapAsync = ref.watch(appRouterSyncBootstrapProvider);

    return bootstrapAsync.when(
      data: (bootstrap) {
        if (!bootstrap.hasAuthenticatedUser) {
          return child;
        }

        final input = bootstrap.input;

        if (input == null) {
          final user = ref.read(supabaseClientProvider).auth.currentUser;

          if (user == null) {
            return child;
          }

          return BusinessContextRequiredGate(
            profileId: user.id,
            child: child,
          );
        }

        return BusinessContextRequiredGate(
          profileId: input.profileId ?? '',
          child: AppSyncLifecycleGate(
            inputBuilder: (_, trigger) async {
              return input.copyWithLifecycleTrigger(trigger.code);
            },
            child: child,
          ),
        );
      },
      loading: () => child,
      error: (error, stackTrace) {
        return Material(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Text(
                  'Error inicializando AppRouterSyncShellGate:\n\n$error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

extension AppRouterSyncShellInputCopy on AppSyncCoordinatorInput {
  AppSyncCoordinatorInput copyWithLifecycleTrigger(String triggerCode) {
    return copyWithMetadata({
      'lifecycle_trigger': triggerCode,
    });
  }
}
