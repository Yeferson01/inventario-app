class AppRoutes {
  AppRoutes._();

  // --- Rutas Públicas ---
  static const String loginPath = '/login';
  static const String loginName = 'login';

  static const String registerPath = '/register';
  static const String registerName = 'register';

  // --- Rutas Privadas (Requieren Auth) ---
  static const String dashboardPath = '/';
  static const String dashboardName = 'dashboard';

  static const String inventarioPath = '/inventario';
  static const String inventarioName = 'inventario';
}
