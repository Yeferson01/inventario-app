import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:inventario_frontend/main.dart';
import 'package:inventario_frontend/core/supabase/supabase_client_provider.dart';
import 'package:inventario_frontend/features/auth/application/productive_auth_providers.dart';
import 'package:inventario_frontend/features/sync/application/app_router_sync_bootstrap_provider.dart';

void main() {
  testWidgets('MyApp builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productiveAuthSessionProvider.overrideWithValue(
            const ProductiveAuthSessionState.unauthenticated(),
          ),
          currentSupabaseUserProvider.overrideWithValue(null),
          appRouterSyncBootstrapProvider.overrideWith(
            (ref) async => const AppRouterSyncBootstrapData(
              hasAuthenticatedUser: false,
            ),
          ),
        ],
        child: const MyApp(
          appName: 'Inventario Test',
          apiUrl: 'http://localhost:3000',
        ),
      ),
    );

    await tester.pump();

    expect(find.byType(MyApp), findsOneWidget);
  });
}
