class AppConfig {
  static const String appName = String.fromEnvironment(
    'APP_NAME',
    defaultValue: 'Inventario Base',
  );

  static const String environment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'dev',
  );

  static const String apiUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'http://localhost:3000',
  );

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const String _configuredAuthRedirectUrl = String.fromEnvironment(
    'AUTH_REDIRECT_URL',
    defaultValue: '',
  );

  static String get authRedirectUrl {
    final configured = _configuredAuthRedirectUrl.trim();
    if (configured.isNotEmpty) return configured;
    return isProd
        ? 'cronosmanagement://auth-callback'
        : 'cronosmanagement-dev://auth-callback';
  }

  static bool get isDev => environment == 'dev';
  static bool get isProd => environment == 'prod';

  static void validate() {
    final missing = <String>[];

    if (supabaseUrl.trim().isEmpty) {
      missing.add('SUPABASE_URL');
    }

    if (supabaseAnonKey.trim().isEmpty) {
      missing.add('SUPABASE_ANON_KEY');
    }

    if (missing.isNotEmpty) {
      throw StateError(
        'Faltan variables de entorno requeridas: ${missing.join(', ')}. '
        'Ejecuta Flutter usando --dart-define-from-file=config/dev.json '
        'o --dart-define-from-file=config/prod.json.',
      );
    }
  }
}
