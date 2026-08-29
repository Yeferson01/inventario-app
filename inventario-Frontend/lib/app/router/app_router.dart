import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/administration/presentation/screens/administration_home_screen.dart';
import '../../features/administration/presentation/screens/business_branches_screen.dart';
import '../../features/administration/presentation/screens/business_team_screen.dart';
import '../../features/auth/application/productive_auth_providers.dart';
import '../../features/auth/presentation/screens/password_setup_screen.dart';
import '../../features/auth/presentation/screens/productive_login_screen.dart';
import '../../features/dashboard/presentation/dashboard_presentation.dart';
import '../../features/debug/presentation/screens/debug_ping_screen.dart';
import '../../features/debug/presentation/screens/debug_supabase_login_screen.dart';
import '../../features/sync/presentation/screens/app_e2e_real_controlled_test_screen.dart';
import 'routes_constants.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final routeAuthority = ref.watch(
    productiveAuthSessionProvider.select(
      (state) => (state.phase, state.user?.id),
    ),
  );
  final router = AppRouter.create(phase: routeAuthority.$1);
  ref.onDispose(router.dispose);
  return router;
});

class AppRouter {
  AppRouter._();

  static String get _initialLocation {
    const routeName = String.fromEnvironment(
      'APP_INITIAL_ROUTE_NAME',
      defaultValue: 'dashboard',
    );

    return switch (routeName) {
      'debug_login' => '/debug/login',
      'debug_ping' => '/debug/ping',
      'debug_e2e' => '/debug/e2e-real-sync',
      'login' || 'register' => AppRoutes.loginPath,
      'inventory' => AppRoutes.inventarioPath,
      _ => AppRoutes.dashboardPath,
    };
  }

  static GoRouter create({required ProductiveAuthPhase phase}) {
    return GoRouter(
      initialLocation: _initialLocation,
      navigatorKey: GlobalKey<NavigatorState>(),
      debugLogDiagnostics: true,
      redirect: (context, state) {
        final location = state.uri.path;
        if (location.startsWith('/debug')) return null;

        final isLogin = location == AppRoutes.loginPath;
        final isPasswordSetup = location == AppRoutes.passwordSetupPath;
        if (location == AppRoutes.registerPath) return AppRoutes.loginPath;

        return switch (phase) {
          ProductiveAuthPhase.initializing =>
            isLogin ? null : AppRoutes.loginPath,
          ProductiveAuthPhase.unauthenticated =>
            isLogin ? null : AppRoutes.loginPath,
          ProductiveAuthPhase.passwordSetupRequired =>
            isPasswordSetup ? null : AppRoutes.passwordSetupPath,
          ProductiveAuthPhase.authenticated =>
            (isLogin || isPasswordSetup) ? AppRoutes.dashboardPath : null,
        };
      },
      routes: [
        GoRoute(
          path: '/debug/login',
          builder: (context, state) => const DebugSupabaseLoginScreen(),
        ),
        GoRoute(
          path: '/debug/ping',
          builder: (context, state) => const DebugPingScreen(),
        ),
        GoRoute(
          path: '/debug/e2e-real-sync',
          builder: (context, state) => const AppE2ERealControlledTestScreen(),
        ),
        GoRoute(
          path: AppRoutes.loginPath,
          name: AppRoutes.loginName,
          builder: (context, state) => const ProductiveLoginScreen(),
        ),
        GoRoute(
          path: AppRoutes.passwordSetupPath,
          name: AppRoutes.passwordSetupName,
          builder: (context, state) => const PasswordSetupScreen(),
        ),
        GoRoute(
          path: AppRoutes.dashboardPath,
          name: AppRoutes.dashboardName,
          builder: (context, state) => const MainDashboardScreen(),
        ),
        GoRoute(
          path: AppRoutes.inventarioPath,
          name: AppRoutes.inventarioName,
          builder: (context, state) => const TemporaryInventarioView(),
        ),
        GoRoute(
          path: AppRoutes.administrationPath,
          name: AppRoutes.administrationName,
          builder: (context, state) => const AdministrationHomeScreen(),
        ),
        GoRoute(
          path: AppRoutes.administrationBranchesPath,
          name: AppRoutes.administrationBranchesName,
          builder: (context, state) => const BusinessBranchesScreen(),
        ),
        GoRoute(
          path: AppRoutes.administrationTeamPath,
          name: AppRoutes.administrationTeamName,
          builder: (context, state) => const BusinessTeamScreen(),
        ),
      ],
      errorBuilder: (context, state) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No se encontró la pantalla solicitada.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class TemporaryInventarioView extends StatelessWidget {
  const TemporaryInventarioView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Módulo de Inventario')),
      body: const Center(child: Text('Inventario operativo')),
    );
  }
}
