import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'routes_constants.dart';

// SIMULADOR TEMPORAL DE AUTH (Cambiar a 'true' para probar rutas privadas, 'false' para públicas)
bool _isUserLoggedInSimulated = true;

class AppRouter {
  AppRouter._();

  // Clave global para manejar el contexto de navegación a nivel raíz
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.dashboardPath,
    debugLogDiagnostics:
        true, // Loguea en consola los cambios de ruta en desarrollo

    // 🛡️ GUARDS & REDIRECTS: Interceptor global de seguridad
    redirect: (BuildContext context, GoRouterState state) {
      final isGoingToLogin = state.matchedLocation == AppRoutes.loginPath;
      final isGoingToRegister = state.matchedLocation == AppRoutes.registerPath;

      // Si está intentando ir a una ruta pública (como registro)
      final isGoingToPublic = isGoingToLogin || isGoingToRegister;

      // Caso 1: El usuario NO está autenticado y quiere entrar a una ruta privada
      if (!_isUserLoggedInSimulated && !isGoingToPublic) {
        return AppRoutes.loginPath; // Redirigir a la fuerza al Login
      }

      // Caso 2: El usuario YA está autenticado e intenta ir al Login o Registro
      if (_isUserLoggedInSimulated && isGoingToPublic) {
        return AppRoutes.dashboardPath; // Redirigir al área privada (Dashboard)
      }

      // Caso 3: No se requiere ninguna redirección, continuar el flujo normal
      return null;
    },

    // 🗺️ DEFINICIÓN DE RUTAS
    routes: [
      // --- RUTAS PÚBLICAS ---
      GoRoute(
        path: AppRoutes.loginPath,
        name: AppRoutes.loginName,
        builder: (context, state) => const TemporaryLoginView(),
      ),
      GoRoute(
        path: AppRoutes.registerPath,
        name: AppRoutes.registerName,
        builder: (context, state) => const TemporaryRegisterView(),
      ),

      // --- RUTAS PRIVADAS ---
      GoRoute(
        path: AppRoutes.dashboardPath,
        name: AppRoutes.dashboardName,
        builder: (context, state) => const TemporaryDashboardView(),
      ),
      GoRoute(
        path: AppRoutes.inventarioPath,
        name: AppRoutes.inventarioName,
        builder: (context, state) => const TemporaryInventarioView(),
      ),
    ],

    // Vista de error global por si se intenta acceder a una ruta inexistente
    errorBuilder: (context, state) => const Scaffold(
      body: Center(child: Text('404 - Página no encontrada')),
    ),
  );
}

// =============================================================================
// VISTAS TEMPORALES PARA VALIDAR LA NAVEGACIÓN Y COMPROBAR EL THEME SYSTEM
// =============================================================================

class TemporaryLoginView extends StatelessWidget {
  const TemporaryLoginView({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('🔑 Pantalla de Login', style: theme.textTheme.headlineLarge),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.goNamed(AppRoutes.registerName),
              child: const Text('¿No tienes cuenta? Regístrate'),
            ),
          ],
        ),
      ),
    );
  }
}

class TemporaryRegisterView extends StatelessWidget {
  const TemporaryRegisterView({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Registro')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => context.goNamed(AppRoutes.loginName),
          child: const Text('Volver al Login'),
        ),
      ),
    );
  }
}

class TemporaryDashboardView extends StatelessWidget {
  const TemporaryDashboardView({super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard Principal')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Bienvenido al Sistema SaaS',
                style: theme.textTheme.headlineLarge),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => context.goNamed(AppRoutes.inventarioName),
              child: const Text('Ir a Gestión de Inventario'),
            ),
          ],
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
      body: const Center(
          child: Text('📦 Aquí se listarán tus productos (Fase 3)')),
    );
  }
}
