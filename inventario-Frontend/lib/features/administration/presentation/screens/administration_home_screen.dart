import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes_constants.dart';
import '../../application/business_administration_providers.dart';

class AdministrationHomeScreen extends ConsumerWidget {
  const AdministrationHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentContext = ref.watch(administrationCurrentContextProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Administración')),
      body: currentContext.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Status(
          message: 'No fue posible cargar el contexto administrativo.',
          onRetry: () => ref.invalidate(administrationCurrentContextProvider),
        ),
        data: (appContext) {
          if (appContext == null || !appContext.authorizationContextReady) {
            return const _Status(
              message: 'No existe un contexto operacional autorizado.',
            );
          }
          final hasLocalBranchPermission =
              appContext.hasPermission('settings.branches');
          final canInviteMembers = appContext.hasPermission('members.invite');
          if (!hasLocalBranchPermission && !canInviteMembers) {
            return const _Status(
              message: 'No tienes permisos de administración en este contexto.',
            );
          }
          final branchRequest = BusinessBranchAdministrationRequest.fromContext(
            appContext,
          );
          final branchAvailability = hasLocalBranchPermission
              ? ref.watch(
                  businessBranchAdministrationProvider(branchRequest),
                )
              : null;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (branchAvailability != null)
                _BranchAdministrationTile(
                  availability: branchAvailability,
                  onOpen: () =>
                      context.push(AppRoutes.administrationBranchesPath),
                  onRetry: () => ref.invalidate(
                    businessBranchAdministrationProvider(branchRequest),
                  ),
                ),
              if (canInviteMembers)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.group_outlined),
                    title: const Text('Equipo'),
                    subtitle: const Text(
                      'Emite, consulta y revoca invitaciones de acceso al negocio.',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(AppRoutes.administrationTeamPath),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BranchAdministrationTile extends StatelessWidget {
  const _BranchAdministrationTile({
    required this.availability,
    required this.onOpen,
    required this.onRetry,
  });

  final AsyncValue<BusinessBranchAdministrationAvailability> availability;
  final VoidCallback onOpen;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return availability.when(
      loading: () => const _BranchCard(
        subtitle: 'Verificando acceso a sucursales…',
        loading: true,
      ),
      error: (_, __) => _BranchCard(
        subtitle: 'No fue posible verificar el acceso a sucursales.',
        onRetry: onRetry,
      ),
      data: (result) {
        return switch (result.kind) {
          BusinessBranchAdministrationAvailabilityKind.available => _BranchCard(
              subtitle:
                  'Consulta y crea sucursales mediante el contrato seguro del servidor.',
              onTap: onOpen,
            ),
          BusinessBranchAdministrationAvailabilityKind.unauthorizedScope =>
            const _BranchCard(
              subtitle: 'Disponible para administración general del negocio.',
            ),
          BusinessBranchAdministrationAvailabilityKind.retryableFailure =>
            _BranchCard(
              subtitle: 'No fue posible verificar el acceso a sucursales.',
              onRetry: onRetry,
            ),
          BusinessBranchAdministrationAvailabilityKind.notApplicable =>
            const SizedBox.shrink(),
        };
      },
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.subtitle,
    this.loading = false,
    this.onTap,
    this.onRetry,
  });

  final String subtitle;
  final bool loading;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        enabled: onTap != null,
        leading: const Icon(Icons.store_outlined),
        title: const Text('Sucursales'),
        subtitle: Text(subtitle),
        trailing: loading
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : onRetry != null
                ? TextButton(
                    onPressed: onRetry,
                    child: const Text('Reintentar'),
                  )
                : onTap != null
                    ? const Icon(Icons.chevron_right)
                    : null,
        onTap: onTap,
      ),
    );
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onRetry, child: const Text('Reintentar')),
            ],
          ],
        ),
      ),
    );
  }
}
