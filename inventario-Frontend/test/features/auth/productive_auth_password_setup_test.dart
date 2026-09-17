import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/app/router/app_router.dart';
import 'package:inventario_frontend/features/auth/application/productive_auth_providers.dart';
import 'package:inventario_frontend/features/auth/application/productive_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('password setup metadata compatibility', () {
    test('PW-01 legacy platform invitation requires password setup', () {
      expect(
        productiveAuthPhaseFor(
          user: _user(
            const {platformInvitationPasswordSetupMetadataKey: true},
          ),
        ),
        ProductiveAuthPhase.passwordSetupRequired,
      );
    });

    test('PW-02 password recovery event requires password setup', () {
      expect(
        productiveAuthPhaseFor(
          user: _user(const {}),
          event: AuthChangeEvent.passwordRecovery,
        ),
        ProductiveAuthPhase.passwordSetupRequired,
      );
    });

    test('PW-03 absent or false platform flag does not require setup', () {
      expect(
        productiveAuthPhaseFor(user: _user(const {})),
        ProductiveAuthPhase.authenticated,
      );
      expect(
        productiveAuthPhaseFor(
          user: _user(const {
            platformInvitationPasswordSetupMetadataKey: false,
          }),
        ),
        ProductiveAuthPhase.authenticated,
      );
    });

    test('PW-04 successful password update clears platform metadata flag',
        () async {
      UserAttributes? submitted;

      await completeInvitationPasswordSetup(
        password: 'new-password',
        updateUser: (attributes) async => submitted = attributes,
      );

      expect(submitted?.password, 'new-password');
      expect(submitted?.data, {
        platformInvitationPasswordSetupMetadataKey: false,
      });
    });

    test('PW-05 failed password update preserves the active requirement',
        () async {
      final invitedUser = _user(
        const {platformInvitationPasswordSetupMetadataKey: true},
      );

      await expectLater(
        completeInvitationPasswordSetup(
          password: 'new-password',
          updateUser: (_) async => throw StateError('remote failure'),
        ),
        throwsStateError,
      );

      expect(
        productiveAuthPhaseFor(user: invitedUser),
        ProductiveAuthPhase.passwordSetupRequired,
      );
    });

    test('PW-06 existing registered user without flag remains authenticated',
        () {
      expect(
        productiveAuthPhaseFor(user: _user(const {})),
        ProductiveAuthPhase.authenticated,
      );
    });

    test('PW-07 business member metadata is ignored by normal auth', () {
      expect(
        productiveAuthPhaseFor(
          user: _user(const {
            'business_member_invitation_requires_password_setup': true,
          }),
        ),
        ProductiveAuthPhase.authenticated,
      );
    });

    testWidgets('PW-08 callback routes platform invitation to password setup',
        (tester) async {
      final phase = productiveAuthPhaseFor(
        user: _user(
          const {platformInvitationPasswordSetupMetadataKey: true},
        ),
        event: AuthChangeEvent.signedIn,
      );
      final router = AppRouter.create(
        phase: phase,
        initialRouteName: 'dashboard',
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Define tu contraseña'), findsOneWidget);
      expect(find.text('Aceptar y continuar'), findsNothing);
    });
  });
}

User _user(Map<String, dynamic> metadata) {
  return User(
    id: 'invited-user',
    appMetadata: const {},
    userMetadata: metadata,
    aud: 'authenticated',
    email: 'invited@example.com',
    createdAt: '2026-09-16T00:00:00Z',
  );
}
