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
    final authenticatedUser = ref.watch(currentSupabaseUserProvider);
    final bootstrapAsync = ref.watch(appRouterSyncBootstrapProvider);

    return bootstrapAsync.when(
      data: (bootstrap) {
        if (authenticatedUser == null) {
          return child;
        }

        if (!bootstrap.hasAuthenticatedUser) {
          return const _AuthenticatedShellLoading();
        }

        final input = bootstrap.input;

        if (input == null) {
          return BusinessContextRequiredGate(
            profileId: authenticatedUser.id,
            child: child,
          );
        }

        return BusinessContextRequiredGate(
          profileId: input.profileId ?? '',
          businessId: input.businessId,
          child: AppSyncLifecycleGate(
            inputBuilder: (_, trigger) async {
              return input.copyWithLifecycleTrigger(trigger.code);
            },
            child: child,
          ),
        );
      },
      loading: () => authenticatedUser == null
          ? child
          : const _AuthenticatedShellLoading(),
      error: (_, __) => authenticatedUser == null
          ? child
          : _AuthenticatedShellFailure(
              onRetry: () => ref.invalidate(appRouterSyncBootstrapProvider),
            ),
    );
  }
}

class _AuthenticatedShellFailure extends StatelessWidget {
  const _AuthenticatedShellFailure({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No fue posible preparar el acceso.'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthenticatedShellLoading extends StatelessWidget {
  const _AuthenticatedShellLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
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
