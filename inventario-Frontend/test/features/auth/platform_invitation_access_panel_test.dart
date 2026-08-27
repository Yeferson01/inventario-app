import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/auth/data/models/platform_business_invitation_models.dart';
import 'package:inventario_frontend/features/auth/presentation/widgets/platform_invitation_access_panel.dart';

void main() {
  testWidgets('accept invitation is single-flight', (tester) async {
    final completion = Completer<AcceptedPlatformBusinessInvitation>();
    var calls = 0;
    final invitation = PlatformBusinessInvitation(
      invitationId: 'invite-a',
      businessId: 'business-a',
      branchId: 'branch-a',
      businessName: 'Business A',
      branchName: 'Principal',
      status: 'pending',
      expiresAt: DateTime.utc(2026, 9),
      isExpired: false,
      createdAt: DateTime.utc(2026, 8, 26),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlatformInvitationAccessPanel(
            invitations: [invitation],
            onAccept: (_) {
              calls += 1;
              return completion.future;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Aceptar y continuar'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(calls, 1);

    completion.complete(
      const AcceptedPlatformBusinessInvitation(
        invitationId: 'invite-a',
        businessId: 'business-a',
        branchId: 'branch-a',
        invitationStatus: 'accepted',
      ),
    );
    await tester.pumpAndSettle();
  });
}
