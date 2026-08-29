import 'package:flutter/material.dart';

import '../../../administration/data/models/business_administration_models.dart';
import '../../../administration/presentation/widgets/business_invitation_access_panel.dart';
import '../../data/models/platform_business_invitation_models.dart';
import '../widgets/platform_invitation_access_panel.dart';

class PrivateInvitationScreen extends StatelessWidget {
  const PrivateInvitationScreen({
    required this.platformInvitations,
    required this.businessInvitations,
    required this.onAcceptPlatform,
    required this.onAcceptBusiness,
    required this.onSignOut,
    super.key,
  });

  final List<PlatformBusinessInvitation> platformInvitations;
  final List<BusinessMemberInvitation> businessInvitations;
  final PlatformInvitationAcceptAction onAcceptPlatform;
  final BusinessInvitationAcceptAction onAcceptBusiness;
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (platformInvitations.isNotEmpty)
                    PlatformInvitationAccessPanel(
                      invitations: platformInvitations,
                      onAccept: onAcceptPlatform,
                    ),
                  if (platformInvitations.isNotEmpty &&
                      businessInvitations.isNotEmpty)
                    const SizedBox(height: 20),
                  if (businessInvitations.isNotEmpty)
                    BusinessInvitationAccessPanel(
                      invitations: businessInvitations,
                      onAccept: onAcceptBusiness,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
