import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/application/authenticated_access_models.dart';
import '../../../auth/application/authenticated_access_providers.dart';
import '../../../auth/application/productive_auth_providers.dart';
import '../../../auth/data/models/platform_business_invitation_models.dart';
import '../../../auth/presentation/screens/private_invitation_screen.dart';
import '../../../auth/presentation/widgets/platform_invitation_access_panel.dart';
import '../../application/app_current_context_provider.dart';
import '../../application/app_router_sync_bootstrap_provider.dart';
import '../../application/operational_bootstrap_entry_models.dart';
import '../../application/operational_bootstrap_entry_providers.dart';
import '../screens/business_context_selection_screen.dart';

class BusinessContextRequiredGate extends ConsumerStatefulWidget {
  const BusinessContextRequiredGate({
    required this.profileId,
    required this.child,
    this.loading,
    super.key,
  });

  final String profileId;
  final Widget child;
  final Widget? loading;

  @override
  ConsumerState<BusinessContextRequiredGate> createState() =>
      _BusinessContextRequiredGateState();
}

class _BusinessContextRequiredGateState
    extends ConsumerState<BusinessContextRequiredGate> {
  OperationalContextSelection? _selection;

  @override
  void didUpdateWidget(covariant BusinessContextRequiredGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _selection = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = ProductiveOperationalEntryRequest(
      profileId: widget.profileId,
      selection: _selection,
    );
    final entryProvider = productiveOperationalEntryProvider(request);

    ref.listen(entryProvider, (previous, next) {
      final priorOutcome = previous?.value?.outcome;
      final result = next.value;
      if (result?.outcome ==
              OperationalBootstrapEntryOutcome
                  .runtimeReadyAndBootstrapCompleted &&
          result!.offlineReady &&
          priorOutcome != result.outcome) {
        ref.invalidate(appRouterSyncBootstrapProvider);
        ref.invalidate(appCurrentContextProvider);
      }
    });

    final entryAsync = ref.watch(entryProvider);
    final access = ref
        .watch(
          authenticatedAccessResolverProvider(widget.profileId),
        )
        .value;
    final previousOutcome = entryAsync.value?.outcome;
    final isRefreshingAccessDenial = entryAsync.isLoading &&
        (previousOutcome ==
                OperationalBootstrapEntryOutcome.authorizationRevoked ||
            previousOutcome ==
                OperationalBootstrapEntryOutcome.noAuthorizedContexts);
    if (isRefreshingAccessDenial) {
      return widget.loading ?? const _OperationalEntryLoading();
    }
    return entryAsync.when(
      loading: () => widget.loading ?? const _OperationalEntryLoading(),
      error: (_, __) => _OperationalEntryStatus(
        title: 'No se pudo preparar el contexto',
        message:
            'No fue posible verificar el acceso operacional. Puedes reintentarlo.',
        actionLabel: 'Reintentar',
        onAction: () => ref.invalidate(entryProvider),
      ),
      data: (result) => _buildResult(result, request, access),
    );
  }

  Future<AcceptedPlatformBusinessInvitation> _acceptInvitation(
    String invitationId,
  ) async {
    final accepted =
        await ref.read(platformInvitationAcceptorProvider)(invitationId);
    if (!mounted) return accepted;
    setState(() {
      _selection = OperationalContextSelection(
        businessId: accepted.businessId,
        branchId: accepted.branchId,
      );
    });
    ref.invalidate(authenticatedAccessResolverProvider(widget.profileId));
    ref.invalidate(productiveOperationalEntryProvider);
    return accepted;
  }

  Future<void> _signOut() => ref.read(productiveSignOutProvider)();

  Widget _buildResult(
    OperationalBootstrapEntryResult result,
    ProductiveOperationalEntryRequest request,
    AuthenticatedAccessResult? access,
  ) {
    final entryProvider = productiveOperationalEntryProvider(request);
    final invitations = access?.pendingInvitations ?? const [];
    switch (result.outcome) {
      case OperationalBootstrapEntryOutcome.noAuthorizedContexts:
        if (invitations.isNotEmpty) {
          return PrivateInvitationScreen(
            invitations: invitations,
            onAccept: _acceptInvitation,
            onSignOut: _signOut,
          );
        }
        return _OperationalEntryStatus(
          title: 'Sin contextos operacionales autorizados',
          message:
              'Esta cuenta no tiene un negocio autorizado. Contacta con el administrador de Cronos.',
          actionLabel: 'Cerrar sesión',
          onAction: _signOut,
        );
      case OperationalBootstrapEntryOutcome.selectionRequired:
        return BusinessContextSelectionScreen(
          contexts: result.contexts,
          additionalContent: invitations.isEmpty
              ? null
              : PlatformInvitationAccessPanel(
                  invitations: invitations,
                  onAccept: _acceptInvitation,
                  compact: true,
                ),
          onContextSelected: (selected) {
            setState(() {
              _selection = OperationalContextSelection(
                businessId: selected.businessId,
                branchId: selected.branchId,
              );
            });
          },
        );
      case OperationalBootstrapEntryOutcome.runtimeReadyAndBootstrapCompleted:
        if (result.offlineReady) {
          return invitations.isEmpty
              ? widget.child
              : _PendingInvitationsOverlay(
                  invitations: invitations,
                  onAccept: _acceptInvitation,
                  child: widget.child,
                );
        }
        return const _OperationalEntryStatus(
          title: 'Recuperación incompleta',
          message:
              'El contexto terminó sin cumplir las condiciones de operación offline.',
        );
      case OperationalBootstrapEntryOutcome.runtimeSetupRequired:
        return _OperationalEntryStatus(
          title: 'Configuración operativa requerida',
          message: result.canRequestAdministrativeSetup
              ? 'La sucursal necesita configuración administrativa antes de operar.'
              : 'La sucursal aún no tiene runtime disponible. Solicita ayuda a un administrador.',
        );
      case OperationalBootstrapEntryOutcome.bootstrapRecoveryBlocked:
        final issues = result.bootstrapResult?.blockingIssues ?? const [];
        final details = issues.isEmpty
            ? result.message
            : issues.map((issue) => issue.message).join('\n');
        return _OperationalEntryStatus(
          title: 'Recuperación bloqueada',
          message: details,
          actionLabel: 'Reintentar',
          onAction: () => ref.invalidate(entryProvider),
        );
      case OperationalBootstrapEntryOutcome.transientFailure:
        final cached = ref.watch(
          productiveCachedContextAvailabilityProvider(widget.profileId),
        );
        return cached.when(
          data: (available) {
            if (available) {
              return widget.child;
            }
            return _OperationalEntryStatus(
              title: 'Red no disponible',
              message:
                  'No fue posible validar el contexto en línea y no existe una proyección local activa para continuar.',
              actionLabel: 'Reintentar',
              onAction: () => ref.invalidate(entryProvider),
            );
          },
          loading: () => widget.loading ?? const _OperationalEntryLoading(),
          error: (_, __) => _OperationalEntryStatus(
            title: 'Red no disponible',
            message:
                'No fue posible comprobar el acceso en línea. Puedes reintentarlo.',
            actionLabel: 'Reintentar',
            onAction: () => ref.invalidate(entryProvider),
          ),
        );
      case OperationalBootstrapEntryOutcome.authorizationRevoked:
        return const _OperationalEntryStatus(
          title: 'Autorización no disponible',
          message:
              'La autorización del contexto ya no está disponible para esta sesión.',
        );
      case OperationalBootstrapEntryOutcome.deviceBlocked:
        return const _OperationalEntryStatus(
          title: 'Dispositivo bloqueado',
          message:
              'Esta instalación no puede autorregistrarse. Se requiere una acción administrativa explícita.',
        );
      case OperationalBootstrapEntryOutcome.failed:
        return _OperationalEntryStatus(
          title: 'No se pudo preparar la operación',
          message:
              'No fue posible completar la verificación del acceso. Puedes reintentarlo.',
          actionLabel: 'Reintentar',
          onAction: () => ref.invalidate(entryProvider),
        );
    }
  }
}

class _PendingInvitationsOverlay extends StatelessWidget {
  const _PendingInvitationsOverlay({
    required this.invitations,
    required this.onAccept,
    required this.child,
  });

  final List<PlatformBusinessInvitation> invitations;
  final PlatformInvitationAcceptAction onAccept;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton.tonalIcon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (sheetContext) => SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: PlatformInvitationAccessPanel(
                        invitations: invitations,
                        onAccept: (id) async {
                          final result = await onAccept(id);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                          return result;
                        },
                      ),
                    ),
                  ),
                ),
                icon: const Icon(Icons.mark_email_unread_outlined),
                label: Text(
                  invitations.length == 1
                      ? '1 invitación pendiente'
                      : '${invitations.length} invitaciones pendientes',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OperationalEntryLoading extends StatelessWidget {
  const _OperationalEntryLoading();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Preparando contexto operacional...'),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationalEntryStatus extends StatelessWidget {
  const _OperationalEntryStatus({
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      Text(message),
                      if (actionLabel != null && onAction != null) ...[
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: onAction,
                          child: Text(actionLabel!),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
