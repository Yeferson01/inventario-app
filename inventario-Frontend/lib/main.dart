import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'app/router/app_router.dart';
import 'app/theme/light_theme.dart';
import 'app/theme/dark_theme.dart';

void main() {
  // Captura las variables del Flavor inyectadas desde el JSON de entorno
  const appName = String.fromEnvironment('APP_NAME', defaultValue: 'Inventario Base');
  const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:3000');

  runApp(
    MyApp(
      appName: appName,
      apiUrl: apiUrl,
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
        // Usamos .router para que GoRouter maneje el árbol de páginas
        return MaterialApp.router(
          title: appName,
          debugShowCheckedModeBanner: false,
          
          // Inyección del Theme System (FlexColorScheme)
          theme: AppLightTheme.theme,
          darkTheme: AppDarkTheme.theme,
          themeMode: ThemeMode.system,
          
          // Configuración del Router
          routerConfig: AppRouter.router,
        );
      },
    );
  }
}