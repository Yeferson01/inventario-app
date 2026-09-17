import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/app/router/app_router.dart';
import 'package:inventario_frontend/core/supabase/productive_supabase_auth_options.dart';
import 'package:inventario_frontend/features/auth/application/productive_auth_providers.dart';
import 'package:inventario_frontend/features/auth/application/productive_auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('auth callback session handoff', () {
    test('CB-01 platform callback session resolves to password setup', () {
      expect(productiveSupabaseAuthOptions.authFlowType, AuthFlowType.pkce);
      expect(productiveSupabaseAuthOptions.detectSessionInUri, isTrue);

      final state = _resolve(
        AsyncValue.data(
          AuthState(AuthChangeEvent.signedIn, _platformInvitationSession),
        ),
      );

      expect(state.phase, ProductiveAuthPhase.passwordSetupRequired);
      expect(state.session, same(_platformInvitationSession));
    });

    test('CB-02 warm callback replaces signed-out state', () {
      final signedOut = _resolve(
        const AsyncValue.data(AuthState(AuthChangeEvent.initialSession, null)),
      );
      final callback = _resolve(
        AsyncValue.data(
          AuthState(AuthChangeEvent.signedIn, _platformInvitationSession),
        ),
      );

      expect(signedOut.phase, ProductiveAuthPhase.unauthenticated);
      expect(callback.phase, ProductiveAuthPhase.passwordSetupRequired);
    });

    testWidgets('CB-03 unresolved session shows resolving then password setup',
        (tester) async {
      var phase = _resolve(const AsyncValue.loading()).phase;
      expect(phase, ProductiveAuthPhase.initializing);

      var router = AppRouter.create(phase: phase);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      expect(find.text('Validando acceso seguro...'), findsOneWidget);
      expect(find.text('Iniciar sesión'), findsNothing);
      router.dispose();

      phase = _resolve(
        AsyncValue.data(
          AuthState(AuthChangeEvent.signedIn, _platformInvitationSession),
        ),
      ).phase;
      router = AppRouter.create(phase: phase);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(find.text('Define tu contraseña'), findsOneWidget);
    });

    testWidgets('CB-04 ordinary signed-out cold start resolves to login',
        (tester) async {
      final state = _resolve(
        const AsyncValue.data(AuthState(AuthChangeEvent.initialSession, null)),
      );
      final router = AppRouter.create(phase: state.phase);
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Iniciar sesión'), findsOneWidget);
    });

    test('CB-05 ordinary persisted session remains authenticated', () {
      final state = _resolve(
        const AsyncValue.loading(),
        currentSession: _ordinarySession,
      );

      expect(state.phase, ProductiveAuthPhase.authenticated);
      expect(state.session, same(_ordinarySession));
    });

    test('CB-06 business invitation flag does not divert registered users', () {
      expect(
        _resolve(
          AsyncValue.data(
            AuthState(AuthChangeEvent.signedIn, _businessInvitationSession),
          ),
        ).phase,
        ProductiveAuthPhase.authenticated,
      );
    });

    test('CB-07 legacy platform invitation remains supported', () {
      expect(
        _resolve(
          AsyncValue.data(
            AuthState(AuthChangeEvent.signedIn, _platformInvitationSession),
          ),
        ).phase,
        ProductiveAuthPhase.passwordSetupRequired,
      );
    });

    testWidgets('CB-08 callback failure fails safely to login', (tester) async {
      final state = _resolve(
        const AsyncValue.error(
          AuthException('Invalid or expired callback'),
          StackTrace.empty,
        ),
      );
      expect(state.phase, ProductiveAuthPhase.unauthenticated);
      expect(state.streamError, isA<AuthException>());

      final router = AppRouter.create(phase: state.phase);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();

      expect(find.text('Iniciar sesión'), findsOneWidget);
      expect(find.textContaining('Invalid or expired'), findsNothing);
    });
  });
}

ProductiveAuthSessionState _resolve(
  AsyncValue<AuthState> change, {
  Session? currentSession,
}) {
  return resolveProductiveAuthSession(
    change: change,
    currentSession: currentSession,
  );
}

final _businessInvitationSession = _session(const {
  'business_member_invitation_requires_password_setup': true,
});
final _platformInvitationSession = _session(const {
  platformInvitationPasswordSetupMetadataKey: true,
});
final _ordinarySession = _session(const {});

Session _session(Map<String, dynamic> metadata) {
  return Session(
    accessToken: 'test-token',
    refreshToken: 'test-refresh',
    tokenType: 'bearer',
    user: User(
      id: 'invited-user',
      appMetadata: const {},
      userMetadata: metadata,
      aud: 'authenticated',
      email: 'invited@example.com',
      createdAt: '2026-09-16T00:00:00Z',
    ),
  );
}
