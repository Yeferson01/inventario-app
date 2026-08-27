import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/supabase/supabase_client_provider.dart';
import 'package:inventario_frontend/features/sync/application/app_router_sync_bootstrap_provider.dart';
import 'package:inventario_frontend/features/sync/presentation/widgets/app_router_sync_shell_gate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AppRouterSyncShellGate', () {
    testWidgets(
      'authenticated user with stale unauthenticated bootstrap stays loading',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              currentSupabaseUserProvider.overrideWithValue(_user),
              appRouterSyncBootstrapProvider.overrideWithValue(
                const AsyncValue.data(
                  AppRouterSyncBootstrapData(
                    hasAuthenticatedUser: false,
                  ),
                ),
              ),
            ],
            child: const MaterialApp(
              home: AppRouterSyncShellGate(
                child: Text('Not authorized technical error'),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.textContaining('Not authorized'), findsNothing);
      },
    );

    testWidgets('unauthenticated user can render the public child',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentSupabaseUserProvider.overrideWithValue(null),
            appRouterSyncBootstrapProvider.overrideWithValue(
              const AsyncValue.data(
                AppRouterSyncBootstrapData(
                  hasAuthenticatedUser: false,
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: AppRouterSyncShellGate(child: Text('Login público')),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Login público'), findsOneWidget);
    });
  });
}

const _user = User(
  id: 'profile-a',
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  email: 'owner@example.com',
  createdAt: '2026-08-27T00:00:00Z',
);
