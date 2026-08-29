import 'package:flutter/material.dart';

import '../../data/models/business_administration_models.dart';

typedef BusinessInvitationAcceptAction
    = Future<AcceptedBusinessMemberInvitation> Function(String invitationId);

class BusinessInvitationAccessPanel extends StatefulWidget {
  const BusinessInvitationAccessPanel({
    required this.invitations,
    required this.onAccept,
    this.compact = false,
    super.key,
  });

  final List<BusinessMemberInvitation> invitations;
  final BusinessInvitationAcceptAction onAccept;
  final bool compact;

  @override
  State<BusinessInvitationAccessPanel> createState() =>
      _BusinessInvitationAccessPanelState();
}

class _BusinessInvitationAccessPanelState
    extends State<BusinessInvitationAccessPanel> {
  String? _acceptingId;
  String? _message;

  Future<void> _accept(BusinessMemberInvitation invitation) async {
    if (_acceptingId != null) return;
    setState(() {
      _acceptingId = invitation.id;
      _message = null;
    });
    try {
      await widget.onAccept(invitation.id);
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _acceptingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Invitaciones de negocio',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'El servidor volverá a validar la invitación y tus permisos al aceptarla.',
        ),
        const SizedBox(height: 12),
        for (final invitation in widget.invitations) ...[
          Card.outlined(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    invitation.businessName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('Rol: ${businessRoleLabel(invitation.roleName)}'),
                  Text(
                    invitation.branchName == null
                        ? 'Alcance: todo el negocio'
                        : 'Sucursal: ${invitation.branchName}',
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed:
                        _acceptingId == null ? () => _accept(invitation) : null,
                    child: _acceptingId == invitation.id
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Aceptar y continuar'),
                  ),
                ],
              ),
            ),
          ),
          if (!widget.compact) const SizedBox(height: 8),
        ],
        if (_message != null) ...[
          const SizedBox(height: 8),
          Semantics(liveRegion: true, child: Text(_message!)),
        ],
      ],
    );
  }
}

String businessRoleLabel(String roleName) {
  return switch (roleName.trim().toLowerCase()) {
    'cashier' => 'Cajero',
    'warehouse' => 'Bodega / Inventario',
    'technician' => 'Técnico',
    _ => roleName,
  };
}
