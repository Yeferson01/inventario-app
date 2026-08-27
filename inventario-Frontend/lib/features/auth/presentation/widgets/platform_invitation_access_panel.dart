import 'package:flutter/material.dart';

import '../../data/models/platform_business_invitation_models.dart';

typedef PlatformInvitationAcceptAction
    = Future<AcceptedPlatformBusinessInvitation> Function(String invitationId);

class PlatformInvitationAccessPanel extends StatefulWidget {
  const PlatformInvitationAccessPanel({
    required this.invitations,
    required this.onAccept,
    this.compact = false,
    super.key,
  });

  final List<PlatformBusinessInvitation> invitations;
  final PlatformInvitationAcceptAction onAccept;
  final bool compact;

  @override
  State<PlatformInvitationAccessPanel> createState() =>
      _PlatformInvitationAccessPanelState();
}

class _PlatformInvitationAccessPanelState
    extends State<PlatformInvitationAccessPanel> {
  String? _acceptingId;
  String? _message;

  Future<void> _accept(PlatformBusinessInvitation invitation) async {
    if (_acceptingId != null) return;
    setState(() {
      _acceptingId = invitation.invitationId;
      _message = null;
    });
    try {
      await widget.onAccept(invitation.invitationId);
    } catch (error) {
      if (mounted) {
        setState(() {
          _message = error.toString();
        });
      }
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
          'Invitaciones pendientes',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Estas invitaciones son privadas y se validan nuevamente en el servidor al aceptarlas.',
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
                    'Has sido invitado a configurar: ${invitation.businessName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text('Sucursal inicial: ${invitation.branchName}'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed:
                        _acceptingId == null ? () => _accept(invitation) : null,
                    child: _acceptingId == invitation.invitationId
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
