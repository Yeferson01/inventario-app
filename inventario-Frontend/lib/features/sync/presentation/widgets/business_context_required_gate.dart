import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../administration/application/business_administration_providers.dart';
import '../../../administration/data/models/business_administration_models.dart';
import '../../../administration/presentation/widgets/business_invitation_access_panel.dart';
import '../../../auth/application/authenticated_access_models.dart';
import '../../../auth/application/authenticated_access_providers.dart';
import '../../../auth/application/productive_auth_providers.dart';
import '../../../auth/data/models/platform_business_invitation_models.dart';
import '../../../auth/presentation/screens/private_invitation_screen.dart';
import '../../../auth/presentation/widgets/platform_invitation_access_panel.dart';
import '../../../cash/application/cash_session_local_models.dart';
import '../../../cash/application/cash_session_local_provider.dart';
import '../../../cash/presentation/widgets/productive_open_cash_session_dialog.dart';
import '../../application/app_current_context_provider.dart';
import '../../application/app_router_sync_bootstrap_provider.dart';
import '../../application/cash_repair_context_service.dart';
import '../../application/operational_bootstrap_entry_models.dart';
import '../../application/operational_bootstrap_entry_providers.dart';
import '../../application/operational_bootstrap_orchestration_models.dart';
import '../../application/pos_sync_upload_provider.dart';
import '../../application/productive_stale_sale_reconciliation_service.dart';
import '../../application/recovery_blocked_stale_sale_service.dart';
import '../screens/business_context_selection_screen.dart';
import 'productive_stale_sale_reconciliation_presenter.dart';

typedef NavigatorContextResolver = BuildContext? Function();

class BusinessContextRequiredGate extends ConsumerStatefulWidget {
  const BusinessContextRequiredGate({
    required this.profileId,
    required this.child,
    this.businessId,
    this.loading,
    this.navigatorContextResolver,
    this.navigatorHost,
    super.key,
  });

  final String profileId;
  final String? businessId;
  final Widget child;
  final Widget? loading;
  final NavigatorContextResolver? navigatorContextResolver;
  final Widget? navigatorHost;

  @override
  ConsumerState<BusinessContextRequiredGate> createState() =>
      _BusinessContextRequiredGateState();
}

class _BusinessContextRequiredGateState
    extends ConsumerState<BusinessContextRequiredGate> {
  OperationalContextSelection? _selection;
  final _recoveryNavigatorHostKey =
      GlobalKey<_RecoveryBlockedNavigatorHostState>();
  bool _cashRepairRunning = false;

  @override
  void didUpdateWidget(covariant BusinessContextRequiredGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileId != widget.profileId) {
      _selection = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final intent = ref.watch(productiveOperationalSelectionIntentProvider);
    final intendedSelection = intent?.profileId == widget.profileId &&
            (widget.businessId == null ||
                intent?.businessId == widget.businessId)
        ? intent?.selection
        : null;
    final request = ProductiveOperationalEntryRequest(
      profileId: widget.profileId,
      selection: intendedSelection ?? _selection,
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

  Future<AcceptedBusinessMemberInvitation> _acceptBusinessInvitation(
    String invitationId,
  ) async {
    final accepted =
        await ref.read(businessInvitationAcceptorProvider)(invitationId);
    if (!mounted) return accepted;
    setState(() {
      _selection = accepted.branchId == null
          ? null
          : OperationalContextSelection(
              businessId: accepted.businessId,
              branchId: accepted.branchId!,
            );
    });
    ref.invalidate(
      myBusinessMemberInvitationsProvider(widget.profileId),
    );
    ref.invalidate(authenticatedAccessResolverProvider(widget.profileId));
    ref.invalidate(productiveOperationalEntryProvider);
    return accepted;
  }

  Future<void> _signOut() => ref.read(productiveSignOutProvider)();

  Future<CashRepairContextResult> _refreshCashForRecovery(
    OperationalBootstrapEntryResult result, {
    required String saleId,
    required String originalCashSessionId,
    required String cashRegisterId,
  }) async {
    final selected = result.selectedContext;
    final appDeviceId = result.device?.appDeviceId.trim();
    final installationId = result.installationId?.trim();
    if (selected == null ||
        appDeviceId == null ||
        appDeviceId.isEmpty ||
        installationId == null ||
        installationId.isEmpty ||
        cashRegisterId.trim().isEmpty) {
      throw const CashRepairContextException(
        'El contexto de caja está incompleto.',
      );
    }

    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      const SnackBar(content: Text('Actualizando estado de caja…')),
    );
    try {
      return await ref.read(cashRepairContextServiceProvider).refresh(
            CashRepairContextRequest(
              profileId: selected.profileId,
              businessId: selected.businessId,
              branchId: selected.branchId,
              installationId: installationId,
              appDeviceId: appDeviceId,
              cashRegisterId: cashRegisterId,
              originalCashSessionId: originalCashSessionId,
              saleId: saleId,
              effectivePermissions: selected.effectivePermissions.toSet(),
            ),
          );
    } finally {
      messenger?.hideCurrentSnackBar();
    }
  }

  Future<void> _openCashForRecovery(
    OperationalBootstrapEntryResult result, {
    required String saleId,
    required String originalCashSessionId,
    required String cashRegisterId,
  }) async {
    if (_cashRepairRunning) return;
    _cashRepairRunning = true;
    try {
      final refreshed = await _refreshCashForRecovery(
        result,
        saleId: saleId,
        originalCashSessionId: originalCashSessionId,
        cashRegisterId: cashRegisterId,
      );
      if (refreshed.openCashSessionId != null) return;

      final dialogContext = _dialogContext;
      if (dialogContext == null) return;
      final selected = result.selectedContext!;
      final appDeviceId = result.device!.appDeviceId.trim();
      final installationId = result.installationId!.trim();

      final service = ref.read(cashSessionLocalServiceProvider);
      Map<String, dynamic>? summary;
      try {
        summary = await service.getLatestCashSessionSummaryForBranch(
          businessId: selected.businessId,
          branchId: selected.branchId,
        );
      } on StateError {
        summary = null;
      }
      if (!mounted || !dialogContext.mounted) return;
      _setRecoveryDialogVisible(true);
      ProductiveOpenCashDialogResult? dialogResult;
      try {
        dialogResult = await showDialog<ProductiveOpenCashDialogResult>(
          context: dialogContext,
          builder: (_) => ProductiveOpenCashSessionDialog(
            suggestedOpeningAmount: suggestedProductiveOpeningAmount(summary),
          ),
        );
      } finally {
        _setRecoveryDialogVisible(false);
      }
      if (dialogResult == null) return;
      await service.openCashSession(
        OpenCashSessionInput(
          businessId: selected.businessId,
          branchId: selected.branchId,
          profileId: selected.profileId,
          cashRegisterId: refreshed.runtime.cashRegisterId!,
          openingCashAmount: dialogResult.openingAmount,
          appDeviceId: appDeviceId,
          deviceInstallationId: installationId,
          metadata: const {
            'source': 'business_context_required_gate',
            'flow': 'recovery_stale_sale_open_cash_session',
          },
        ),
      );
      final afterOpen = await _refreshCashForRecovery(
        result,
        saleId: saleId,
        originalCashSessionId: originalCashSessionId,
        cashRegisterId: cashRegisterId,
      );
      if (afterOpen.openCashSessionId == null) {
        throw const CashRepairContextException(
          'La caja abierta no pudo confirmarse en el contexto actualizado.',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Caja abierta correctamente.')),
        );
      }
    } catch (error) {
      if (mounted) {
        await _showRecoveryMessage(
          'No se pudo abrir la caja',
          error is CashRepairContextException
              ? error.message
              : 'No se pudo verificar el estado autoritativo de caja.',
        );
      }
    } finally {
      _cashRepairRunning = false;
    }
  }

  Future<void> _showRecoveryMessage(String title, String message) async {
    final dialogContext = _dialogContext;
    if (dialogContext == null) return;
    _setRecoveryDialogVisible(true);
    try {
      await showDialog<void>(
        context: dialogContext,
        builder: (messageContext) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(messageContext),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
    } finally {
      _setRecoveryDialogVisible(false);
    }
  }

  void _setRecoveryDialogVisible(bool visible) {
    _recoveryNavigatorHostKey.currentState?.setBlockingOverlayVisible(!visible);
  }

  BuildContext? get _dialogContext {
    final provided = widget.navigatorContextResolver?.call();
    if (provided?.mounted == true) return provided;
    return Navigator.maybeOf(context, rootNavigator: true)?.overlay?.context;
  }

  Widget _buildResult(
    OperationalBootstrapEntryResult result,
    ProductiveOperationalEntryRequest request,
    AuthenticatedAccessResult? access,
  ) {
    final entryProvider = productiveOperationalEntryProvider(request);
    final invitations = access?.pendingInvitations ?? const [];
    final businessInvitations = access?.pendingBusinessInvitations ??
        const <BusinessMemberInvitation>[];
    final hasInvitations =
        invitations.isNotEmpty || businessInvitations.isNotEmpty;
    switch (result.outcome) {
      case OperationalBootstrapEntryOutcome.noAuthorizedContexts:
        if (hasInvitations) {
          return PrivateInvitationScreen(
            platformInvitations: invitations,
            businessInvitations: businessInvitations,
            onAcceptPlatform: _acceptInvitation,
            onAcceptBusiness: _acceptBusinessInvitation,
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
          additionalContent: !hasInvitations
              ? null
              : _InvitationPanels(
                  platformInvitations: invitations,
                  businessInvitations: businessInvitations,
                  onAcceptPlatform: _acceptInvitation,
                  onAcceptBusiness: _acceptBusinessInvitation,
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
          return !hasInvitations
              ? widget.child
              : _PendingInvitationsOverlay(
                  platformInvitations: invitations,
                  businessInvitations: businessInvitations,
                  onAcceptPlatform: _acceptInvitation,
                  onAcceptBusiness: _acceptBusinessInvitation,
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
        final blocked = _RecoveryBlockedOperationalEntry(
          key: ValueKey(
            '${result.profileId}:${result.selectedContext?.businessId}:'
            '${result.selectedContext?.branchId}:'
            '${issues.map((issue) => '${issue.issueType}:${issue.entityId}').join('|')}',
          ),
          result: result,
          issues: issues,
          assessmentService: ref.read(
            recoveryBlockedStaleSaleAssessmentServiceProvider,
          ),
          reconciliationController: ref.read(
            productiveStaleSaleReconciliationServiceProvider,
          ),
          onRetry: () => ref.invalidate(entryProvider),
          onRefreshCashContext: ({
            required saleId,
            required originalCashSessionId,
            required cashRegisterId,
          }) async {
            await _refreshCashForRecovery(
              result,
              saleId: saleId,
              originalCashSessionId: originalCashSessionId,
              cashRegisterId: cashRegisterId,
            );
          },
          onOpenCash: ({
            required saleId,
            required originalCashSessionId,
            required cashRegisterId,
          }) =>
              _openCashForRecovery(
            result,
            saleId: saleId,
            originalCashSessionId: originalCashSessionId,
            cashRegisterId: cashRegisterId,
          ),
          navigatorContextResolver: () => _dialogContext,
          onDialogVisibilityChanged: _setRecoveryDialogVisible,
        );
        return _RecoveryBlockedNavigatorHost(
          key: _recoveryNavigatorHostKey,
          navigatorHost: widget.navigatorHost ?? widget.child,
          navigatorContextResolver: () => _dialogContext,
          blocked: blocked,
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

class _RecoveryBlockedNavigatorHost extends StatefulWidget {
  const _RecoveryBlockedNavigatorHost({
    required this.navigatorHost,
    required this.navigatorContextResolver,
    required this.blocked,
    super.key,
  });

  final Widget navigatorHost;
  final NavigatorContextResolver navigatorContextResolver;
  final Widget blocked;

  @override
  State<_RecoveryBlockedNavigatorHost> createState() =>
      _RecoveryBlockedNavigatorHostState();
}

class _RecoveryBlockedNavigatorHostState
    extends State<_RecoveryBlockedNavigatorHost> {
  OverlayEntry? _entry;
  bool _installScheduled = false;
  bool _suspended = false;

  @override
  void didUpdateWidget(covariant _RecoveryBlockedNavigatorHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry?.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _scheduleInstall() {
    if (_installScheduled || _entry != null) return;
    _installScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _installScheduled = false;
      if (!mounted || _entry != null) return;
      final navigatorContext = widget.navigatorContextResolver();
      final overlay = navigatorContext == null
          ? null
          : Overlay.maybeOf(navigatorContext, rootOverlay: true);
      if (overlay == null) return;
      final entry = OverlayEntry(builder: _buildBlockedOverlay);
      overlay.insert(entry);
      _entry = entry;
      if (mounted) setState(() {});
    });
  }

  void setBlockingOverlayVisible(bool visible) {
    if (!mounted || visible == !_suspended) return;
    if (!visible) {
      _suspended = true;
      _entry?.markNeedsBuild();
      setState(() {});
      return;
    }
    _suspended = false;
    final navigatorContext = widget.navigatorContextResolver();
    final overlay = navigatorContext == null
        ? null
        : Overlay.maybeOf(navigatorContext, rootOverlay: true);
    if (overlay != null && _entry == null) {
      final entry = OverlayEntry(builder: _buildBlockedOverlay);
      overlay.insert(entry);
      _entry = entry;
    } else {
      _entry?.markNeedsBuild();
    }
    setState(() {});
  }

  Widget _buildBlockedOverlay(BuildContext context) {
    return Offstage(
      offstage: _suspended,
      child: IgnorePointer(
        ignoring: _suspended,
        child: widget.blocked,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _scheduleInstall();
    if (_entry != null) return widget.navigatorHost;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.navigatorHost,
        _buildBlockedOverlay(context),
      ],
    );
  }
}

class _RecoveryBlockedOperationalEntry extends StatefulWidget {
  const _RecoveryBlockedOperationalEntry({
    required this.result,
    required this.issues,
    required this.assessmentService,
    required this.reconciliationController,
    required this.onRetry,
    required this.onRefreshCashContext,
    required this.onOpenCash,
    required this.navigatorContextResolver,
    required this.onDialogVisibilityChanged,
    super.key,
  });

  final OperationalBootstrapEntryResult result;
  final List<OperationalBootstrapBlockingIssue> issues;
  final RecoveryBlockedStaleSaleAssessmentService assessmentService;
  final ProductiveStaleSaleReconciliationController reconciliationController;
  final VoidCallback onRetry;
  final ProductiveCashRepairAction onRefreshCashContext;
  final ProductiveCashRepairAction onOpenCash;
  final NavigatorContextResolver navigatorContextResolver;
  final ValueChanged<bool> onDialogVisibilityChanged;

  @override
  State<_RecoveryBlockedOperationalEntry> createState() =>
      _RecoveryBlockedOperationalEntryState();
}

class _RecoveryBlockedOperationalEntryState
    extends State<_RecoveryBlockedOperationalEntry> {
  late Future<RecoveryBlockedStaleSaleAssessment> _assessment;
  bool _reviewing = false;

  @override
  void initState() {
    super.initState();
    _assessment = _assess();
  }

  Future<RecoveryBlockedStaleSaleAssessment> _assess() {
    final result = widget.result;
    final selected = result.selectedContext;
    final profileId = result.profileId;
    if (profileId == null || selected == null) {
      return Future.error(
        StateError('Operational recovery scope is incomplete.'),
      );
    }
    return widget.assessmentService.assess(
      profileId: profileId,
      businessId: selected.businessId,
      branchId: selected.branchId,
      blockingIssues: widget.issues,
    );
  }

  Future<void> _review() async {
    if (_reviewing) return;
    final result = widget.result;
    final selected = result.selectedContext!;
    final profileId = result.profileId!;
    final appDeviceId = result.device?.appDeviceId.trim() ??
        result.bootstrapResult?.appDeviceId.trim() ??
        '';
    if (appDeviceId.isEmpty) return;
    final dialogContext = widget.navigatorContextResolver();
    if (dialogContext == null || !dialogContext.mounted) return;
    setState(() => _reviewing = true);
    await ProductiveStaleSaleReconciliationPresenter.show(
      context: dialogContext,
      service: widget.reconciliationController,
      profileId: profileId,
      businessId: selected.businessId,
      branchId: selected.branchId,
      appDeviceId: appDeviceId,
      effectivePermissions: selected.effectivePermissions.toSet(),
      onRefreshCashContext: widget.onRefreshCashContext,
      onOpenCash: widget.onOpenCash,
      onDialogVisibilityChanged: widget.onDialogVisibilityChanged,
      dialogBarrierColor: Theme.of(dialogContext).scaffoldBackgroundColor,
    );
    if (!mounted) return;
    final remaining = await widget.reconciliationController.loadPending(
      profileId: profileId,
      businessId: selected.businessId,
      branchId: selected.branchId,
    );
    if (!mounted) return;
    if (remaining.isEmpty) {
      widget.onRetry();
      return;
    }
    setState(() {
      _reviewing = false;
      _assessment = _assess();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RecoveryBlockedStaleSaleAssessment>(
      future: _assessment,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _OperationalEntryLoading();
        }
        final assessment = snapshot.data;
        if (assessment == null || !assessment.canReviewSales) {
          return _OperationalEntryStatus(
            title: 'Recuperación bloqueada',
            message: _issueDetails(widget.result, widget.issues),
            actionLabel: 'Reintentar',
            onAction: widget.onRetry,
          );
        }
        final count = assessment.sales.length;
        final hardMessage = assessment.hardIssues.isEmpty
            ? ''
            : '\n\nAdemás existen otros bloqueos que deberán resolverse:\n'
                '${assessment.hardIssues.map((issue) => issue.message).join('\n')}';
        return _OperationalEntryStatus(
          title: 'Recuperación requiere revisión',
          message: 'Hay operaciones pendientes que necesitan revisión antes '
              'de continuar.\n\n$count ${count == 1 ? 'venta no pudo' : 'ventas no pudieron'} '
              'sincronizarse porque la caja original ya estaba cerrada.'
              '$hardMessage',
          actionLabel: 'Revisar ventas',
          onAction: _reviewing ? null : _review,
          secondaryActionLabel: 'Reintentar recuperación',
          onSecondaryAction: _reviewing ? null : widget.onRetry,
        );
      },
    );
  }

  String _issueDetails(
    OperationalBootstrapEntryResult result,
    List<OperationalBootstrapBlockingIssue> issues,
  ) {
    return issues.isEmpty
        ? result.message
        : issues.map((issue) => issue.message).join('\n');
  }
}

class _PendingInvitationsOverlay extends StatelessWidget {
  const _PendingInvitationsOverlay({
    required this.platformInvitations,
    required this.businessInvitations,
    required this.onAcceptPlatform,
    required this.onAcceptBusiness,
    required this.child,
  });

  final List<PlatformBusinessInvitation> platformInvitations;
  final List<BusinessMemberInvitation> businessInvitations;
  final PlatformInvitationAcceptAction onAcceptPlatform;
  final BusinessInvitationAcceptAction onAcceptBusiness;
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
                      child: _InvitationPanels(
                        platformInvitations: platformInvitations,
                        businessInvitations: businessInvitations,
                        onAcceptPlatform: (id) async {
                          final result = await onAcceptPlatform(id);
                          if (sheetContext.mounted) {
                            Navigator.of(sheetContext).pop();
                          }
                          return result;
                        },
                        onAcceptBusiness: (id) async {
                          final result = await onAcceptBusiness(id);
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
                  platformInvitations.length + businessInvitations.length == 1
                      ? '1 invitación pendiente'
                      : '${platformInvitations.length + businessInvitations.length} invitaciones pendientes',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _InvitationPanels extends StatelessWidget {
  const _InvitationPanels({
    required this.platformInvitations,
    required this.businessInvitations,
    required this.onAcceptPlatform,
    required this.onAcceptBusiness,
  });

  final List<PlatformBusinessInvitation> platformInvitations;
  final List<BusinessMemberInvitation> businessInvitations;
  final PlatformInvitationAcceptAction onAcceptPlatform;
  final BusinessInvitationAcceptAction onAcceptBusiness;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (platformInvitations.isNotEmpty)
          PlatformInvitationAccessPanel(
            invitations: platformInvitations,
            onAccept: onAcceptPlatform,
            compact: true,
          ),
        if (platformInvitations.isNotEmpty && businessInvitations.isNotEmpty)
          const SizedBox(height: 20),
        if (businessInvitations.isNotEmpty)
          BusinessInvitationAccessPanel(
            invitations: businessInvitations,
            onAccept: onAcceptBusiness,
            compact: true,
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
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

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
                      if (secondaryActionLabel != null &&
                          onSecondaryAction != null) ...[
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: onSecondaryAction,
                          child: Text(secondaryActionLabel!),
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
