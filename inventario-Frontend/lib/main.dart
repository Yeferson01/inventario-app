import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/router/app_router.dart';
import 'app/theme/dark_theme.dart';
import 'app/theme/light_theme.dart';
import 'core/config/app_config.dart';
import 'features/sync/presentation/widgets/app_router_sync_shell_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  AppConfig.validate();

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseAnonKey,
  );

  runApp(
    const ProviderScope(
      child: MyApp(
        appName: AppConfig.appName,
        apiUrl: AppConfig.apiUrl,
      ),
    ),
  );
}

class MyApp extends StatelessWidget {
  final String appName;
  final String apiUrl;

  const MyApp({
    super.key,
    required this.appName,
    required this.apiUrl,
  });

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        return MaterialApp.router(
          builder: (context, child) {
            return AppRouterSyncShellGate(
              child: child ?? const SizedBox.shrink(),
            );
          },
          title: appName,
          debugShowCheckedModeBanner: false,
          theme: AppLightTheme.theme,
          darkTheme: AppDarkTheme.theme,
          themeMode: ThemeMode.system,
          routerConfig: AppRouter.router,
        );
      },
    );
  }
}
