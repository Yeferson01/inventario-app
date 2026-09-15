import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:inventario_frontend/app/router/app_router.dart';
import 'package:inventario_frontend/app/router/routes_constants.dart';
import 'package:inventario_frontend/features/auth/application/productive_auth_providers.dart';

void main() {
  testWidgets('debug initial route remains available in debug', (tester) async {
    final router = AppRouter.create(
      phase: ProductiveAuthPhase.unauthenticated,
      initialRouteName: 'debug_ping',
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Debug Ping'), findsOneWidget);
  });

  testWidgets('disabled diagnostics reject direct debug navigation',
      (tester) async {
    final router = AppRouter.create(
      phase: ProductiveAuthPhase.unauthenticated,
      enableDebugRoutes: false,
      initialRouteName: 'debug_login',
    );
    addTearDown(router.dispose);
    final paths = router.configuration.routes.whereType<GoRoute>().map(
          (route) => route.path,
        );
    expect(paths.any((path) => path.startsWith('/debug')), isFalse);
    expect(paths, contains(AppRoutes.passwordSetupPath));
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    expect(find.text('Iniciar sesión'), findsOneWidget);
    for (final path in [
      '/debug/login',
      '/debug/ping',
      '/debug/e2e-real-sync'
    ]) {
      router.go(path);
      await tester.pumpAndSettle();
      expect(find.text('Iniciar sesión'), findsOneWidget);
    }
  });

  test('accidental debug dart-defines fall back to a productive route', () {
    for (final name in ['debug_login', 'debug_ping', 'debug_e2e']) {
      expect(
        AppRouter.initialLocationFor(name, enableDebugRoutes: false),
        AppRouter.initialLocationFor('dashboard', enableDebugRoutes: false),
      );
    }
  });

  testWidgets('unauthenticated productive route resolves to Login',
      (tester) async {
    final router = AppRouter.create(
      phase: ProductiveAuthPhase.unauthenticated,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.textContaining('Regístrate'), findsNothing);
  });
}
