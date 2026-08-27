import 'package:flutter/material.dart';

import '../../data/models/platform_business_invitation_models.dart';
import '../widgets/platform_invitation_access_panel.dart';

class PrivateInvitationScreen extends StatelessWidget {
  const PrivateInvitationScreen({
    required this.invitations,
    required this.onAccept,
    required this.onSignOut,
    super.key,
  });

  final List<PlatformBusinessInvitation> invitations;
  final PlatformInvitationAcceptAction onAccept;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Acceso privado'),
        actions: [
          IconButton(
            onPressed: onSignOut,
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: PlatformInvitationAccessPanel(
                invitations: invitations,
                onAccept: onAccept,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
