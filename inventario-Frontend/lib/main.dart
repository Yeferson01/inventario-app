import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/router/app_router.dart';
import 'app/theme/dark_theme.dart';
import 'app/theme/light_theme.dart';
import 'core/config/app_config.dart';
import 'features/debug/presentation/screens/debug_ping_screen.dart';
import 'features/auth/application/productive_auth_providers.dart';
import 'features/sync/application/app_router_sync_bootstrap_provider.dart';
import 'features/sync/presentation/widgets/app_router_sync_shell_gate.dart';

void main() {
  late final Zone bootstrapZone;
  runZonedGuarded(
    () async {
      bootstrapZone = Zone.current;
      WidgetsFlutterBinding.ensureInitialized();

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        debugPrint('FlutterError: ${details.exceptionAsString()}');
        debugPrintStack(stackTrace: details.stack);
      };

      if (const bool.fromEnvironment('BYPASS_MAIN_DEBUG')) {
        debugPrint(
          'BYPASS_MAIN_DEBUG activo: render directo antes de AppConfig/Supabase.',
        );
        runApp(
          const MaterialApp(
            debugShowCheckedModeBanner: false,
            home: DebugPingScreen(),
          ),
        );
        return;
      }

      try {
        debugPrint('BOOT: validando AppConfig...');
        AppConfig.validate();
        debugPrint('BOOT: AppConfig OK');

        if (const bool.fromEnvironment('CONFIG_ONLY_PING_DEBUG')) {
          runApp(
            const MaterialApp(
              debugShowCheckedModeBanner: false,
              home: DebugPingScreen(),
            ),
          );
          return;
        }

        debugPrint('BOOT: inicializando Supabase...');

        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          publishableKey: AppConfig.supabaseAnonKey,
        ).timeout(
          const Duration(seconds: 12),
          onTimeout: () {
            throw TimeoutException(
              'Supabase.initialize tardó más de 12 segundos.',
            );
          },
        );

        debugPrint('BOOT: Supabase OK');

        if (const bool.fromEnvironment('AFTER_INIT_PING_DEBUG')) {
          runApp(
            const MaterialApp(
              debugShowCheckedModeBanner: false,
              home: DebugPingScreen(),
            ),
          );
          return;
        }

        runApp(
          const ProviderScope(
            child: MyApp(
              appName: AppConfig.appName,
              apiUrl: AppConfig.apiUrl,
            ),
          ),
        );
      } catch (error, stackTrace) {
        debugPrint('BOOT ERROR: $error');
        debugPrintStack(stackTrace: stackTrace);

        runApp(
          BootstrapErrorApp(
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    },
    (error, stackTrace) {
      debugPrint('UNCAUGHT ZONE ERROR: $error');
      debugPrintStack(stackTrace: stackTrace);

      bootstrapZone.run(
        () => runApp(
          BootstrapErrorApp(
            error: error,
            stackTrace: stackTrace,
          ),
        ),
      );
    },
  );
}

class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({
    required this.error,
    required this.stackTrace,
    super.key,
  });

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Error de arranque'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: SelectableText(
              'La app falló antes de pintar la interfaz principal.\n\n'
              'Error:\n$error\n\n'
              'StackTrace:\n$stackTrace',
              style: const TextStyle(
                color: Colors.red,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends ConsumerWidget {
  final String appName;
  final String apiUrl;

  const MyApp({
    super.key,
    required this.appName,
    required this.apiUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final rootNavigatorKey = ref.watch(appRootNavigatorKeyProvider);
    ref.listen(productiveAuthSessionProvider, (previous, next) {
      if (previous?.user?.id != next.user?.id ||
          previous?.lastEvent != next.lastEvent) {
        ref.invalidate(appRouterSyncBootstrapProvider);
      }
    });
    if (const bool.fromEnvironment('ROUTER_MINIMAL_DEBUG')) {
      debugPrint('ROUTER_MINIMAL_DEBUG activo: MaterialApp.router mínimo.');
      return MaterialApp.router(
        debugShowCheckedModeBanner: false,
        routerConfig: router,
      );
    }

    if (const bool.fromEnvironment('BYPASS_ROUTER_DEBUG')) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: DebugPingScreen(),
      );
    }

    return ScreenUtilInit(
      designSize: const Size(390, 844),
      ensureScreenSize: true,
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          builder: (context, child) {
            if (const bool.fromEnvironment('DISABLE_SYNC_GATE')) {
              return child ?? const SizedBox.shrink();
            }

            return AppRouterSyncShellGate(
              navigatorContextResolver: () =>
                  rootNavigatorKey.currentState?.overlay?.context,
              child: child ?? const SizedBox.shrink(),
            );
          },
          title: appName,
          debugShowCheckedModeBanner: false,
          theme: AppLightTheme.theme,
          darkTheme: AppDarkTheme.theme,
          themeMode: ThemeMode.system,
          routerConfig: router,
        );
      },
    );
  }
}
