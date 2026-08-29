import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/business_administration_providers.dart';
import '../../application/business_administration_submission_controllers.dart';
import '../../data/models/business_administration_models.dart';
import '../widgets/business_invitation_access_panel.dart';

class BusinessTeamScreen extends ConsumerWidget {
  const BusinessTeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(administrationCurrentContextProvider);
    return current.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) => _TeamStatus(
        message: 'No fue posible cargar el contexto administrativo.',
        onRetry: () => ref.invalidate(administrationCurrentContextProvider),
      ),
      data: (appContext) {
        if (appContext == null || !appContext.hasPermission('members.invite')) {
          return const _TeamStatus(
            message: 'No tienes permisos para administrar invitaciones.',
          );
        }
        final invitations =
            ref.watch(adminBusinessInvitationsProvider(appContext.businessId));
        return Scaffold(
          appBar: AppBar(title: const Text('Equipo')),
          floatingActionButton: !invitations.hasValue
              ? null
              : FloatingActionButton.extended(
                  onPressed: () async {
                    final issued =
                        await showDialog<IssueBusinessMemberInvitationResult>(
                      context: context,
                      builder: (_) => _IssueInvitationDialog(
                        businessId: appContext.businessId,
                      ),
                    );
                    if (issued == null) return;
                    ref.invalidate(
                      adminBusinessInvitationsProvider(appContext.businessId),
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(issued.userMessage)),
                    );
                  },
                  icon: const Icon(Icons.person_add_alt_1_outlined),
                  label: const Text('Invitar empleado'),
                ),
          body: invitations.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _TeamStatusBody(
              message: error.toString(),
              onRetry: () => ref.invalidate(
                adminBusinessInvitationsProvider(appContext.businessId),
              ),
            ),
            data: (response) => response.invitations.isEmpty
                ? const Center(
                    child: Text('No hay invitaciones para este alcance.'))
                : RefreshIndicator(
                    onRefresh: () async => ref.refresh(
                      adminBusinessInvitationsProvider(appContext.businessId)
                          .future,
                    ),
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: response.invitations.length,
                      itemBuilder: (context, index) {
                        final invitation = response.invitations[index];
                        return Card(
                          child: ListTile(
                            title: Text(invitation.email),
                            subtitle: Text([
                              businessRoleLabel(invitation.roleName),
                              invitation.branchName ?? 'Todo el negocio',
                              _statusLabel(invitation),
                              _deliveryLabel(invitation.deliveryStatus),
                              if (invitation.isPending)
                                'Vence ${invitation.expiresAt.toLocal().toString().split(' ').first}',
                            ].join(' · ')),
                            trailing: invitation.isPending
                                ? IconButton(
                                    tooltip: 'Revocar invitación',
                                    icon: const Icon(Icons.cancel_outlined),
                                    onPressed: () => _revoke(
                                      context,
                                      ref,
                                      invitation,
                                    ),
                                  )
                                : null,
                          ),
                        );
                      },
                    ),
                  ),
          ),
        );
      },
    );
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    BusinessMemberInvitation invitation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revocar invitación'),
        content: Text('Se revocará la invitación de ${invitation.email}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revocar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(businessAdministrationServiceProvider).revokeInvitation(
            invitation.id,
            reason: 'Revocada desde Administración',
          );
      ref.invalidate(adminBusinessInvitationsProvider(invitation.businessId));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invitación revocada.')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString())),
        );
      }
    }
  }

  String _statusLabel(BusinessMemberInvitation invitation) {
    return switch (invitation.status) {
      'pending' when !invitation.isPending => 'Expirada',
      'pending' => 'Pendiente',
      'accepted' => 'Aceptada',
      'revoked' => 'Revocada',
      _ => invitation.status,
    };
  }

  String _deliveryLabel(BusinessMemberInvitationDeliveryState status) {
    return switch (status) {
      BusinessMemberInvitationDeliveryState.sent => 'Correo enviado',
      BusinessMemberInvitationDeliveryState.failed => 'Correo no enviado',
      BusinessMemberInvitationDeliveryState.pending => 'Entrega pendiente',
      BusinessMemberInvitationDeliveryState.unknown => 'Entrega por confirmar',
    };
  }
}

class _IssueInvitationDialog extends ConsumerStatefulWidget {
  const _IssueInvitationDialog({required this.businessId});
  final String businessId;

  @override
  ConsumerState<_IssueInvitationDialog> createState() =>
      _IssueInvitationDialogState();
}

class _IssueInvitationDialogState
    extends ConsumerState<_IssueInvitationDialog> {
  static const _businessWideScope = '__business_wide__';
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  late BusinessInvitationIssueController _controller;
  String? _roleId;
  String? _scopeValue;
  bool _initialized = false;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(businessInvitationIssueControllerProvider);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate() || _roleId == null) {
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await _controller.submit(
        IssueBusinessMemberInvitationRequest(
          businessId: widget.businessId,
          email: _email.text,
          roleId: _roleId!,
          branchId: _scopeValue == _businessWideScope ? null : _scopeValue,
        ),
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final optionsAsync =
        ref.watch(businessInvitationOptionsProvider(widget.businessId));
    return AlertDialog(
      title: const Text('Invitar empleado'),
      content: SizedBox(
        width: 420,
        child: optionsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _TeamStatusBody(
            message: error.toString(),
            onRetry: () => ref.invalidate(
              businessInvitationOptionsProvider(widget.businessId),
            ),
          ),
          data: (options) {
            if (!_initialized) {
              _initialized = true;
              _roleId = options.roles.firstOrNull?.id;
              _scopeValue = options.canInviteBusinessWide
                  ? _businessWideScope
                  : options.branches.firstOrNull?.id;
            }
            return Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (options.roles.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'No hay roles delegables disponibles para este contexto.',
                        ),
                      ),
                    TextFormField(
                      controller: _email,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(labelText: 'Correo'),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                .hasMatch(email)
                            ? null
                            : 'Escribe un correo válido.';
                      },
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _roleId,
                      decoration: const InputDecoration(labelText: 'Rol'),
                      items: options.roles
                          .map(
                            (role) => DropdownMenuItem(
                              value: role.id,
                              child: Text(businessRoleLabel(role.name)),
                            ),
                          )
                          .toList(),
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _roleId = value),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _scopeValue,
                      decoration: const InputDecoration(labelText: 'Alcance'),
                      items: [
                        if (options.canInviteBusinessWide)
                          const DropdownMenuItem<String>(
                            value: _businessWideScope,
                            child: Text('Todo el negocio'),
                          ),
                        ...options.branches.map(
                          (branch) => DropdownMenuItem<String>(
                            value: branch.id,
                            child: Text(branch.name),
                          ),
                        ),
                      ],
                      onChanged: _submitting
                          ? null
                          : (value) => setState(() => _scopeValue = value),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: optionsAsync.hasValue &&
                  _roleId != null &&
                  _scopeValue != null &&
                  !_submitting
              ? _submit
              : null,
          child: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enviar invitación'),
        ),
      ],
    );
  }
}

class _TeamStatus extends StatelessWidget {
  const _TeamStatus({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Equipo')),
        body: _TeamStatusBody(message: message, onRetry: onRetry),
      );
}

class _TeamStatusBody extends StatelessWidget {
  const _TeamStatusBody({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: onRetry, child: const Text('Reintentar')),
              ],
            ],
          ),
        ),
      );
}
