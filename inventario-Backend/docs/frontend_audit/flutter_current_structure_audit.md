# Auditoría Flutter actual — Fase 6.18C.1

Fecha: Tue Jun 23 16:03:41 HPS 2026

## Ruta actual
/c/Users/Cronos/Developer/personal/inventario-app

## Carpetas principales
.
./.git
./.git/gk
./.git/hooks
./.git/info
./.git/logs
./.git/objects
./.git/refs
./inventario-Backend
./inventario-Backend/backups
./inventario-Backend/docs
./inventario-Backend/node_modules
./inventario-Backend/scripts
./inventario-Backend/supabase
./inventario-Frontend
./inventario-Frontend/.dart_tool
./inventario-Frontend/.idea
./inventario-Frontend/android
./inventario-Frontend/build
./inventario-Frontend/config
./inventario-Frontend/ios
./inventario-Frontend/lib
./inventario-Frontend/linux
./inventario-Frontend/macos
./inventario-Frontend/test
./inventario-Frontend/web
./inventario-Frontend/windows

## Archivos principales del frontend
inventario-Frontend/.dart_tool/package_config.json
inventario-Frontend/.dart_tool/package_graph.json
inventario-Frontend/.dart_tool/version
inventario-Frontend/.flutter-plugins-dependencies
inventario-Frontend/.idea/modules.xml
inventario-Frontend/.idea/workspace.xml
inventario-Frontend/.metadata
inventario-Frontend/README.md
inventario-Frontend/analysis_options.yaml
inventario-Frontend/android/.gitignore
inventario-Frontend/android/build.gradle.kts
inventario-Frontend/android/gradle.properties
inventario-Frontend/android/gradlew
inventario-Frontend/android/gradlew.bat
inventario-Frontend/android/inventario_frontend_android.iml
inventario-Frontend/android/local.properties
inventario-Frontend/android/settings.gradle.kts
inventario-Frontend/config/dev.json
inventario-Frontend/config/prod.json
inventario-Frontend/inventario_frontend.iml
inventario-Frontend/ios/.gitignore
inventario-Frontend/lib/main.dart
inventario-Frontend/linux/.gitignore
inventario-Frontend/linux/CMakeLists.txt
inventario-Frontend/macos/.gitignore
inventario-Frontend/pubspec.lock
inventario-Frontend/pubspec.yaml
inventario-Frontend/test/database_test.dart
inventario-Frontend/test/widget_test.dart
inventario-Frontend/web/favicon.png
inventario-Frontend/web/index.html
inventario-Frontend/web/manifest.json
inventario-Frontend/windows/.gitignore
inventario-Frontend/windows/CMakeLists.txt

## Estructura lib/ hasta profundidad 5
inventario-Frontend/lib/app/router/app_router.dart
inventario-Frontend/lib/app/router/routes_constants.dart
inventario-Frontend/lib/app/theme/colors.dart
inventario-Frontend/lib/app/theme/dark_theme.dart
inventario-Frontend/lib/app/theme/light_theme.dart
inventario-Frontend/lib/app/theme/radius.dart
inventario-Frontend/lib/app/theme/shadows.dart
inventario-Frontend/lib/app/theme/spacing.dart
inventario-Frontend/lib/app/theme/typography.dart
inventario-Frontend/lib/core/database/app_database.dart
inventario-Frontend/lib/core/database/app_database.g.dart
inventario-Frontend/lib/features/auth/data/datasources/business_dao.dart
inventario-Frontend/lib/features/auth/data/datasources/profile_dao.dart
inventario-Frontend/lib/features/customers/data/datasources/customer_dao.dart
inventario-Frontend/lib/features/inventory/data/datasources/category_dao.dart
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart
inventario-Frontend/lib/main.dart

## Conteo de archivos Dart
19

## pubspec.yaml
name: inventario_frontend
description: "A new Flutter project."
# The following line prevents the package from being accidentally published to
# pub.dev using `flutter pub publish`. This is preferred for private packages.
publish_to: 'none' # Remove this line if you wish to publish to pub.dev

# The following defines the version and build number for your application.
# A version number is three numbers separated by dots, like 1.2.43
# followed by an optional build number separated by a +.
# Both the version and the builder number may be overridden in flutter
# build by specifying --build-name and --build-number, respectively.
# In Android, build-name is used as versionName while build-number used as versionCode.
# Read more about Android versioning at https://developer.android.com/studio/publish/versioning
# In iOS, build-name is used as CFBundleShortVersionString while build-number is used as CFBundleVersion.
# Read more about iOS versioning at
# https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html
# In Windows, build-name is used as the major, minor, and patch parts
# of the product and file versions while build-number is used as the build suffix.
version: 1.0.0+1

environment:
  sdk: '>=3.3.0 <4.0.0'

# Dependencies specify other packages that your package needs in order to work.
# To automatically upgrade your package dependencies to the latest versions
# consider running `flutter pub upgrade --major-versions`. Alternatively,
# dependencies can be manually updated by changing the version numbers below to
# the latest version available on pub.dev. To see which dependencies have newer
# versions available, run `flutter pub outdated`.
dependencies:
  flutter:
    sdk: flutter

  # Iconos nativos de iOS
  cupertino_icons: ^1.0.8

  # Estado global y Navegación
  flutter_riverpod: ^3.3.1
  go_router: ^17.3.0

  # Networking y Backend
  dio: ^5.5.0
  supabase_flutter: ^2.6.0

  # Base de datos local (Offline-First)
  drift: ^2.20.1
  path_provider: ^2.1.3
  path: ^1.9.0

  # UI y Diseño
  flex_color_scheme: ^8.4.0
  flutter_screenutil: ^5.9.3

  # Utilidades y Modelado
  freezed_annotation: ^3.1.0
  json_annotation: ^4.9.0
  intl: ^0.20.2
  uuid: ^4.4.0
  logger: ^2.3.0

dev_dependencies:
  flutter_test:
    sdk: flutter

  # Analizador de buenas prácticas de código
  flutter_lints: ^6.0.0

  # Generadores de Código estables acoplados a la perfección
  build_runner: ^2.4.9
  drift_dev: ^2.20.1
  freezed: ^3.2.5
  json_serializable: ^6.8.0

# The following section is specific to Flutter packages.
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application, so that you can use the icons in
  # the material Icons class.
  uses-material-design: true

  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
  #   - images/a_dot_ham.jpeg

  # An image asset can refer to one or more resolution-specific "variants", see
  # https://flutter.dev/to/resolution-aware-images

  # For details regarding adding assets from package dependencies, see
  # https://flutter.dev/to/asset-from-package

  # To add custom fonts to your application, add a fonts section here,
  # in this "flutter" section. Each entry in this list should have a
  # "family" key with the font family name, and a "fonts" key with a
  # list giving the asset and other descriptors for the font. For
  # example:
  # fonts:
  #   - family: Schyler
  #     fonts:
  #       - asset: fonts/Schyler-Regular.ttf
  #       - asset: fonts/Schyler-Italic.ttf
  #         style: italic
  #   - family: Trajan Pro
  #     fonts:
  #       - asset: fonts/TrajanPro.ttf
  #       - asset: fonts/TrajanPro_Bold.ttf
  #         weight: 700
  #
  # For details regarding fonts from package dependencies,
  # see https://flutter.dev/to/font-from-package

## main.dart
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
## Dependencias/patrones detectados

### Supabase
inventario-Frontend/lib/core/database/app_database.dart:31:  TextColumn get id => text()(); // UUID de Supabase mapped como String
inventario-Frontend/lib/main.dart:3:import 'package:supabase_flutter/supabase_flutter.dart';
inventario-Frontend/pubspec.yaml:43:  supabase_flutter: ^2.6.0

### Base local: Drift / SQLite / Hive / SharedPreferences
inventario-Frontend/lib/core/database/app_database.dart:2:import 'package:drift/drift.dart';
inventario-Frontend/lib/core/database/app_database.dart:3:import 'package:drift/native.dart';
inventario-Frontend/lib/core/database/app_database.dart:26:// DEFINICIÓN DE TABLAS LOCALES (DRIFT)
inventario-Frontend/lib/core/database/app_database.dart:199:// CLASE CENTRAL DE BASE DE DATOS DRIFT
inventario-Frontend/lib/core/database/app_database.dart:202:@DriftDatabase(
inventario-Frontend/lib/core/database/app_database.dart:250:    final file = File(p.join(dbFolder.path, 'app_local_database.sqlite'));
inventario-Frontend/lib/core/database/app_database.g.dart:16:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:21:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:27:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:33:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:38:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:43:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:51:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:57:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:64:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:72:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:80:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:88:      type: DriftSqlType.dateTime, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:92:              type: DriftSqlType.int,
inventario-Frontend/lib/core/database/app_database.g.dart:187:          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:189:          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:191:          .read(DriftSqlType.string, data['${effectivePrefix}business_type']),
inventario-Frontend/lib/core/database/app_database.g.dart:193:          .read(DriftSqlType.string, data['${effectivePrefix}owner_name']),
inventario-Frontend/lib/core/database/app_database.g.dart:195:          .read(DriftSqlType.string, data['${effectivePrefix}phone']),
inventario-Frontend/lib/core/database/app_database.g.dart:197:          .read(DriftSqlType.string, data['${effectivePrefix}email']),
inventario-Frontend/lib/core/database/app_database.g.dart:199:          .read(DriftSqlType.string, data['${effectivePrefix}address']),
inventario-Frontend/lib/core/database/app_database.g.dart:201:          DriftSqlType.string, data['${effectivePrefix}subscription_plan'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:203:          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:205:          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:207:          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:209:          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
inventario-Frontend/lib/core/database/app_database.g.dart:212:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:317:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:337:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:658:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:664:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:673:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:678:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:683:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:691:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:699:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:705:              type: DriftSqlType.int,
inventario-Frontend/lib/core/database/app_database.g.dart:771:          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:773:          .read(DriftSqlType.string, data['${effectivePrefix}business_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:775:          .read(DriftSqlType.string, data['${effectivePrefix}full_name']),
inventario-Frontend/lib/core/database/app_database.g.dart:777:          .read(DriftSqlType.string, data['${effectivePrefix}role']),
inventario-Frontend/lib/core/database/app_database.g.dart:779:          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:781:          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:783:          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:786:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:859:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:874:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:1094:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:1100:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:1108:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:1114:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:1120:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:1128:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:1136:      type: DriftSqlType.dateTime, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:1140:              type: DriftSqlType.int,
inventario-Frontend/lib/core/database/app_database.g.dart:1210:          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:1212:          .read(DriftSqlType.string, data['${effectivePrefix}business_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:1214:          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:1216:          .read(DriftSqlType.string, data['${effectivePrefix}description']),
inventario-Frontend/lib/core/database/app_database.g.dart:1218:          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:1220:          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:1222:          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
inventario-Frontend/lib/core/database/app_database.g.dart:1225:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:1300:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:1315:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:1537:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:1543:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:1552:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:1557:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:1562:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:1568:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:1574:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:1582:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:1590:      type: DriftSqlType.dateTime, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:1594:              type: DriftSqlType.int,
inventario-Frontend/lib/core/database/app_database.g.dart:1672:          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:1674:          .read(DriftSqlType.string, data['${effectivePrefix}business_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:1676:          .read(DriftSqlType.string, data['${effectivePrefix}full_name'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:1678:          .read(DriftSqlType.string, data['${effectivePrefix}phone']),
inventario-Frontend/lib/core/database/app_database.g.dart:1680:          .read(DriftSqlType.string, data['${effectivePrefix}email']),
inventario-Frontend/lib/core/database/app_database.g.dart:1682:          .read(DriftSqlType.string, data['${effectivePrefix}address']),
inventario-Frontend/lib/core/database/app_database.g.dart:1684:          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:1686:          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:1688:          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
inventario-Frontend/lib/core/database/app_database.g.dart:1691:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:1780:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:1797:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:2051:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:2057:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:2066:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:2075:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:2080:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:2086:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:2092:      type: DriftSqlType.double,
inventario-Frontend/lib/core/database/app_database.g.dart:2100:      type: DriftSqlType.double, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:2106:      type: DriftSqlType.int,
inventario-Frontend/lib/core/database/app_database.g.dart:2114:      type: DriftSqlType.int,
inventario-Frontend/lib/core/database/app_database.g.dart:2121:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:2128:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:2136:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:2144:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:2152:      type: DriftSqlType.dateTime, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:2158:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:2162:              type: DriftSqlType.int,
inventario-Frontend/lib/core/database/app_database.g.dart:2289:          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:2291:          .read(DriftSqlType.string, data['${effectivePrefix}business_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:2293:          .read(DriftSqlType.string, data['${effectivePrefix}category_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:2295:          .read(DriftSqlType.string, data['${effectivePrefix}barcode']),
inventario-Frontend/lib/core/database/app_database.g.dart:2297:          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:2299:          .read(DriftSqlType.string, data['${effectivePrefix}description']),
inventario-Frontend/lib/core/database/app_database.g.dart:2301:          .read(DriftSqlType.double, data['${effectivePrefix}purchase_price'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:2303:          .read(DriftSqlType.double, data['${effectivePrefix}sale_price'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:2305:          .read(DriftSqlType.int, data['${effectivePrefix}stock_quantity'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:2307:          .read(DriftSqlType.int, data['${effectivePrefix}minimum_stock'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:2309:          .read(DriftSqlType.string, data['${effectivePrefix}unit'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:2311:          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:2313:          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:2315:          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:2317:          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
inventario-Frontend/lib/core/database/app_database.g.dart:2319:          .read(DriftSqlType.string, data['${effectivePrefix}simple_category']),
inventario-Frontend/lib/core/database/app_database.g.dart:2322:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:2445:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:2469:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:2870:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:2876:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:2884:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:2893:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:2901:      type: DriftSqlType.double, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:2907:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:2912:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:2920:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:2928:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:2936:      type: DriftSqlType.dateTime, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:2940:              type: DriftSqlType.int,
inventario-Frontend/lib/core/database/app_database.g.dart:3027:          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:3029:          .read(DriftSqlType.string, data['${effectivePrefix}business_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:3031:          .read(DriftSqlType.string, data['${effectivePrefix}user_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:3033:          .read(DriftSqlType.string, data['${effectivePrefix}customer_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:3035:          .read(DriftSqlType.double, data['${effectivePrefix}total'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:3037:          .read(DriftSqlType.string, data['${effectivePrefix}payment_method']),
inventario-Frontend/lib/core/database/app_database.g.dart:3039:          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:3041:          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:3043:          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:3045:          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
inventario-Frontend/lib/core/database/app_database.g.dart:3048:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:3142:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:3160:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:3436:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:3441:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:3450:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:3459:      type: DriftSqlType.int, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:3465:      type: DriftSqlType.double, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:3471:      type: DriftSqlType.double, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:3477:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:3483:              type: DriftSqlType.int,
inventario-Frontend/lib/core/database/app_database.g.dart:3553:          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:3555:          .read(DriftSqlType.string, data['${effectivePrefix}sale_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:3557:          .read(DriftSqlType.string, data['${effectivePrefix}product_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:3559:          .read(DriftSqlType.int, data['${effectivePrefix}quantity'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:3561:          .read(DriftSqlType.double, data['${effectivePrefix}unit_price'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:3563:          .read(DriftSqlType.double, data['${effectivePrefix}subtotal'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:3565:          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:3568:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:3638:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:3653:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:3875:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:3881:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:3890:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:3895:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:3903:      type: DriftSqlType.double, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:3908:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:3916:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:3924:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:3932:      type: DriftSqlType.dateTime, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:3938:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:3944:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:3952:      type: DriftSqlType.string, requiredDuringInsert: false);
inventario-Frontend/lib/core/database/app_database.g.dart:3956:              type: DriftSqlType.int,
inventario-Frontend/lib/core/database/app_database.g.dart:4057:          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:4059:          .read(DriftSqlType.string, data['${effectivePrefix}business_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:4061:          .read(DriftSqlType.string, data['${effectivePrefix}supplier_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:4063:          .read(DriftSqlType.string, data['${effectivePrefix}user_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:4065:          .read(DriftSqlType.double, data['${effectivePrefix}total'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:4067:          .read(DriftSqlType.string, data['${effectivePrefix}status'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:4069:          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:4071:          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:4073:          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
inventario-Frontend/lib/core/database/app_database.g.dart:4075:          DriftSqlType.string, data['${effectivePrefix}invoice_photo_url']),
inventario-Frontend/lib/core/database/app_database.g.dart:4077:          DriftSqlType.string, data['${effectivePrefix}processing_status'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:4079:          .read(DriftSqlType.string, data['${effectivePrefix}supplier_name']),
inventario-Frontend/lib/core/database/app_database.g.dart:4082:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:4188:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:4208:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:4536:      type: DriftSqlType.string, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:4542:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:4551:      type: DriftSqlType.string,
inventario-Frontend/lib/core/database/app_database.g.dart:4560:      type: DriftSqlType.int, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:4566:      type: DriftSqlType.double, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:4572:      type: DriftSqlType.double, requiredDuringInsert: true);
inventario-Frontend/lib/core/database/app_database.g.dart:4578:      type: DriftSqlType.dateTime,
inventario-Frontend/lib/core/database/app_database.g.dart:4584:              type: DriftSqlType.int,
inventario-Frontend/lib/core/database/app_database.g.dart:4656:          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:4658:          .read(DriftSqlType.string, data['${effectivePrefix}purchase_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:4660:          .read(DriftSqlType.string, data['${effectivePrefix}product_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:4662:          .read(DriftSqlType.int, data['${effectivePrefix}quantity'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:4664:          .read(DriftSqlType.double, data['${effectivePrefix}unit_cost'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:4666:          .read(DriftSqlType.double, data['${effectivePrefix}subtotal'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:4668:          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:4671:              .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:4742:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/core/database/app_database.g.dart:4757:    serializer ??= driftRuntimeOptions.defaultSerializer;
inventario-Frontend/lib/features/auth/data/datasources/business_dao.dart:3:@DriftAccessor(tables: [Businesses])
inventario-Frontend/lib/features/auth/data/datasources/profile_dao.dart:3:@DriftAccessor(tables: [Profiles])
inventario-Frontend/lib/features/customers/data/datasources/customer_dao.dart:3:@DriftAccessor(tables: [Customers])
inventario-Frontend/lib/features/inventory/data/datasources/category_dao.dart:3:@DriftAccessor(tables: [Categories])
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:3:@DriftAccessor(tables: [Products, Categories])
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:3:@DriftAccessor(tables: [Purchases, PurchaseItems, Products])
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:3:@DriftAccessor(tables: [Sales, SaleItems, Products])
inventario-Frontend/pubspec.yaml:16:# https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html
inventario-Frontend/pubspec.yaml:46:  drift: ^2.20.1
inventario-Frontend/pubspec.yaml:70:  drift_dev: ^2.20.1

### Navegación
inventario-Frontend/lib/app/router/app_router.dart:2:import 'package:go_router/go_router.dart';
inventario-Frontend/lib/app/router/app_router.dart:12:  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
inventario-Frontend/lib/app/router/app_router.dart:15:    navigatorKey: _rootNavigatorKey,
inventario-Frontend/lib/app/router/app_router.dart:42:    routes: [
inventario-Frontend/lib/main.dart:39:        return MaterialApp.router(
inventario-Frontend/pubspec.yaml:39:  go_router: ^17.3.0

### Estado: Riverpod / Provider / Bloc / GetX
inventario-Frontend/lib/core/database/app_database.dart:4:import 'package:path_provider/path_provider.dart';
inventario-Frontend/pubspec.yaml:38:  flutter_riverpod: ^3.3.1
inventario-Frontend/pubspec.yaml:47:  path_provider: ^2.1.3

### Conectividad / offline
inventario-Frontend/lib/core/database/app_database.dart:17:/// Estado de sincronización local para el Sync Engine (Fase 4)
inventario-Frontend/lib/core/database/app_database.dart:18:enum SyncStatus {
inventario-Frontend/lib/core/database/app_database.dart:19:  synced,
inventario-Frontend/lib/core/database/app_database.dart:44:  // Control Local Offline-First
inventario-Frontend/lib/core/database/app_database.dart:45:  IntColumn get syncStatus => intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();
inventario-Frontend/lib/core/database/app_database.dart:61:  IntColumn get syncStatus => intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();
inventario-Frontend/lib/core/database/app_database.dart:77:  IntColumn get syncStatus => intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();
inventario-Frontend/lib/core/database/app_database.dart:95:  IntColumn get syncStatus => intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();
inventario-Frontend/lib/core/database/app_database.dart:120:  IntColumn get syncStatus => intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();
inventario-Frontend/lib/core/database/app_database.dart:139:  IntColumn get syncStatus => intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();
inventario-Frontend/lib/core/database/app_database.dart:155:  IntColumn get syncStatus => intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();
inventario-Frontend/lib/core/database/app_database.dart:175:  // Control Local Offline-First
inventario-Frontend/lib/core/database/app_database.dart:176:  IntColumn get syncStatus => intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();
inventario-Frontend/lib/core/database/app_database.dart:192:  IntColumn get syncStatus => intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();
inventario-Frontend/lib/core/database/app_database.dart:237:        onCreate: (m) async {
inventario-Frontend/lib/core/database/app_database.dart:240:        onUpgrade: (m, from, to) async {
inventario-Frontend/lib/core/database/app_database.dart:248:  return LazyDatabase(() async {
inventario-Frontend/lib/core/database/app_database.g.dart:90:  late final GeneratedColumnWithTypeConverter<SyncStatus, int> syncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:91:      GeneratedColumn<int>('sync_status', aliasedName, false,
inventario-Frontend/lib/core/database/app_database.g.dart:94:              defaultValue: Constant(SyncStatus.synced.index))
inventario-Frontend/lib/core/database/app_database.g.dart:95:          .withConverter<SyncStatus>($BusinessesTable.$convertersyncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:110:        syncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:210:      syncStatus: $BusinessesTable.$convertersyncStatus.fromSql(attachedDatabase
inventario-Frontend/lib/core/database/app_database.g.dart:212:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:221:  static JsonTypeConverter2<SyncStatus, int, int> $convertersyncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:222:      const EnumIndexConverter<SyncStatus>(SyncStatus.values);
inventario-Frontend/lib/core/database/app_database.g.dart:238:  final SyncStatus syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:252:      required this.syncStatus});
inventario-Frontend/lib/core/database/app_database.g.dart:281:      map['sync_status'] = Variable<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:282:          $BusinessesTable.$convertersyncStatus.toSql(syncStatus));
inventario-Frontend/lib/core/database/app_database.g.dart:311:      syncStatus: Value(syncStatus),
inventario-Frontend/lib/core/database/app_database.g.dart:331:      syncStatus: $BusinessesTable.$convertersyncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:332:          .fromJson(serializer.fromJson<int>(json['syncStatus'])),
inventario-Frontend/lib/core/database/app_database.g.dart:351:      'syncStatus': serializer.toJson<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:352:          $BusinessesTable.$convertersyncStatus.toJson(syncStatus)),
inventario-Frontend/lib/core/database/app_database.g.dart:369:          SyncStatus? syncStatus}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:384:        syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:404:      syncStatus:
inventario-Frontend/lib/core/database/app_database.g.dart:405:          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:424:          ..write('syncStatus: $syncStatus')
inventario-Frontend/lib/core/database/app_database.g.dart:443:      syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:460:          other.syncStatus == this.syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:476:  final Value<SyncStatus> syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:491:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:507:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:524:    Expression<int>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:540:      if (syncStatus != null) 'sync_status': syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:558:      Value<SyncStatus>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:573:      syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:617:    if (syncStatus.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:618:      map['sync_status'] = Variable<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:619:          $BusinessesTable.$convertersyncStatus.toSql(syncStatus.value));
inventario-Frontend/lib/core/database/app_database.g.dart:642:          ..write('syncStatus: $syncStatus, ')
inventario-Frontend/lib/core/database/app_database.g.dart:703:  late final GeneratedColumnWithTypeConverter<SyncStatus, int> syncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:704:      GeneratedColumn<int>('sync_status', aliasedName, false,
inventario-Frontend/lib/core/database/app_database.g.dart:707:              defaultValue: Constant(SyncStatus.synced.index))
inventario-Frontend/lib/core/database/app_database.g.dart:708:          .withConverter<SyncStatus>($ProfilesTable.$convertersyncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:718:        syncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:784:      syncStatus: $ProfilesTable.$convertersyncStatus.fromSql(attachedDatabase
inventario-Frontend/lib/core/database/app_database.g.dart:786:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:795:  static JsonTypeConverter2<SyncStatus, int, int> $convertersyncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:796:      const EnumIndexConverter<SyncStatus>(SyncStatus.values);
inventario-Frontend/lib/core/database/app_database.g.dart:807:  final SyncStatus syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:816:      required this.syncStatus});
inventario-Frontend/lib/core/database/app_database.g.dart:834:      map['sync_status'] =
inventario-Frontend/lib/core/database/app_database.g.dart:835:          Variable<int>($ProfilesTable.$convertersyncStatus.toSql(syncStatus));
inventario-Frontend/lib/core/database/app_database.g.dart:853:      syncStatus: Value(syncStatus),
inventario-Frontend/lib/core/database/app_database.g.dart:868:      syncStatus: $ProfilesTable.$convertersyncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:869:          .fromJson(serializer.fromJson<int>(json['syncStatus'])),
inventario-Frontend/lib/core/database/app_database.g.dart:883:      'syncStatus': serializer
inventario-Frontend/lib/core/database/app_database.g.dart:884:          .toJson<int>($ProfilesTable.$convertersyncStatus.toJson(syncStatus)),
inventario-Frontend/lib/core/database/app_database.g.dart:896:          SyncStatus? syncStatus}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:905:        syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:917:      syncStatus:
inventario-Frontend/lib/core/database/app_database.g.dart:918:          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:932:          ..write('syncStatus: $syncStatus')
inventario-Frontend/lib/core/database/app_database.g.dart:939:      id, businessId, fullName, role, status, createdAt, updatedAt, syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:951:          other.syncStatus == this.syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:962:  final Value<SyncStatus> syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:972:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:983:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:994:    Expression<int>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1005:      if (syncStatus != null) 'sync_status': syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1018:      Value<SyncStatus>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1028:      syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1057:    if (syncStatus.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:1058:      map['sync_status'] = Variable<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:1059:          $ProfilesTable.$convertersyncStatus.toSql(syncStatus.value));
inventario-Frontend/lib/core/database/app_database.g.dart:1077:          ..write('syncStatus: $syncStatus, ')
inventario-Frontend/lib/core/database/app_database.g.dart:1138:  late final GeneratedColumnWithTypeConverter<SyncStatus, int> syncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:1139:      GeneratedColumn<int>('sync_status', aliasedName, false,
inventario-Frontend/lib/core/database/app_database.g.dart:1142:              defaultValue: Constant(SyncStatus.synced.index))
inventario-Frontend/lib/core/database/app_database.g.dart:1143:          .withConverter<SyncStatus>($CategoriesTable.$convertersyncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:1153:        syncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:1223:      syncStatus: $CategoriesTable.$convertersyncStatus.fromSql(attachedDatabase
inventario-Frontend/lib/core/database/app_database.g.dart:1225:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:1234:  static JsonTypeConverter2<SyncStatus, int, int> $convertersyncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:1235:      const EnumIndexConverter<SyncStatus>(SyncStatus.values);
inventario-Frontend/lib/core/database/app_database.g.dart:1246:  final SyncStatus syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:1255:      required this.syncStatus});
inventario-Frontend/lib/core/database/app_database.g.dart:1273:      map['sync_status'] = Variable<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:1274:          $CategoriesTable.$convertersyncStatus.toSql(syncStatus));
inventario-Frontend/lib/core/database/app_database.g.dart:1294:      syncStatus: Value(syncStatus),
inventario-Frontend/lib/core/database/app_database.g.dart:1309:      syncStatus: $CategoriesTable.$convertersyncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:1310:          .fromJson(serializer.fromJson<int>(json['syncStatus'])),
inventario-Frontend/lib/core/database/app_database.g.dart:1324:      'syncStatus': serializer.toJson<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:1325:          $CategoriesTable.$convertersyncStatus.toJson(syncStatus)),
inventario-Frontend/lib/core/database/app_database.g.dart:1337:          SyncStatus? syncStatus}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:1346:        syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1359:      syncStatus:
inventario-Frontend/lib/core/database/app_database.g.dart:1360:          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1374:          ..write('syncStatus: $syncStatus')
inventario-Frontend/lib/core/database/app_database.g.dart:1381:      updatedAt, deletedAt, syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:1393:          other.syncStatus == this.syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:1404:  final Value<SyncStatus> syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:1414:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:1425:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:1437:    Expression<int>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1448:      if (syncStatus != null) 'sync_status': syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1461:      Value<SyncStatus>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1471:      syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1500:    if (syncStatus.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:1501:      map['sync_status'] = Variable<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:1502:          $CategoriesTable.$convertersyncStatus.toSql(syncStatus.value));
inventario-Frontend/lib/core/database/app_database.g.dart:1520:          ..write('syncStatus: $syncStatus, ')
inventario-Frontend/lib/core/database/app_database.g.dart:1592:  late final GeneratedColumnWithTypeConverter<SyncStatus, int> syncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:1593:      GeneratedColumn<int>('sync_status', aliasedName, false,
inventario-Frontend/lib/core/database/app_database.g.dart:1596:              defaultValue: Constant(SyncStatus.synced.index))
inventario-Frontend/lib/core/database/app_database.g.dart:1597:          .withConverter<SyncStatus>($CustomersTable.$convertersyncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:1609:        syncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:1689:      syncStatus: $CustomersTable.$convertersyncStatus.fromSql(attachedDatabase
inventario-Frontend/lib/core/database/app_database.g.dart:1691:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:1700:  static JsonTypeConverter2<SyncStatus, int, int> $convertersyncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:1701:      const EnumIndexConverter<SyncStatus>(SyncStatus.values);
inventario-Frontend/lib/core/database/app_database.g.dart:1714:  final SyncStatus syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:1725:      required this.syncStatus});
inventario-Frontend/lib/core/database/app_database.g.dart:1749:      map['sync_status'] =
inventario-Frontend/lib/core/database/app_database.g.dart:1750:          Variable<int>($CustomersTable.$convertersyncStatus.toSql(syncStatus));
inventario-Frontend/lib/core/database/app_database.g.dart:1774:      syncStatus: Value(syncStatus),
inventario-Frontend/lib/core/database/app_database.g.dart:1791:      syncStatus: $CustomersTable.$convertersyncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:1792:          .fromJson(serializer.fromJson<int>(json['syncStatus'])),
inventario-Frontend/lib/core/database/app_database.g.dart:1808:      'syncStatus': serializer
inventario-Frontend/lib/core/database/app_database.g.dart:1809:          .toJson<int>($CustomersTable.$convertersyncStatus.toJson(syncStatus)),
inventario-Frontend/lib/core/database/app_database.g.dart:1823:          SyncStatus? syncStatus}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:1834:        syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1848:      syncStatus:
inventario-Frontend/lib/core/database/app_database.g.dart:1849:          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1865:          ..write('syncStatus: $syncStatus')
inventario-Frontend/lib/core/database/app_database.g.dart:1872:      address, createdAt, updatedAt, deletedAt, syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:1886:          other.syncStatus == this.syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:1899:  final Value<SyncStatus> syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:1911:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:1924:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:1938:    Expression<int>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1951:      if (syncStatus != null) 'sync_status': syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1966:      Value<SyncStatus>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:1978:      syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:2013:    if (syncStatus.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:2014:      map['sync_status'] = Variable<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:2015:          $CustomersTable.$convertersyncStatus.toSql(syncStatus.value));
inventario-Frontend/lib/core/database/app_database.g.dart:2035:          ..write('syncStatus: $syncStatus, ')
inventario-Frontend/lib/core/database/app_database.g.dart:2160:  late final GeneratedColumnWithTypeConverter<SyncStatus, int> syncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:2161:      GeneratedColumn<int>('sync_status', aliasedName, false,
inventario-Frontend/lib/core/database/app_database.g.dart:2164:              defaultValue: Constant(SyncStatus.synced.index))
inventario-Frontend/lib/core/database/app_database.g.dart:2165:          .withConverter<SyncStatus>($ProductsTable.$convertersyncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:2184:        syncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:2320:      syncStatus: $ProductsTable.$convertersyncStatus.fromSql(attachedDatabase
inventario-Frontend/lib/core/database/app_database.g.dart:2322:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:2331:  static JsonTypeConverter2<SyncStatus, int, int> $convertersyncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:2332:      const EnumIndexConverter<SyncStatus>(SyncStatus.values);
inventario-Frontend/lib/core/database/app_database.g.dart:2352:  final SyncStatus syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:2370:      required this.syncStatus});
inventario-Frontend/lib/core/database/app_database.g.dart:2403:      map['sync_status'] =
inventario-Frontend/lib/core/database/app_database.g.dart:2404:          Variable<int>($ProductsTable.$convertersyncStatus.toSql(syncStatus));
inventario-Frontend/lib/core/database/app_database.g.dart:2439:      syncStatus: Value(syncStatus),
inventario-Frontend/lib/core/database/app_database.g.dart:2463:      syncStatus: $ProductsTable.$convertersyncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:2464:          .fromJson(serializer.fromJson<int>(json['syncStatus'])),
inventario-Frontend/lib/core/database/app_database.g.dart:2487:      'syncStatus': serializer
inventario-Frontend/lib/core/database/app_database.g.dart:2488:          .toJson<int>($ProductsTable.$convertersyncStatus.toJson(syncStatus)),
inventario-Frontend/lib/core/database/app_database.g.dart:2509:          SyncStatus? syncStatus}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:2528:        syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:2559:      syncStatus:
inventario-Frontend/lib/core/database/app_database.g.dart:2560:          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:2583:          ..write('syncStatus: $syncStatus')
inventario-Frontend/lib/core/database/app_database.g.dart:2606:      syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:2627:          other.syncStatus == this.syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:2647:  final Value<SyncStatus> syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:2666:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:2686:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:2708:    Expression<int>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:2728:      if (syncStatus != null) 'sync_status': syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:2750:      Value<SyncStatus>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:2769:      syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:2825:    if (syncStatus.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:2826:      map['sync_status'] = Variable<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:2827:          $ProductsTable.$convertersyncStatus.toSql(syncStatus.value));
inventario-Frontend/lib/core/database/app_database.g.dart:2854:          ..write('syncStatus: $syncStatus, ')
inventario-Frontend/lib/core/database/app_database.g.dart:2938:  late final GeneratedColumnWithTypeConverter<SyncStatus, int> syncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:2939:      GeneratedColumn<int>('sync_status', aliasedName, false,
inventario-Frontend/lib/core/database/app_database.g.dart:2942:              defaultValue: Constant(SyncStatus.synced.index))
inventario-Frontend/lib/core/database/app_database.g.dart:2943:          .withConverter<SyncStatus>($SalesTable.$convertersyncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:2956:        syncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:3046:      syncStatus: $SalesTable.$convertersyncStatus.fromSql(attachedDatabase
inventario-Frontend/lib/core/database/app_database.g.dart:3048:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:3057:  static JsonTypeConverter2<SyncStatus, int, int> $convertersyncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:3058:      const EnumIndexConverter<SyncStatus>(SyncStatus.values);
inventario-Frontend/lib/core/database/app_database.g.dart:3072:  final SyncStatus syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:3084:      required this.syncStatus});
inventario-Frontend/lib/core/database/app_database.g.dart:3109:      map['sync_status'] =
inventario-Frontend/lib/core/database/app_database.g.dart:3110:          Variable<int>($SalesTable.$convertersyncStatus.toSql(syncStatus));
inventario-Frontend/lib/core/database/app_database.g.dart:3136:      syncStatus: Value(syncStatus),
inventario-Frontend/lib/core/database/app_database.g.dart:3154:      syncStatus: $SalesTable.$convertersyncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:3155:          .fromJson(serializer.fromJson<int>(json['syncStatus'])),
inventario-Frontend/lib/core/database/app_database.g.dart:3172:      'syncStatus': serializer
inventario-Frontend/lib/core/database/app_database.g.dart:3173:          .toJson<int>($SalesTable.$convertersyncStatus.toJson(syncStatus)),
inventario-Frontend/lib/core/database/app_database.g.dart:3188:          SyncStatus? syncStatus}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:3201:        syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:3219:      syncStatus:
inventario-Frontend/lib/core/database/app_database.g.dart:3220:          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:3237:          ..write('syncStatus: $syncStatus')
inventario-Frontend/lib/core/database/app_database.g.dart:3244:      paymentMethod, status, createdAt, updatedAt, deletedAt, syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:3259:          other.syncStatus == this.syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:3273:  final Value<SyncStatus> syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:3286:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:3300:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:3315:    Expression<int>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:3329:      if (syncStatus != null) 'sync_status': syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:3345:      Value<SyncStatus>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:3358:      syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:3396:    if (syncStatus.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:3397:      map['sync_status'] = Variable<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:3398:          $SalesTable.$convertersyncStatus.toSql(syncStatus.value));
inventario-Frontend/lib/core/database/app_database.g.dart:3419:          ..write('syncStatus: $syncStatus, ')
inventario-Frontend/lib/core/database/app_database.g.dart:3481:  late final GeneratedColumnWithTypeConverter<SyncStatus, int> syncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:3482:      GeneratedColumn<int>('sync_status', aliasedName, false,
inventario-Frontend/lib/core/database/app_database.g.dart:3485:              defaultValue: Constant(SyncStatus.synced.index))
inventario-Frontend/lib/core/database/app_database.g.dart:3486:          .withConverter<SyncStatus>($SaleItemsTable.$convertersyncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:3496:        syncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:3566:      syncStatus: $SaleItemsTable.$convertersyncStatus.fromSql(attachedDatabase
inventario-Frontend/lib/core/database/app_database.g.dart:3568:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:3577:  static JsonTypeConverter2<SyncStatus, int, int> $convertersyncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:3578:      const EnumIndexConverter<SyncStatus>(SyncStatus.values);
inventario-Frontend/lib/core/database/app_database.g.dart:3589:  final SyncStatus syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:3598:      required this.syncStatus});
inventario-Frontend/lib/core/database/app_database.g.dart:3614:      map['sync_status'] =
inventario-Frontend/lib/core/database/app_database.g.dart:3615:          Variable<int>($SaleItemsTable.$convertersyncStatus.toSql(syncStatus));
inventario-Frontend/lib/core/database/app_database.g.dart:3632:      syncStatus: Value(syncStatus),
inventario-Frontend/lib/core/database/app_database.g.dart:3647:      syncStatus: $SaleItemsTable.$convertersyncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:3648:          .fromJson(serializer.fromJson<int>(json['syncStatus'])),
inventario-Frontend/lib/core/database/app_database.g.dart:3662:      'syncStatus': serializer
inventario-Frontend/lib/core/database/app_database.g.dart:3663:          .toJson<int>($SaleItemsTable.$convertersyncStatus.toJson(syncStatus)),
inventario-Frontend/lib/core/database/app_database.g.dart:3675:          SyncStatus? syncStatus}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:3684:        syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:3695:      syncStatus:
inventario-Frontend/lib/core/database/app_database.g.dart:3696:          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:3710:          ..write('syncStatus: $syncStatus')
inventario-Frontend/lib/core/database/app_database.g.dart:3717:      subtotal, createdAt, syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:3729:          other.syncStatus == this.syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:3740:  final Value<SyncStatus> syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:3750:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:3761:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:3775:    Expression<int>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:3786:      if (syncStatus != null) 'sync_status': syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:3799:      Value<SyncStatus>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:3809:      syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:3838:    if (syncStatus.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:3839:      map['sync_status'] = Variable<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:3840:          $SaleItemsTable.$convertersyncStatus.toSql(syncStatus.value));
inventario-Frontend/lib/core/database/app_database.g.dart:3858:          ..write('syncStatus: $syncStatus, ')
inventario-Frontend/lib/core/database/app_database.g.dart:3954:  late final GeneratedColumnWithTypeConverter<SyncStatus, int> syncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:3955:      GeneratedColumn<int>('sync_status', aliasedName, false,
inventario-Frontend/lib/core/database/app_database.g.dart:3958:              defaultValue: Constant(SyncStatus.synced.index))
inventario-Frontend/lib/core/database/app_database.g.dart:3959:          .withConverter<SyncStatus>($PurchasesTable.$convertersyncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:3974:        syncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:4080:      syncStatus: $PurchasesTable.$convertersyncStatus.fromSql(attachedDatabase
inventario-Frontend/lib/core/database/app_database.g.dart:4082:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:4091:  static JsonTypeConverter2<SyncStatus, int, int> $convertersyncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:4092:      const EnumIndexConverter<SyncStatus>(SyncStatus.values);
inventario-Frontend/lib/core/database/app_database.g.dart:4108:  final SyncStatus syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:4122:      required this.syncStatus});
inventario-Frontend/lib/core/database/app_database.g.dart:4151:      map['sync_status'] =
inventario-Frontend/lib/core/database/app_database.g.dart:4152:          Variable<int>($PurchasesTable.$convertersyncStatus.toSql(syncStatus));
inventario-Frontend/lib/core/database/app_database.g.dart:4182:      syncStatus: Value(syncStatus),
inventario-Frontend/lib/core/database/app_database.g.dart:4202:      syncStatus: $PurchasesTable.$convertersyncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:4203:          .fromJson(serializer.fromJson<int>(json['syncStatus'])),
inventario-Frontend/lib/core/database/app_database.g.dart:4222:      'syncStatus': serializer
inventario-Frontend/lib/core/database/app_database.g.dart:4223:          .toJson<int>($PurchasesTable.$convertersyncStatus.toJson(syncStatus)),
inventario-Frontend/lib/core/database/app_database.g.dart:4240:          SyncStatus? syncStatus}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:4257:        syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:4281:      syncStatus:
inventario-Frontend/lib/core/database/app_database.g.dart:4282:          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:4301:          ..write('syncStatus: $syncStatus')
inventario-Frontend/lib/core/database/app_database.g.dart:4320:      syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:4337:          other.syncStatus == this.syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:4353:  final Value<SyncStatus> syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:4368:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:4384:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:4401:    Expression<int>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:4417:      if (syncStatus != null) 'sync_status': syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:4435:      Value<SyncStatus>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:4450:      syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:4494:    if (syncStatus.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:4495:      map['sync_status'] = Variable<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:4496:          $PurchasesTable.$convertersyncStatus.toSql(syncStatus.value));
inventario-Frontend/lib/core/database/app_database.g.dart:4519:          ..write('syncStatus: $syncStatus, ')
inventario-Frontend/lib/core/database/app_database.g.dart:4582:  late final GeneratedColumnWithTypeConverter<SyncStatus, int> syncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:4583:      GeneratedColumn<int>('sync_status', aliasedName, false,
inventario-Frontend/lib/core/database/app_database.g.dart:4586:              defaultValue: Constant(SyncStatus.synced.index))
inventario-Frontend/lib/core/database/app_database.g.dart:4587:          .withConverter<SyncStatus>($PurchaseItemsTable.$convertersyncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:4597:        syncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:4669:      syncStatus: $PurchaseItemsTable.$convertersyncStatus.fromSql(
inventario-Frontend/lib/core/database/app_database.g.dart:4671:              .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
inventario-Frontend/lib/core/database/app_database.g.dart:4680:  static JsonTypeConverter2<SyncStatus, int, int> $convertersyncStatus =
inventario-Frontend/lib/core/database/app_database.g.dart:4681:      const EnumIndexConverter<SyncStatus>(SyncStatus.values);
inventario-Frontend/lib/core/database/app_database.g.dart:4692:  final SyncStatus syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:4701:      required this.syncStatus});
inventario-Frontend/lib/core/database/app_database.g.dart:4717:      map['sync_status'] = Variable<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:4718:          $PurchaseItemsTable.$convertersyncStatus.toSql(syncStatus));
inventario-Frontend/lib/core/database/app_database.g.dart:4736:      syncStatus: Value(syncStatus),
inventario-Frontend/lib/core/database/app_database.g.dart:4751:      syncStatus: $PurchaseItemsTable.$convertersyncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:4752:          .fromJson(serializer.fromJson<int>(json['syncStatus'])),
inventario-Frontend/lib/core/database/app_database.g.dart:4766:      'syncStatus': serializer.toJson<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:4767:          $PurchaseItemsTable.$convertersyncStatus.toJson(syncStatus)),
inventario-Frontend/lib/core/database/app_database.g.dart:4779:          SyncStatus? syncStatus}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:4788:        syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:4800:      syncStatus:
inventario-Frontend/lib/core/database/app_database.g.dart:4801:          data.syncStatus.present ? data.syncStatus.value : this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:4815:          ..write('syncStatus: $syncStatus')
inventario-Frontend/lib/core/database/app_database.g.dart:4822:      subtotal, createdAt, syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:4834:          other.syncStatus == this.syncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:4845:  final Value<SyncStatus> syncStatus;
inventario-Frontend/lib/core/database/app_database.g.dart:4855:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:4866:    this.syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:4880:    Expression<int>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:4891:      if (syncStatus != null) 'sync_status': syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:4904:      Value<SyncStatus>? syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:4914:      syncStatus: syncStatus ?? this.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:4943:    if (syncStatus.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:4944:      map['sync_status'] = Variable<int>(
inventario-Frontend/lib/core/database/app_database.g.dart:4945:          $PurchaseItemsTable.$convertersyncStatus.toSql(syncStatus.value));
inventario-Frontend/lib/core/database/app_database.g.dart:4963:          ..write('syncStatus: $syncStatus, ')
inventario-Frontend/lib/core/database/app_database.g.dart:5019:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:5035:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:5180:  ColumnWithTypeConverterFilters<SyncStatus, SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:5182:          column: $table.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:5359:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5360:      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));
inventario-Frontend/lib/core/database/app_database.g.dart:5408:  GeneratedColumnWithTypeConverter<SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:5410:          column: $table.syncStatus, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5580:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:5596:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:5612:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:5628:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:5655:              getPrefetchedDataCallback: (items) async {
inventario-Frontend/lib/core/database/app_database.g.dart:5767:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:5778:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:5857:  ColumnWithTypeConverterFilters<SyncStatus, SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:5859:          column: $table.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:5952:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5953:      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));
inventario-Frontend/lib/core/database/app_database.g.dart:6003:  GeneratedColumnWithTypeConverter<SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:6005:          column: $table.syncStatus, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6101:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:6112:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:6123:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:6134:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:6175:              getPrefetchedDataCallback: (items) async {
inventario-Frontend/lib/core/database/app_database.g.dart:6229:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:6240:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:6306:  ColumnWithTypeConverterFilters<SyncStatus, SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:6308:          column: $table.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:6380:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6381:      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));
inventario-Frontend/lib/core/database/app_database.g.dart:6431:  GeneratedColumnWithTypeConverter<SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:6433:          column: $table.syncStatus, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6507:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:6518:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:6529:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:6540:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:6579:              getPrefetchedDataCallback: (items) async {
inventario-Frontend/lib/core/database/app_database.g.dart:6623:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:6636:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:6708:  ColumnWithTypeConverterFilters<SyncStatus, SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:6710:          column: $table.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:6788:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6789:      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));
inventario-Frontend/lib/core/database/app_database.g.dart:6845:  GeneratedColumnWithTypeConverter<SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:6847:          column: $table.syncStatus, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6923:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:6936:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:6949:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:6962:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:7001:              getPrefetchedDataCallback: (items) async {
inventario-Frontend/lib/core/database/app_database.g.dart:7050:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:7070:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:7191:  ColumnWithTypeConverterFilters<SyncStatus, SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:7193:          column: $table.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:7334:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7335:      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));
inventario-Frontend/lib/core/database/app_database.g.dart:7429:  GeneratedColumnWithTypeConverter<SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:7431:          column: $table.syncStatus, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:7559:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:7579:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:7599:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:7619:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:7673:              getPrefetchedDataCallback: (items) async {
inventario-Frontend/lib/core/database/app_database.g.dart:7735:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:7749:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:7843:  ColumnWithTypeConverterFilters<SyncStatus, SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:7845:          column: $table.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:7961:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7962:      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));
inventario-Frontend/lib/core/database/app_database.g.dart:8055:  GeneratedColumnWithTypeConverter<SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:8057:          column: $table.syncStatus, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8175:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:8189:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:8203:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:8217:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:8277:              getPrefetchedDataCallback: (items) async {
inventario-Frontend/lib/core/database/app_database.g.dart:8318:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:8329:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:8391:  ColumnWithTypeConverterFilters<SyncStatus, SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:8393:          column: $table.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:8461:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8462:      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));
inventario-Frontend/lib/core/database/app_database.g.dart:8529:  GeneratedColumnWithTypeConverter<SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:8531:          column: $table.syncStatus, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8604:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:8615:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:8626:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:8637:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:8686:              getPrefetchedDataCallback: (items) async {
inventario-Frontend/lib/core/database/app_database.g.dart:8719:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:8735:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:8829:  ColumnWithTypeConverterFilters<SyncStatus, SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:8831:          column: $table.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:8938:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8939:      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));
inventario-Frontend/lib/core/database/app_database.g.dart:9021:  GeneratedColumnWithTypeConverter<SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:9023:          column: $table.syncStatus, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:9123:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:9139:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:9155:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:9171:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:9223:              getPrefetchedDataCallback: (items) async {
inventario-Frontend/lib/core/database/app_database.g.dart:9267:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:9279:  Value<SyncStatus> syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:9343:  ColumnWithTypeConverterFilters<SyncStatus, SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:9345:          column: $table.syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:9413:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9414:      column: $table.syncStatus, builder: (column) => ColumnOrderings(column));
inventario-Frontend/lib/core/database/app_database.g.dart:9481:  GeneratedColumnWithTypeConverter<SyncStatus, int> get syncStatus =>
inventario-Frontend/lib/core/database/app_database.g.dart:9483:          column: $table.syncStatus, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:9556:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:9567:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:9578:            Value<SyncStatus> syncStatus = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:9589:            syncStatus: syncStatus,
inventario-Frontend/lib/core/database/app_database.g.dart:9638:              getPrefetchedDataCallback: (items) async {
inventario-Frontend/lib/features/auth/data/datasources/business_dao.dart:19:  Future<void> saveBusinessLocal(Business business) async {
inventario-Frontend/lib/features/auth/data/datasources/business_dao.dart:24:  Future<void> softDeleteBusiness(String id) async {
inventario-Frontend/lib/features/auth/data/datasources/business_dao.dart:28:        syncStatus: const Value(SyncStatus.pendingDelete),
inventario-Frontend/lib/features/auth/data/datasources/business_dao.dart:34:  // Sync Engine: Obtener negocios pendientes de sincronizar
inventario-Frontend/lib/features/auth/data/datasources/business_dao.dart:35:  Future<List<Business>> getPendingSyncBusinesses() {
inventario-Frontend/lib/features/auth/data/datasources/business_dao.dart:36:    return (select(businesses)..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not())).get();
inventario-Frontend/lib/features/auth/data/datasources/profile_dao.dart:24:  Future<void> saveProfileLocal(Profile profile) async {
inventario-Frontend/lib/features/auth/data/datasources/profile_dao.dart:28:  // Sync Engine: Obtener cambios de perfiles locales
inventario-Frontend/lib/features/auth/data/datasources/profile_dao.dart:29:  Future<List<Profile>> getPendingSyncProfiles() {
inventario-Frontend/lib/features/auth/data/datasources/profile_dao.dart:30:    return (select(profiles)..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not())).get();
inventario-Frontend/lib/features/customers/data/datasources/customer_dao.dart:16:  Future<void> insertOrUpdateCustomer(Customer customer) async {
inventario-Frontend/lib/features/customers/data/datasources/customer_dao.dart:21:  Future<void> softDeleteCustomer(String id) async {
inventario-Frontend/lib/features/customers/data/datasources/customer_dao.dart:25:        syncStatus: const Value(SyncStatus.pendingDelete),
inventario-Frontend/lib/features/customers/data/datasources/customer_dao.dart:32:  Future<List<Customer>> getPendingSyncCustomers(String businessId) {
inventario-Frontend/lib/features/customers/data/datasources/customer_dao.dart:35:          ..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not()))
inventario-Frontend/lib/features/inventory/data/datasources/category_dao.dart:16:  Future<void> saveCategoryLocal(Category category) async {
inventario-Frontend/lib/features/inventory/data/datasources/category_dao.dart:20:  Future<void> softDeleteCategory(String id) async {
inventario-Frontend/lib/features/inventory/data/datasources/category_dao.dart:24:        syncStatus: const Value(SyncStatus.pendingDelete),
inventario-Frontend/lib/features/inventory/data/datasources/category_dao.dart:30:  // Sync Engine
inventario-Frontend/lib/features/inventory/data/datasources/category_dao.dart:31:  Future<List<Category>> getPendingSyncCategories(String businessId) {
inventario-Frontend/lib/features/inventory/data/datasources/category_dao.dart:34:          ..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not()))
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:19:  Future<List<Product>> searchProducts(String businessId, String query) async {
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:27:  // Insertar o actualizar localmente (Inyecciones Offline)
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:28:  Future<void> saveProductLocal(Product companion) async {
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:33:  Future<void> softDeleteProduct(String id) async {
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:37:        syncStatus: const Value(SyncStatus.pendingDelete),
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:43:  // --- Operaciones para el Sync Engine (Fase 4) ---
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:46:  Future<List<Product>> getPendingSyncProducts(String businessId) {
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:49:          ..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not()))
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:25:  }) async {
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:26:    await transaction(() async {
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:43:            syncStatus: const Value(SyncStatus.pendingUpdate),
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:51:  // Sync Engine: Obtener compras pendientes de sincronizar
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:52:  Future<List<Purchase>> getPendingSyncPurchases(String businessId) {
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:55:          ..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not()))
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:59:  // Sync Engine: Obtener ítems asociados a esas compras pendientes
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:60:  Future<List<PurchaseItem>> getPendingSyncPurchaseItems(List<String> pendingPurchaseIds) {
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:25:  }) async {
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:26:    await transaction(() async {
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:41:            syncStatus: const Value(SyncStatus.pendingUpdate), 
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:49:  // Sync Engine: Obtener ventas pendientes de subir a la nube
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:50:  Future<List<Sale>> getPendingSyncSales(String businessId) {
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:53:          ..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not()))
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:57:  // Sync Engine: Obtener ítems de venta pendientes vinculados a esas ventas
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:58:  Future<List<SaleItem>> getPendingSyncSaleItems(List<String> pendingSaleIds) {
inventario-Frontend/pubspec.yaml:45:  # Base de datos local (Offline-First)

### POS / ventas / productos / inventario
inventario-Frontend/lib/app/router/app_router.dart:62:        path: AppRoutes.inventarioPath,
inventario-Frontend/lib/app/router/app_router.dart:63:        name: AppRoutes.inventarioName,
inventario-Frontend/lib/app/router/app_router.dart:64:        builder: (context, state) => const TemporaryInventarioView(),
inventario-Frontend/lib/app/router/app_router.dart:132:              onPressed: () => context.goNamed(AppRoutes.inventarioName),
inventario-Frontend/lib/app/router/app_router.dart:133:              child: const Text('Ir a Gestión de Inventario'),
inventario-Frontend/lib/app/router/app_router.dart:142:class TemporaryInventarioView extends StatelessWidget {
inventario-Frontend/lib/app/router/app_router.dart:143:  const TemporaryInventarioView({super.key});
inventario-Frontend/lib/app/router/app_router.dart:147:      appBar: AppBar(title: const Text('Módulo de Inventario')),
inventario-Frontend/lib/app/router/app_router.dart:148:      body: const Center(child: Text('📦 Aquí se listarán tus productos (Fase 3)')),
inventario-Frontend/lib/app/router/routes_constants.dart:15:  static const String inventarioPath = '/inventario';
inventario-Frontend/lib/app/router/routes_constants.dart:16:  static const String inventarioName = 'inventario';
inventario-Frontend/lib/core/database/app_database.dart:9:part '../../features/inventory/data/datasources/product_dao.dart';
inventario-Frontend/lib/core/database/app_database.dart:10:part '../../features/inventory/data/datasources/category_dao.dart';
inventario-Frontend/lib/core/database/app_database.dart:11:part '../../features/inventory/data/datasources/purchase_dao.dart';
inventario-Frontend/lib/core/database/app_database.dart:12:part '../../features/sales/data/datasources/sale_dao.dart';
inventario-Frontend/lib/core/database/app_database.dart:101:@DataClassName('Product')
inventario-Frontend/lib/core/database/app_database.dart:102:class Products extends Table {
inventario-Frontend/lib/core/database/app_database.dart:106:  TextColumn get barcode => text().nullable()();
inventario-Frontend/lib/core/database/app_database.dart:110:  RealColumn get salePrice => real()();
inventario-Frontend/lib/core/database/app_database.dart:126:@DataClassName('Sale')
inventario-Frontend/lib/core/database/app_database.dart:127:class Sales extends Table {
inventario-Frontend/lib/core/database/app_database.dart:145:@DataClassName('SaleItem')
inventario-Frontend/lib/core/database/app_database.dart:146:class SaleItems extends Table {
inventario-Frontend/lib/core/database/app_database.dart:148:  TextColumn get saleId => text().nullable().references(Sales, #id)();
inventario-Frontend/lib/core/database/app_database.dart:149:  TextColumn get productId => text().nullable().references(Products, #id)();
inventario-Frontend/lib/core/database/app_database.dart:186:  TextColumn get productId => text().nullable().references(Products, #id)();
inventario-Frontend/lib/core/database/app_database.dart:208:    Products,
inventario-Frontend/lib/core/database/app_database.dart:209:    Sales,
inventario-Frontend/lib/core/database/app_database.dart:210:    SaleItems,
inventario-Frontend/lib/core/database/app_database.dart:219:    ProductDao,
inventario-Frontend/lib/core/database/app_database.dart:220:    SaleDao,
inventario-Frontend/lib/core/database/app_database.g.dart:2042:class $ProductsTable extends Products with TableInfo<$ProductsTable, Product> {
inventario-Frontend/lib/core/database/app_database.g.dart:2046:  $ProductsTable(this.attachedDatabase, [this._alias]);
inventario-Frontend/lib/core/database/app_database.g.dart:2070:  static const VerificationMeta _barcodeMeta =
inventario-Frontend/lib/core/database/app_database.g.dart:2071:      const VerificationMeta('barcode');
inventario-Frontend/lib/core/database/app_database.g.dart:2073:  late final GeneratedColumn<String> barcode = GeneratedColumn<String>(
inventario-Frontend/lib/core/database/app_database.g.dart:2074:      'barcode', aliasedName, true,
inventario-Frontend/lib/core/database/app_database.g.dart:2095:  static const VerificationMeta _salePriceMeta =
inventario-Frontend/lib/core/database/app_database.g.dart:2096:      const VerificationMeta('salePrice');
inventario-Frontend/lib/core/database/app_database.g.dart:2098:  late final GeneratedColumn<double> salePrice = GeneratedColumn<double>(
inventario-Frontend/lib/core/database/app_database.g.dart:2099:      'sale_price', aliasedName, false,
inventario-Frontend/lib/core/database/app_database.g.dart:2165:          .withConverter<SyncStatus>($ProductsTable.$convertersyncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:2171:        barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:2175:        salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:2190:  static const String $name = 'products';
inventario-Frontend/lib/core/database/app_database.g.dart:2192:  VerificationContext validateIntegrity(Insertable<Product> instance,
inventario-Frontend/lib/core/database/app_database.g.dart:2213:    if (data.containsKey('barcode')) {
inventario-Frontend/lib/core/database/app_database.g.dart:2214:      context.handle(_barcodeMeta,
inventario-Frontend/lib/core/database/app_database.g.dart:2215:          barcode.isAcceptableOrUnknown(data['barcode']!, _barcodeMeta));
inventario-Frontend/lib/core/database/app_database.g.dart:2235:    if (data.containsKey('sale_price')) {
inventario-Frontend/lib/core/database/app_database.g.dart:2236:      context.handle(_salePriceMeta,
inventario-Frontend/lib/core/database/app_database.g.dart:2237:          salePrice.isAcceptableOrUnknown(data['sale_price']!, _salePriceMeta));
inventario-Frontend/lib/core/database/app_database.g.dart:2239:      context.missing(_salePriceMeta);
inventario-Frontend/lib/core/database/app_database.g.dart:2285:  Product map(Map<String, dynamic> data, {String? tablePrefix}) {
inventario-Frontend/lib/core/database/app_database.g.dart:2287:    return Product(
inventario-Frontend/lib/core/database/app_database.g.dart:2294:      barcode: attachedDatabase.typeMapping
inventario-Frontend/lib/core/database/app_database.g.dart:2295:          .read(DriftSqlType.string, data['${effectivePrefix}barcode']),
inventario-Frontend/lib/core/database/app_database.g.dart:2302:      salePrice: attachedDatabase.typeMapping
inventario-Frontend/lib/core/database/app_database.g.dart:2303:          .read(DriftSqlType.double, data['${effectivePrefix}sale_price'])!,
inventario-Frontend/lib/core/database/app_database.g.dart:2320:      syncStatus: $ProductsTable.$convertersyncStatus.fromSql(attachedDatabase
inventario-Frontend/lib/core/database/app_database.g.dart:2327:  $ProductsTable createAlias(String alias) {
inventario-Frontend/lib/core/database/app_database.g.dart:2328:    return $ProductsTable(attachedDatabase, alias);
inventario-Frontend/lib/core/database/app_database.g.dart:2335:class Product extends DataClass implements Insertable<Product> {
inventario-Frontend/lib/core/database/app_database.g.dart:2339:  final String? barcode;
inventario-Frontend/lib/core/database/app_database.g.dart:2343:  final double salePrice;
inventario-Frontend/lib/core/database/app_database.g.dart:2353:  const Product(
inventario-Frontend/lib/core/database/app_database.g.dart:2357:      this.barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:2361:      required this.salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:2381:    if (!nullToAbsent || barcode != null) {
inventario-Frontend/lib/core/database/app_database.g.dart:2382:      map['barcode'] = Variable<String>(barcode);
inventario-Frontend/lib/core/database/app_database.g.dart:2389:    map['sale_price'] = Variable<double>(salePrice);
inventario-Frontend/lib/core/database/app_database.g.dart:2404:          Variable<int>($ProductsTable.$convertersyncStatus.toSql(syncStatus));
inventario-Frontend/lib/core/database/app_database.g.dart:2409:  ProductsCompanion toCompanion(bool nullToAbsent) {
inventario-Frontend/lib/core/database/app_database.g.dart:2410:    return ProductsCompanion(
inventario-Frontend/lib/core/database/app_database.g.dart:2418:      barcode: barcode == null && nullToAbsent
inventario-Frontend/lib/core/database/app_database.g.dart:2420:          : Value(barcode),
inventario-Frontend/lib/core/database/app_database.g.dart:2426:      salePrice: Value(salePrice),
inventario-Frontend/lib/core/database/app_database.g.dart:2443:  factory Product.fromJson(Map<String, dynamic> json,
inventario-Frontend/lib/core/database/app_database.g.dart:2446:    return Product(
inventario-Frontend/lib/core/database/app_database.g.dart:2450:      barcode: serializer.fromJson<String?>(json['barcode']),
inventario-Frontend/lib/core/database/app_database.g.dart:2454:      salePrice: serializer.fromJson<double>(json['salePrice']),
inventario-Frontend/lib/core/database/app_database.g.dart:2463:      syncStatus: $ProductsTable.$convertersyncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:2474:      'barcode': serializer.toJson<String?>(barcode),
inventario-Frontend/lib/core/database/app_database.g.dart:2478:      'salePrice': serializer.toJson<double>(salePrice),
inventario-Frontend/lib/core/database/app_database.g.dart:2488:          .toJson<int>($ProductsTable.$convertersyncStatus.toJson(syncStatus)),
inventario-Frontend/lib/core/database/app_database.g.dart:2492:  Product copyWith(
inventario-Frontend/lib/core/database/app_database.g.dart:2496:          Value<String?> barcode = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:2500:          double? salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:2510:      Product(
inventario-Frontend/lib/core/database/app_database.g.dart:2514:        barcode: barcode.present ? barcode.value : this.barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:2518:        salePrice: salePrice ?? this.salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:2530:  Product copyWithCompanion(ProductsCompanion data) {
inventario-Frontend/lib/core/database/app_database.g.dart:2531:    return Product(
inventario-Frontend/lib/core/database/app_database.g.dart:2537:      barcode: data.barcode.present ? data.barcode.value : this.barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:2544:      salePrice: data.salePrice.present ? data.salePrice.value : this.salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:2566:    return (StringBuffer('Product(')
inventario-Frontend/lib/core/database/app_database.g.dart:2570:          ..write('barcode: $barcode, ')
inventario-Frontend/lib/core/database/app_database.g.dart:2574:          ..write('salePrice: $salePrice, ')
inventario-Frontend/lib/core/database/app_database.g.dart:2593:      barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:2597:      salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:2610:      (other is Product &&
inventario-Frontend/lib/core/database/app_database.g.dart:2614:          other.barcode == this.barcode &&
inventario-Frontend/lib/core/database/app_database.g.dart:2618:          other.salePrice == this.salePrice &&
inventario-Frontend/lib/core/database/app_database.g.dart:2630:class ProductsCompanion extends UpdateCompanion<Product> {
inventario-Frontend/lib/core/database/app_database.g.dart:2634:  final Value<String?> barcode;
inventario-Frontend/lib/core/database/app_database.g.dart:2638:  final Value<double> salePrice;
inventario-Frontend/lib/core/database/app_database.g.dart:2649:  const ProductsCompanion({
inventario-Frontend/lib/core/database/app_database.g.dart:2653:    this.barcode = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:2657:    this.salePrice = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:2669:  ProductsCompanion.insert({
inventario-Frontend/lib/core/database/app_database.g.dart:2673:    this.barcode = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:2677:    required double salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:2690:        salePrice = Value(salePrice);
inventario-Frontend/lib/core/database/app_database.g.dart:2691:  static Insertable<Product> custom({
inventario-Frontend/lib/core/database/app_database.g.dart:2695:    Expression<String>? barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:2699:    Expression<double>? salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:2715:      if (barcode != null) 'barcode': barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:2719:      if (salePrice != null) 'sale_price': salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:2733:  ProductsCompanion copyWith(
inventario-Frontend/lib/core/database/app_database.g.dart:2737:      Value<String?>? barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:2741:      Value<double>? salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:2752:    return ProductsCompanion(
inventario-Frontend/lib/core/database/app_database.g.dart:2756:      barcode: barcode ?? this.barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:2760:      salePrice: salePrice ?? this.salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:2786:    if (barcode.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:2787:      map['barcode'] = Variable<String>(barcode.value);
inventario-Frontend/lib/core/database/app_database.g.dart:2798:    if (salePrice.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:2799:      map['sale_price'] = Variable<double>(salePrice.value);
inventario-Frontend/lib/core/database/app_database.g.dart:2827:          $ProductsTable.$convertersyncStatus.toSql(syncStatus.value));
inventario-Frontend/lib/core/database/app_database.g.dart:2837:    return (StringBuffer('ProductsCompanion(')
inventario-Frontend/lib/core/database/app_database.g.dart:2841:          ..write('barcode: $barcode, ')
inventario-Frontend/lib/core/database/app_database.g.dart:2845:          ..write('salePrice: $salePrice, ')
inventario-Frontend/lib/core/database/app_database.g.dart:2861:class $SalesTable extends Sales with TableInfo<$SalesTable, Sale> {
inventario-Frontend/lib/core/database/app_database.g.dart:2865:  $SalesTable(this.attachedDatabase, [this._alias]);
inventario-Frontend/lib/core/database/app_database.g.dart:2943:          .withConverter<SyncStatus>($SalesTable.$convertersyncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:2962:  static const String $name = 'sales';
inventario-Frontend/lib/core/database/app_database.g.dart:2964:  VerificationContext validateIntegrity(Insertable<Sale> instance,
inventario-Frontend/lib/core/database/app_database.g.dart:3023:  Sale map(Map<String, dynamic> data, {String? tablePrefix}) {
inventario-Frontend/lib/core/database/app_database.g.dart:3025:    return Sale(
inventario-Frontend/lib/core/database/app_database.g.dart:3046:      syncStatus: $SalesTable.$convertersyncStatus.fromSql(attachedDatabase
inventario-Frontend/lib/core/database/app_database.g.dart:3053:  $SalesTable createAlias(String alias) {
inventario-Frontend/lib/core/database/app_database.g.dart:3054:    return $SalesTable(attachedDatabase, alias);
inventario-Frontend/lib/core/database/app_database.g.dart:3061:class Sale extends DataClass implements Insertable<Sale> {
inventario-Frontend/lib/core/database/app_database.g.dart:3073:  const Sale(
inventario-Frontend/lib/core/database/app_database.g.dart:3110:          Variable<int>($SalesTable.$convertersyncStatus.toSql(syncStatus));
inventario-Frontend/lib/core/database/app_database.g.dart:3115:  SalesCompanion toCompanion(bool nullToAbsent) {
inventario-Frontend/lib/core/database/app_database.g.dart:3116:    return SalesCompanion(
inventario-Frontend/lib/core/database/app_database.g.dart:3140:  factory Sale.fromJson(Map<String, dynamic> json,
inventario-Frontend/lib/core/database/app_database.g.dart:3143:    return Sale(
inventario-Frontend/lib/core/database/app_database.g.dart:3154:      syncStatus: $SalesTable.$convertersyncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:3173:          .toJson<int>($SalesTable.$convertersyncStatus.toJson(syncStatus)),
inventario-Frontend/lib/core/database/app_database.g.dart:3177:  Sale copyWith(
inventario-Frontend/lib/core/database/app_database.g.dart:3189:      Sale(
inventario-Frontend/lib/core/database/app_database.g.dart:3203:  Sale copyWithCompanion(SalesCompanion data) {
inventario-Frontend/lib/core/database/app_database.g.dart:3204:    return Sale(
inventario-Frontend/lib/core/database/app_database.g.dart:3226:    return (StringBuffer('Sale(')
inventario-Frontend/lib/core/database/app_database.g.dart:3248:      (other is Sale &&
inventario-Frontend/lib/core/database/app_database.g.dart:3262:class SalesCompanion extends UpdateCompanion<Sale> {
inventario-Frontend/lib/core/database/app_database.g.dart:3275:  const SalesCompanion({
inventario-Frontend/lib/core/database/app_database.g.dart:3289:  SalesCompanion.insert({
inventario-Frontend/lib/core/database/app_database.g.dart:3304:  static Insertable<Sale> custom({
inventario-Frontend/lib/core/database/app_database.g.dart:3334:  SalesCompanion copyWith(
inventario-Frontend/lib/core/database/app_database.g.dart:3347:    return SalesCompanion(
inventario-Frontend/lib/core/database/app_database.g.dart:3398:          $SalesTable.$convertersyncStatus.toSql(syncStatus.value));
inventario-Frontend/lib/core/database/app_database.g.dart:3408:    return (StringBuffer('SalesCompanion(')
inventario-Frontend/lib/core/database/app_database.g.dart:3426:class $SaleItemsTable extends SaleItems
inventario-Frontend/lib/core/database/app_database.g.dart:3427:    with TableInfo<$SaleItemsTable, SaleItem> {
inventario-Frontend/lib/core/database/app_database.g.dart:3431:  $SaleItemsTable(this.attachedDatabase, [this._alias]);
inventario-Frontend/lib/core/database/app_database.g.dart:3437:  static const VerificationMeta _saleIdMeta = const VerificationMeta('saleId');
inventario-Frontend/lib/core/database/app_database.g.dart:3439:  late final GeneratedColumn<String> saleId = GeneratedColumn<String>(
inventario-Frontend/lib/core/database/app_database.g.dart:3440:      'sale_id', aliasedName, true,
inventario-Frontend/lib/core/database/app_database.g.dart:3444:          GeneratedColumn.constraintIsAlways('REFERENCES sales (id)'));
inventario-Frontend/lib/core/database/app_database.g.dart:3445:  static const VerificationMeta _productIdMeta =
inventario-Frontend/lib/core/database/app_database.g.dart:3446:      const VerificationMeta('productId');
inventario-Frontend/lib/core/database/app_database.g.dart:3448:  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
inventario-Frontend/lib/core/database/app_database.g.dart:3449:      'product_id', aliasedName, true,
inventario-Frontend/lib/core/database/app_database.g.dart:3453:          GeneratedColumn.constraintIsAlways('REFERENCES products (id)'));
inventario-Frontend/lib/core/database/app_database.g.dart:3486:          .withConverter<SyncStatus>($SaleItemsTable.$convertersyncStatus);
inventario-Frontend/lib/core/database/app_database.g.dart:3490:        saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:3491:        productId,
inventario-Frontend/lib/core/database/app_database.g.dart:3502:  static const String $name = 'sale_items';
inventario-Frontend/lib/core/database/app_database.g.dart:3504:  VerificationContext validateIntegrity(Insertable<SaleItem> instance,
inventario-Frontend/lib/core/database/app_database.g.dart:3513:    if (data.containsKey('sale_id')) {
inventario-Frontend/lib/core/database/app_database.g.dart:3514:      context.handle(_saleIdMeta,
inventario-Frontend/lib/core/database/app_database.g.dart:3515:          saleId.isAcceptableOrUnknown(data['sale_id']!, _saleIdMeta));
inventario-Frontend/lib/core/database/app_database.g.dart:3517:    if (data.containsKey('product_id')) {
inventario-Frontend/lib/core/database/app_database.g.dart:3518:      context.handle(_productIdMeta,
inventario-Frontend/lib/core/database/app_database.g.dart:3519:          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
inventario-Frontend/lib/core/database/app_database.g.dart:3549:  SaleItem map(Map<String, dynamic> data, {String? tablePrefix}) {
inventario-Frontend/lib/core/database/app_database.g.dart:3551:    return SaleItem(
inventario-Frontend/lib/core/database/app_database.g.dart:3554:      saleId: attachedDatabase.typeMapping
inventario-Frontend/lib/core/database/app_database.g.dart:3555:          .read(DriftSqlType.string, data['${effectivePrefix}sale_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:3556:      productId: attachedDatabase.typeMapping
inventario-Frontend/lib/core/database/app_database.g.dart:3557:          .read(DriftSqlType.string, data['${effectivePrefix}product_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:3566:      syncStatus: $SaleItemsTable.$convertersyncStatus.fromSql(attachedDatabase
inventario-Frontend/lib/core/database/app_database.g.dart:3573:  $SaleItemsTable createAlias(String alias) {
inventario-Frontend/lib/core/database/app_database.g.dart:3574:    return $SaleItemsTable(attachedDatabase, alias);
inventario-Frontend/lib/core/database/app_database.g.dart:3581:class SaleItem extends DataClass implements Insertable<SaleItem> {
inventario-Frontend/lib/core/database/app_database.g.dart:3583:  final String? saleId;
inventario-Frontend/lib/core/database/app_database.g.dart:3584:  final String? productId;
inventario-Frontend/lib/core/database/app_database.g.dart:3590:  const SaleItem(
inventario-Frontend/lib/core/database/app_database.g.dart:3592:      this.saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:3593:      this.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:3603:    if (!nullToAbsent || saleId != null) {
inventario-Frontend/lib/core/database/app_database.g.dart:3604:      map['sale_id'] = Variable<String>(saleId);
inventario-Frontend/lib/core/database/app_database.g.dart:3606:    if (!nullToAbsent || productId != null) {
inventario-Frontend/lib/core/database/app_database.g.dart:3607:      map['product_id'] = Variable<String>(productId);
inventario-Frontend/lib/core/database/app_database.g.dart:3615:          Variable<int>($SaleItemsTable.$convertersyncStatus.toSql(syncStatus));
inventario-Frontend/lib/core/database/app_database.g.dart:3620:  SaleItemsCompanion toCompanion(bool nullToAbsent) {
inventario-Frontend/lib/core/database/app_database.g.dart:3621:    return SaleItemsCompanion(
inventario-Frontend/lib/core/database/app_database.g.dart:3623:      saleId:
inventario-Frontend/lib/core/database/app_database.g.dart:3624:          saleId == null && nullToAbsent ? const Value.absent() : Value(saleId),
inventario-Frontend/lib/core/database/app_database.g.dart:3625:      productId: productId == null && nullToAbsent
inventario-Frontend/lib/core/database/app_database.g.dart:3627:          : Value(productId),
inventario-Frontend/lib/core/database/app_database.g.dart:3636:  factory SaleItem.fromJson(Map<String, dynamic> json,
inventario-Frontend/lib/core/database/app_database.g.dart:3639:    return SaleItem(
inventario-Frontend/lib/core/database/app_database.g.dart:3641:      saleId: serializer.fromJson<String?>(json['saleId']),
inventario-Frontend/lib/core/database/app_database.g.dart:3642:      productId: serializer.fromJson<String?>(json['productId']),
inventario-Frontend/lib/core/database/app_database.g.dart:3647:      syncStatus: $SaleItemsTable.$convertersyncStatus
inventario-Frontend/lib/core/database/app_database.g.dart:3656:      'saleId': serializer.toJson<String?>(saleId),
inventario-Frontend/lib/core/database/app_database.g.dart:3657:      'productId': serializer.toJson<String?>(productId),
inventario-Frontend/lib/core/database/app_database.g.dart:3663:          .toJson<int>($SaleItemsTable.$convertersyncStatus.toJson(syncStatus)),
inventario-Frontend/lib/core/database/app_database.g.dart:3667:  SaleItem copyWith(
inventario-Frontend/lib/core/database/app_database.g.dart:3669:          Value<String?> saleId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:3670:          Value<String?> productId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:3676:      SaleItem(
inventario-Frontend/lib/core/database/app_database.g.dart:3678:        saleId: saleId.present ? saleId.value : this.saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:3679:        productId: productId.present ? productId.value : this.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:3686:  SaleItem copyWithCompanion(SaleItemsCompanion data) {
inventario-Frontend/lib/core/database/app_database.g.dart:3687:    return SaleItem(
inventario-Frontend/lib/core/database/app_database.g.dart:3689:      saleId: data.saleId.present ? data.saleId.value : this.saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:3690:      productId: data.productId.present ? data.productId.value : this.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:3702:    return (StringBuffer('SaleItem(')
inventario-Frontend/lib/core/database/app_database.g.dart:3704:          ..write('saleId: $saleId, ')
inventario-Frontend/lib/core/database/app_database.g.dart:3705:          ..write('productId: $productId, ')
inventario-Frontend/lib/core/database/app_database.g.dart:3716:  int get hashCode => Object.hash(id, saleId, productId, quantity, unitPrice,
inventario-Frontend/lib/core/database/app_database.g.dart:3721:      (other is SaleItem &&
inventario-Frontend/lib/core/database/app_database.g.dart:3723:          other.saleId == this.saleId &&
inventario-Frontend/lib/core/database/app_database.g.dart:3724:          other.productId == this.productId &&
inventario-Frontend/lib/core/database/app_database.g.dart:3732:class SaleItemsCompanion extends UpdateCompanion<SaleItem> {
inventario-Frontend/lib/core/database/app_database.g.dart:3734:  final Value<String?> saleId;
inventario-Frontend/lib/core/database/app_database.g.dart:3735:  final Value<String?> productId;
inventario-Frontend/lib/core/database/app_database.g.dart:3742:  const SaleItemsCompanion({
inventario-Frontend/lib/core/database/app_database.g.dart:3744:    this.saleId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:3745:    this.productId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:3753:  SaleItemsCompanion.insert({
inventario-Frontend/lib/core/database/app_database.g.dart:3755:    this.saleId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:3756:    this.productId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:3767:  static Insertable<SaleItem> custom({
inventario-Frontend/lib/core/database/app_database.g.dart:3769:    Expression<String>? saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:3770:    Expression<String>? productId,
inventario-Frontend/lib/core/database/app_database.g.dart:3780:      if (saleId != null) 'sale_id': saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:3781:      if (productId != null) 'product_id': productId,
inventario-Frontend/lib/core/database/app_database.g.dart:3791:  SaleItemsCompanion copyWith(
inventario-Frontend/lib/core/database/app_database.g.dart:3793:      Value<String?>? saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:3794:      Value<String?>? productId,
inventario-Frontend/lib/core/database/app_database.g.dart:3801:    return SaleItemsCompanion(
inventario-Frontend/lib/core/database/app_database.g.dart:3803:      saleId: saleId ?? this.saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:3804:      productId: productId ?? this.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:3820:    if (saleId.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:3821:      map['sale_id'] = Variable<String>(saleId.value);
inventario-Frontend/lib/core/database/app_database.g.dart:3823:    if (productId.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:3824:      map['product_id'] = Variable<String>(productId.value);
inventario-Frontend/lib/core/database/app_database.g.dart:3840:          $SaleItemsTable.$convertersyncStatus.toSql(syncStatus.value));
inventario-Frontend/lib/core/database/app_database.g.dart:3850:    return (StringBuffer('SaleItemsCompanion(')
inventario-Frontend/lib/core/database/app_database.g.dart:3852:          ..write('saleId: $saleId, ')
inventario-Frontend/lib/core/database/app_database.g.dart:3853:          ..write('productId: $productId, ')
inventario-Frontend/lib/core/database/app_database.g.dart:4546:  static const VerificationMeta _productIdMeta =
inventario-Frontend/lib/core/database/app_database.g.dart:4547:      const VerificationMeta('productId');
inventario-Frontend/lib/core/database/app_database.g.dart:4549:  late final GeneratedColumn<String> productId = GeneratedColumn<String>(
inventario-Frontend/lib/core/database/app_database.g.dart:4550:      'product_id', aliasedName, true,
inventario-Frontend/lib/core/database/app_database.g.dart:4554:          GeneratedColumn.constraintIsAlways('REFERENCES products (id)'));
inventario-Frontend/lib/core/database/app_database.g.dart:4592:        productId,
inventario-Frontend/lib/core/database/app_database.g.dart:4620:    if (data.containsKey('product_id')) {
inventario-Frontend/lib/core/database/app_database.g.dart:4621:      context.handle(_productIdMeta,
inventario-Frontend/lib/core/database/app_database.g.dart:4622:          productId.isAcceptableOrUnknown(data['product_id']!, _productIdMeta));
inventario-Frontend/lib/core/database/app_database.g.dart:4659:      productId: attachedDatabase.typeMapping
inventario-Frontend/lib/core/database/app_database.g.dart:4660:          .read(DriftSqlType.string, data['${effectivePrefix}product_id']),
inventario-Frontend/lib/core/database/app_database.g.dart:4687:  final String? productId;
inventario-Frontend/lib/core/database/app_database.g.dart:4696:      this.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:4709:    if (!nullToAbsent || productId != null) {
inventario-Frontend/lib/core/database/app_database.g.dart:4710:      map['product_id'] = Variable<String>(productId);
inventario-Frontend/lib/core/database/app_database.g.dart:4729:      productId: productId == null && nullToAbsent
inventario-Frontend/lib/core/database/app_database.g.dart:4731:          : Value(productId),
inventario-Frontend/lib/core/database/app_database.g.dart:4746:      productId: serializer.fromJson<String?>(json['productId']),
inventario-Frontend/lib/core/database/app_database.g.dart:4761:      'productId': serializer.toJson<String?>(productId),
inventario-Frontend/lib/core/database/app_database.g.dart:4774:          Value<String?> productId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:4783:        productId: productId.present ? productId.value : this.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:4795:      productId: data.productId.present ? data.productId.value : this.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:4810:          ..write('productId: $productId, ')
inventario-Frontend/lib/core/database/app_database.g.dart:4821:  int get hashCode => Object.hash(id, purchaseId, productId, quantity, unitCost,
inventario-Frontend/lib/core/database/app_database.g.dart:4829:          other.productId == this.productId &&
inventario-Frontend/lib/core/database/app_database.g.dart:4840:  final Value<String?> productId;
inventario-Frontend/lib/core/database/app_database.g.dart:4850:    this.productId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:4861:    this.productId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:4875:    Expression<String>? productId,
inventario-Frontend/lib/core/database/app_database.g.dart:4886:      if (productId != null) 'product_id': productId,
inventario-Frontend/lib/core/database/app_database.g.dart:4899:      Value<String?>? productId,
inventario-Frontend/lib/core/database/app_database.g.dart:4909:      productId: productId ?? this.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:4928:    if (productId.present) {
inventario-Frontend/lib/core/database/app_database.g.dart:4929:      map['product_id'] = Variable<String>(productId.value);
inventario-Frontend/lib/core/database/app_database.g.dart:4958:          ..write('productId: $productId, ')
inventario-Frontend/lib/core/database/app_database.g.dart:4977:  late final $ProductsTable products = $ProductsTable(this);
inventario-Frontend/lib/core/database/app_database.g.dart:4978:  late final $SalesTable sales = $SalesTable(this);
inventario-Frontend/lib/core/database/app_database.g.dart:4979:  late final $SaleItemsTable saleItems = $SaleItemsTable(this);
inventario-Frontend/lib/core/database/app_database.g.dart:4986:  late final ProductDao productDao = ProductDao(this as AppDatabase);
inventario-Frontend/lib/core/database/app_database.g.dart:4987:  late final SaleDao saleDao = SaleDao(this as AppDatabase);
inventario-Frontend/lib/core/database/app_database.g.dart:4998:        products,
inventario-Frontend/lib/core/database/app_database.g.dart:4999:        sales,
inventario-Frontend/lib/core/database/app_database.g.dart:5000:        saleItems,
inventario-Frontend/lib/core/database/app_database.g.dart:5088:  static MultiTypedResultKey<$ProductsTable, List<Product>> _productsRefsTable(
inventario-Frontend/lib/core/database/app_database.g.dart:5090:      MultiTypedResultKey.fromTable(db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:5092:              $_aliasNameGenerator(db.businesses.id, db.products.businessId));
inventario-Frontend/lib/core/database/app_database.g.dart:5094:  $$ProductsTableProcessedTableManager get productsRefs {
inventario-Frontend/lib/core/database/app_database.g.dart:5095:    final manager = $$ProductsTableTableManager($_db, $_db.products)
inventario-Frontend/lib/core/database/app_database.g.dart:5098:    final cache = $_typedResult.readTableOrNull(_productsRefsTable($_db));
inventario-Frontend/lib/core/database/app_database.g.dart:5103:  static MultiTypedResultKey<$SalesTable, List<Sale>> _salesRefsTable(
inventario-Frontend/lib/core/database/app_database.g.dart:5105:      MultiTypedResultKey.fromTable(db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:5107:              $_aliasNameGenerator(db.businesses.id, db.sales.businessId));
inventario-Frontend/lib/core/database/app_database.g.dart:5109:  $$SalesTableProcessedTableManager get salesRefs {
inventario-Frontend/lib/core/database/app_database.g.dart:5110:    final manager = $$SalesTableTableManager($_db, $_db.sales)
inventario-Frontend/lib/core/database/app_database.g.dart:5113:    final cache = $_typedResult.readTableOrNull(_salesRefsTable($_db));
inventario-Frontend/lib/core/database/app_database.g.dart:5134:class $$BusinessesTableFilterComposer
inventario-Frontend/lib/core/database/app_database.g.dart:5135:    extends Composer<_$AppDatabase, $BusinessesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:5136:  $$BusinessesTableFilterComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:5140:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5141:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5143:  ColumnFilters<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5146:  ColumnFilters<String> get name => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5149:  ColumnFilters<String> get businessType => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5152:  ColumnFilters<String> get ownerName => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5155:  ColumnFilters<String> get phone => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5158:  ColumnFilters<String> get email => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5161:  ColumnFilters<String> get address => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5164:  ColumnFilters<String> get subscriptionPlan => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5168:  ColumnFilters<String> get status => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5171:  ColumnFilters<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5174:  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5177:  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5181:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5186:      Expression<bool> Function($$ProfilesTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5187:    final $$ProfilesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5188:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5193:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5194:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5195:            $$ProfilesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5198:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5200:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5201:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5203:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5207:      Expression<bool> Function($$CategoriesTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5208:    final $$CategoriesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5209:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5214:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5215:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5216:            $$CategoriesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5219:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5221:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5222:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5224:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5228:      Expression<bool> Function($$CustomersTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5229:    final $$CustomersTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5230:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5235:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5236:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5237:            $$CustomersTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5240:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5242:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5243:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5245:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5248:  Expression<bool> productsRefs(
inventario-Frontend/lib/core/database/app_database.g.dart:5249:      Expression<bool> Function($$ProductsTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5250:    final $$ProductsTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5251:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5253:        referencedTable: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:5256:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5257:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5258:            $$ProductsTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5260:              $table: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:5261:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5263:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5264:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5266:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5269:  Expression<bool> salesRefs(
inventario-Frontend/lib/core/database/app_database.g.dart:5270:      Expression<bool> Function($$SalesTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5271:    final $$SalesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5272:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5274:        referencedTable: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:5277:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5278:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5279:            $$SalesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5281:              $table: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:5282:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5284:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5285:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5287:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5291:      Expression<bool> Function($$PurchasesTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5292:    final $$PurchasesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5293:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5298:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5299:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5300:            $$PurchasesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5303:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5305:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5306:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5308:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5312:class $$BusinessesTableOrderingComposer
inventario-Frontend/lib/core/database/app_database.g.dart:5313:    extends Composer<_$AppDatabase, $BusinessesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:5314:  $$BusinessesTableOrderingComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:5318:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5319:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5321:  ColumnOrderings<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5324:  ColumnOrderings<String> get name => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5327:  ColumnOrderings<String> get businessType => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5331:  ColumnOrderings<String> get ownerName => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5334:  ColumnOrderings<String> get phone => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5337:  ColumnOrderings<String> get email => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5340:  ColumnOrderings<String> get address => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5343:  ColumnOrderings<String> get subscriptionPlan => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5347:  ColumnOrderings<String> get status => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5350:  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5353:  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5356:  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5359:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5363:class $$BusinessesTableAnnotationComposer
inventario-Frontend/lib/core/database/app_database.g.dart:5364:    extends Composer<_$AppDatabase, $BusinessesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:5365:  $$BusinessesTableAnnotationComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:5369:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5370:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5373:      $composableBuilder(column: $table.id, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5376:      $composableBuilder(column: $table.name, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5378:  GeneratedColumn<String> get businessType => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5382:      $composableBuilder(column: $table.ownerName, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5385:      $composableBuilder(column: $table.phone, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5388:      $composableBuilder(column: $table.email, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5391:      $composableBuilder(column: $table.address, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5393:  GeneratedColumn<String> get subscriptionPlan => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5397:      $composableBuilder(column: $table.status, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5400:      $composableBuilder(column: $table.createdAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5403:      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5406:      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5409:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5413:      Expression<T> Function($$ProfilesTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5414:    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5415:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5420:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5421:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5422:            $$ProfilesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5425:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5427:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5428:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5430:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5434:      Expression<T> Function($$CategoriesTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5435:    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5436:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5441:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5442:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5443:            $$CategoriesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5446:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5448:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5449:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5451:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5455:      Expression<T> Function($$CustomersTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5456:    final $$CustomersTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5457:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5462:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5463:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5464:            $$CustomersTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5467:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5469:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5470:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5472:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5475:  Expression<T> productsRefs<T extends Object>(
inventario-Frontend/lib/core/database/app_database.g.dart:5476:      Expression<T> Function($$ProductsTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5477:    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5478:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5480:        referencedTable: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:5483:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5484:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5485:            $$ProductsTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5487:              $table: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:5488:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5490:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5491:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5493:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5496:  Expression<T> salesRefs<T extends Object>(
inventario-Frontend/lib/core/database/app_database.g.dart:5497:      Expression<T> Function($$SalesTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5498:    final $$SalesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5499:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5501:        referencedTable: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:5504:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5505:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5506:            $$SalesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5508:              $table: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:5509:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5511:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5512:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5514:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5518:      Expression<T> Function($$PurchasesTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5519:    final $$PurchasesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5520:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5525:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5526:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5527:            $$PurchasesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5530:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5532:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5533:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5535:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5543:    $$BusinessesTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5544:    $$BusinessesTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5545:    $$BusinessesTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5554:        bool productsRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:5555:        bool salesRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:5561:          createFilteringComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:5562:              $$BusinessesTableFilterComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:5563:          createOrderingComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:5564:              $$BusinessesTableOrderingComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:5565:          createComputedFieldComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:5566:              $$BusinessesTableAnnotationComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:5641:              productsRefs = false,
inventario-Frontend/lib/core/database/app_database.g.dart:5642:              salesRefs = false,
inventario-Frontend/lib/core/database/app_database.g.dart:5650:                if (productsRefs) db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:5651:                if (salesRefs) db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:5696:                  if (productsRefs)
inventario-Frontend/lib/core/database/app_database.g.dart:5698:                            Product>(
inventario-Frontend/lib/core/database/app_database.g.dart:5701:                            $$BusinessesTableReferences._productsRefsTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:5704:                                .productsRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:5709:                  if (salesRefs)
inventario-Frontend/lib/core/database/app_database.g.dart:5710:                    await $_getPrefetchedData<Business, $BusinessesTable, Sale>(
inventario-Frontend/lib/core/database/app_database.g.dart:5713:                            $$BusinessesTableReferences._salesRefsTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:5716:                                .salesRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:5745:    $$BusinessesTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5746:    $$BusinessesTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5747:    $$BusinessesTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5756:        bool productsRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:5757:        bool salesRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:5801:  static MultiTypedResultKey<$SalesTable, List<Sale>> _salesRefsTable(
inventario-Frontend/lib/core/database/app_database.g.dart:5803:      MultiTypedResultKey.fromTable(db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:5804:          aliasName: $_aliasNameGenerator(db.profiles.id, db.sales.userId));
inventario-Frontend/lib/core/database/app_database.g.dart:5806:  $$SalesTableProcessedTableManager get salesRefs {
inventario-Frontend/lib/core/database/app_database.g.dart:5807:    final manager = $$SalesTableTableManager($_db, $_db.sales)
inventario-Frontend/lib/core/database/app_database.g.dart:5810:    final cache = $_typedResult.readTableOrNull(_salesRefsTable($_db));
inventario-Frontend/lib/core/database/app_database.g.dart:5830:class $$ProfilesTableFilterComposer
inventario-Frontend/lib/core/database/app_database.g.dart:5831:    extends Composer<_$AppDatabase, $ProfilesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:5832:  $$ProfilesTableFilterComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:5836:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5837:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5839:  ColumnFilters<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5842:  ColumnFilters<String> get fullName => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5845:  ColumnFilters<String> get role => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5848:  ColumnFilters<String> get status => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5851:  ColumnFilters<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5854:  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5858:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5862:  $$BusinessesTableFilterComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:5863:    final $$BusinessesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5864:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5869:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5870:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5871:            $$BusinessesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5874:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5876:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5877:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5879:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:5882:  Expression<bool> salesRefs(
inventario-Frontend/lib/core/database/app_database.g.dart:5883:      Expression<bool> Function($$SalesTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5884:    final $$SalesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5885:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5887:        referencedTable: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:5890:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5891:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5892:            $$SalesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5894:              $table: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:5895:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5897:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5898:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5900:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5904:      Expression<bool> Function($$PurchasesTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:5905:    final $$PurchasesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5906:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5911:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5912:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5913:            $$PurchasesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5916:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5918:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5919:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5921:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:5925:class $$ProfilesTableOrderingComposer
inventario-Frontend/lib/core/database/app_database.g.dart:5926:    extends Composer<_$AppDatabase, $ProfilesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:5927:  $$ProfilesTableOrderingComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:5931:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5932:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5934:  ColumnOrderings<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5937:  ColumnOrderings<String> get fullName => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5940:  ColumnOrderings<String> get role => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5943:  ColumnOrderings<String> get status => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5946:  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5949:  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5952:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5955:  $$BusinessesTableOrderingComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:5956:    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:5957:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:5962:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5963:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:5964:            $$BusinessesTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:5967:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5969:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:5970:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5972:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:5976:class $$ProfilesTableAnnotationComposer
inventario-Frontend/lib/core/database/app_database.g.dart:5977:    extends Composer<_$AppDatabase, $ProfilesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:5978:  $$ProfilesTableAnnotationComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:5982:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5983:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:5986:      $composableBuilder(column: $table.id, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5989:      $composableBuilder(column: $table.fullName, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5992:      $composableBuilder(column: $table.role, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5995:      $composableBuilder(column: $table.status, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:5998:      $composableBuilder(column: $table.createdAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6001:      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6004:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6007:  $$BusinessesTableAnnotationComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:6008:    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6009:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6014:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6015:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6016:            $$BusinessesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6019:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6021:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6022:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6024:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:6027:  Expression<T> salesRefs<T extends Object>(
inventario-Frontend/lib/core/database/app_database.g.dart:6028:      Expression<T> Function($$SalesTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:6029:    final $$SalesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6030:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6032:        referencedTable: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:6035:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6036:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6037:            $$SalesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6039:              $table: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:6040:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6042:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6043:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6045:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:6049:      Expression<T> Function($$PurchasesTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:6050:    final $$PurchasesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6051:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6056:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6057:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6058:            $$PurchasesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6061:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6063:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6064:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6066:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:6074:    $$ProfilesTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6075:    $$ProfilesTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6076:    $$ProfilesTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6082:        {bool businessId, bool salesRefs, bool purchasesRefs})> {
inventario-Frontend/lib/core/database/app_database.g.dart:6087:          createFilteringComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:6088:              $$ProfilesTableFilterComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:6089:          createOrderingComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:6090:              $$ProfilesTableOrderingComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:6091:          createComputedFieldComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:6092:              $$ProfilesTableAnnotationComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:6142:              {businessId = false, salesRefs = false, purchasesRefs = false}) {
inventario-Frontend/lib/core/database/app_database.g.dart:6146:                if (salesRefs) db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:6177:                  if (salesRefs)
inventario-Frontend/lib/core/database/app_database.g.dart:6178:                    await $_getPrefetchedData<Profile, $ProfilesTable, Sale>(
inventario-Frontend/lib/core/database/app_database.g.dart:6181:                            $$ProfilesTableReferences._salesRefsTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:6183:                            $$ProfilesTableReferences(db, table, p0).salesRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:6212:    $$ProfilesTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6213:    $$ProfilesTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6214:    $$ProfilesTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6220:        {bool businessId, bool salesRefs, bool purchasesRefs})>;
inventario-Frontend/lib/core/database/app_database.g.dart:6263:  static MultiTypedResultKey<$ProductsTable, List<Product>> _productsRefsTable(
inventario-Frontend/lib/core/database/app_database.g.dart:6265:      MultiTypedResultKey.fromTable(db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:6267:              $_aliasNameGenerator(db.categories.id, db.products.categoryId));
inventario-Frontend/lib/core/database/app_database.g.dart:6269:  $$ProductsTableProcessedTableManager get productsRefs {
inventario-Frontend/lib/core/database/app_database.g.dart:6270:    final manager = $$ProductsTableTableManager($_db, $_db.products)
inventario-Frontend/lib/core/database/app_database.g.dart:6273:    final cache = $_typedResult.readTableOrNull(_productsRefsTable($_db));
inventario-Frontend/lib/core/database/app_database.g.dart:6279:class $$CategoriesTableFilterComposer
inventario-Frontend/lib/core/database/app_database.g.dart:6280:    extends Composer<_$AppDatabase, $CategoriesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:6281:  $$CategoriesTableFilterComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:6285:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6286:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6288:  ColumnFilters<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6291:  ColumnFilters<String> get name => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6294:  ColumnFilters<String> get description => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6297:  ColumnFilters<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6300:  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6303:  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6307:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6311:  $$BusinessesTableFilterComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:6312:    final $$BusinessesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6313:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6318:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6319:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6320:            $$BusinessesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6323:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6325:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6326:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6328:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:6331:  Expression<bool> productsRefs(
inventario-Frontend/lib/core/database/app_database.g.dart:6332:      Expression<bool> Function($$ProductsTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:6333:    final $$ProductsTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6334:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6336:        referencedTable: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:6339:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6340:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6341:            $$ProductsTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6343:              $table: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:6344:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6346:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6347:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6349:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:6353:class $$CategoriesTableOrderingComposer
inventario-Frontend/lib/core/database/app_database.g.dart:6354:    extends Composer<_$AppDatabase, $CategoriesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:6355:  $$CategoriesTableOrderingComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:6359:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6360:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6362:  ColumnOrderings<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6365:  ColumnOrderings<String> get name => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6368:  ColumnOrderings<String> get description => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6371:  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6374:  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6377:  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6380:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6383:  $$BusinessesTableOrderingComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:6384:    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6385:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6390:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6391:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6392:            $$BusinessesTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6395:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6397:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6398:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6400:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:6404:class $$CategoriesTableAnnotationComposer
inventario-Frontend/lib/core/database/app_database.g.dart:6405:    extends Composer<_$AppDatabase, $CategoriesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:6406:  $$CategoriesTableAnnotationComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:6410:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6411:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6414:      $composableBuilder(column: $table.id, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6417:      $composableBuilder(column: $table.name, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6419:  GeneratedColumn<String> get description => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6423:      $composableBuilder(column: $table.createdAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6426:      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6429:      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6432:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6435:  $$BusinessesTableAnnotationComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:6436:    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6437:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6442:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6443:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6444:            $$BusinessesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6447:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6449:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6450:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6452:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:6455:  Expression<T> productsRefs<T extends Object>(
inventario-Frontend/lib/core/database/app_database.g.dart:6456:      Expression<T> Function($$ProductsTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:6457:    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6458:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6460:        referencedTable: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:6463:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6464:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6465:            $$ProductsTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6467:              $table: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:6468:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6470:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6471:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6473:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:6481:    $$CategoriesTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6482:    $$CategoriesTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6483:    $$CategoriesTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6488:    PrefetchHooks Function({bool businessId, bool productsRefs})> {
inventario-Frontend/lib/core/database/app_database.g.dart:6493:          createFilteringComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:6494:              $$CategoriesTableFilterComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:6495:          createOrderingComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:6496:              $$CategoriesTableOrderingComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:6497:          createComputedFieldComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:6498:              $$CategoriesTableAnnotationComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:6549:          prefetchHooksCallback: ({businessId = false, productsRefs = false}) {
inventario-Frontend/lib/core/database/app_database.g.dart:6552:              explicitlyWatchedTables: [if (productsRefs) db.products],
inventario-Frontend/lib/core/database/app_database.g.dart:6581:                  if (productsRefs)
inventario-Frontend/lib/core/database/app_database.g.dart:6583:                            Product>(
inventario-Frontend/lib/core/database/app_database.g.dart:6586:                            $$CategoriesTableReferences._productsRefsTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:6589:                                .productsRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:6605:    $$CategoriesTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6606:    $$CategoriesTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6607:    $$CategoriesTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6612:    PrefetchHooks Function({bool businessId, bool productsRefs})>;
inventario-Frontend/lib/core/database/app_database.g.dart:6659:  static MultiTypedResultKey<$SalesTable, List<Sale>> _salesRefsTable(
inventario-Frontend/lib/core/database/app_database.g.dart:6661:      MultiTypedResultKey.fromTable(db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:6663:              $_aliasNameGenerator(db.customers.id, db.sales.customerId));
inventario-Frontend/lib/core/database/app_database.g.dart:6665:  $$SalesTableProcessedTableManager get salesRefs {
inventario-Frontend/lib/core/database/app_database.g.dart:6666:    final manager = $$SalesTableTableManager($_db, $_db.sales)
inventario-Frontend/lib/core/database/app_database.g.dart:6669:    final cache = $_typedResult.readTableOrNull(_salesRefsTable($_db));
inventario-Frontend/lib/core/database/app_database.g.dart:6675:class $$CustomersTableFilterComposer
inventario-Frontend/lib/core/database/app_database.g.dart:6676:    extends Composer<_$AppDatabase, $CustomersTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:6677:  $$CustomersTableFilterComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:6681:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6682:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6684:  ColumnFilters<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6687:  ColumnFilters<String> get fullName => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6690:  ColumnFilters<String> get phone => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6693:  ColumnFilters<String> get email => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6696:  ColumnFilters<String> get address => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6699:  ColumnFilters<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6702:  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6705:  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6709:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6713:  $$BusinessesTableFilterComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:6714:    final $$BusinessesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6715:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6720:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6721:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6722:            $$BusinessesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6725:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6727:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6728:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6730:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:6733:  Expression<bool> salesRefs(
inventario-Frontend/lib/core/database/app_database.g.dart:6734:      Expression<bool> Function($$SalesTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:6735:    final $$SalesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6736:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6738:        referencedTable: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:6741:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6742:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6743:            $$SalesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6745:              $table: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:6746:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6748:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6749:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6751:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:6755:class $$CustomersTableOrderingComposer
inventario-Frontend/lib/core/database/app_database.g.dart:6756:    extends Composer<_$AppDatabase, $CustomersTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:6757:  $$CustomersTableOrderingComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:6761:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6762:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6764:  ColumnOrderings<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6767:  ColumnOrderings<String> get fullName => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6770:  ColumnOrderings<String> get phone => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6773:  ColumnOrderings<String> get email => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6776:  ColumnOrderings<String> get address => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6779:  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6782:  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6785:  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6788:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6791:  $$BusinessesTableOrderingComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:6792:    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6793:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6798:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6799:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6800:            $$BusinessesTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6803:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6805:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6806:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6808:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:6812:class $$CustomersTableAnnotationComposer
inventario-Frontend/lib/core/database/app_database.g.dart:6813:    extends Composer<_$AppDatabase, $CustomersTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:6814:  $$CustomersTableAnnotationComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:6818:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6819:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6822:      $composableBuilder(column: $table.id, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6825:      $composableBuilder(column: $table.fullName, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6828:      $composableBuilder(column: $table.phone, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6831:      $composableBuilder(column: $table.email, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6834:      $composableBuilder(column: $table.address, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6837:      $composableBuilder(column: $table.createdAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6840:      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6843:      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:6846:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6849:  $$BusinessesTableAnnotationComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:6850:    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6851:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6856:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6857:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6858:            $$BusinessesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6861:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6863:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6864:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6866:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:6869:  Expression<T> salesRefs<T extends Object>(
inventario-Frontend/lib/core/database/app_database.g.dart:6870:      Expression<T> Function($$SalesTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:6871:    final $$SalesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:6872:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:6874:        referencedTable: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:6877:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6878:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:6879:            $$SalesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:6881:              $table: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:6882:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6884:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:6885:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6887:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:6895:    $$CustomersTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6896:    $$CustomersTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6897:    $$CustomersTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:6902:    PrefetchHooks Function({bool businessId, bool salesRefs})> {
inventario-Frontend/lib/core/database/app_database.g.dart:6907:          createFilteringComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:6908:              $$CustomersTableFilterComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:6909:          createOrderingComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:6910:              $$CustomersTableOrderingComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:6911:          createComputedFieldComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:6912:              $$CustomersTableAnnotationComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:6971:          prefetchHooksCallback: ({businessId = false, salesRefs = false}) {
inventario-Frontend/lib/core/database/app_database.g.dart:6974:              explicitlyWatchedTables: [if (salesRefs) db.sales],
inventario-Frontend/lib/core/database/app_database.g.dart:7003:                  if (salesRefs)
inventario-Frontend/lib/core/database/app_database.g.dart:7004:                    await $_getPrefetchedData<Customer, $CustomersTable, Sale>(
inventario-Frontend/lib/core/database/app_database.g.dart:7007:                            $$CustomersTableReferences._salesRefsTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:7009:                            $$CustomersTableReferences(db, table, p0).salesRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:7025:    $$CustomersTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7026:    $$CustomersTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7027:    $$CustomersTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7032:    PrefetchHooks Function({bool businessId, bool salesRefs})>;
inventario-Frontend/lib/core/database/app_database.g.dart:7033:typedef $$ProductsTableCreateCompanionBuilder = ProductsCompanion Function({
inventario-Frontend/lib/core/database/app_database.g.dart:7037:  Value<String?> barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:7041:  required double salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:7053:typedef $$ProductsTableUpdateCompanionBuilder = ProductsCompanion Function({
inventario-Frontend/lib/core/database/app_database.g.dart:7057:  Value<String?> barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:7061:  Value<double> salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:7074:final class $$ProductsTableReferences
inventario-Frontend/lib/core/database/app_database.g.dart:7075:    extends BaseReferences<_$AppDatabase, $ProductsTable, Product> {
inventario-Frontend/lib/core/database/app_database.g.dart:7076:  $$ProductsTableReferences(super.$_db, super.$_table, super.$_typedResult);
inventario-Frontend/lib/core/database/app_database.g.dart:7080:          $_aliasNameGenerator(db.products.businessId, db.businesses.id));
inventario-Frontend/lib/core/database/app_database.g.dart:7095:          $_aliasNameGenerator(db.products.categoryId, db.categories.id));
inventario-Frontend/lib/core/database/app_database.g.dart:7108:  static MultiTypedResultKey<$SaleItemsTable, List<SaleItem>>
inventario-Frontend/lib/core/database/app_database.g.dart:7109:      _saleItemsRefsTable(_$AppDatabase db) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7110:          MultiTypedResultKey.fromTable(db.saleItems,
inventario-Frontend/lib/core/database/app_database.g.dart:7112:                  $_aliasNameGenerator(db.products.id, db.saleItems.productId));
inventario-Frontend/lib/core/database/app_database.g.dart:7114:  $$SaleItemsTableProcessedTableManager get saleItemsRefs {
inventario-Frontend/lib/core/database/app_database.g.dart:7115:    final manager = $$SaleItemsTableTableManager($_db, $_db.saleItems)
inventario-Frontend/lib/core/database/app_database.g.dart:7116:        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));
inventario-Frontend/lib/core/database/app_database.g.dart:7118:    final cache = $_typedResult.readTableOrNull(_saleItemsRefsTable($_db));
inventario-Frontend/lib/core/database/app_database.g.dart:7127:                  db.products.id, db.purchaseItems.productId));
inventario-Frontend/lib/core/database/app_database.g.dart:7131:        .filter((f) => f.productId.id.sqlEquals($_itemColumn<String>('id')!));
inventario-Frontend/lib/core/database/app_database.g.dart:7139:class $$ProductsTableFilterComposer
inventario-Frontend/lib/core/database/app_database.g.dart:7140:    extends Composer<_$AppDatabase, $ProductsTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:7141:  $$ProductsTableFilterComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:7145:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7146:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7148:  ColumnFilters<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7151:  ColumnFilters<String> get barcode => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7152:      column: $table.barcode, builder: (column) => ColumnFilters(column));
inventario-Frontend/lib/core/database/app_database.g.dart:7154:  ColumnFilters<String> get name => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7157:  ColumnFilters<String> get description => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7160:  ColumnFilters<double> get purchasePrice => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7163:  ColumnFilters<double> get salePrice => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7164:      column: $table.salePrice, builder: (column) => ColumnFilters(column));
inventario-Frontend/lib/core/database/app_database.g.dart:7166:  ColumnFilters<int> get stockQuantity => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7169:  ColumnFilters<int> get minimumStock => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7172:  ColumnFilters<String> get unit => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7175:  ColumnFilters<String> get status => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7178:  ColumnFilters<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7181:  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7184:  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7187:  ColumnFilters<String> get simpleCategory => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7192:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7196:  $$BusinessesTableFilterComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:7197:    final $$BusinessesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7198:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7203:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7204:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7205:            $$BusinessesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7208:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7210:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7211:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7213:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:7216:  $$CategoriesTableFilterComposer get categoryId {
inventario-Frontend/lib/core/database/app_database.g.dart:7217:    final $$CategoriesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7218:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7223:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7224:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7225:            $$CategoriesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7228:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7230:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7231:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7233:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:7236:  Expression<bool> saleItemsRefs(
inventario-Frontend/lib/core/database/app_database.g.dart:7237:      Expression<bool> Function($$SaleItemsTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:7238:    final $$SaleItemsTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7239:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7241:        referencedTable: $db.saleItems,
inventario-Frontend/lib/core/database/app_database.g.dart:7242:        getReferencedColumn: (t) => t.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:7244:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7245:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7246:            $$SaleItemsTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7248:              $table: $db.saleItems,
inventario-Frontend/lib/core/database/app_database.g.dart:7249:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7251:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7252:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7254:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:7258:      Expression<bool> Function($$PurchaseItemsTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:7259:    final $$PurchaseItemsTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7260:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7263:        getReferencedColumn: (t) => t.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:7265:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7266:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7267:            $$PurchaseItemsTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7270:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7272:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7273:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7275:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:7279:class $$ProductsTableOrderingComposer
inventario-Frontend/lib/core/database/app_database.g.dart:7280:    extends Composer<_$AppDatabase, $ProductsTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:7281:  $$ProductsTableOrderingComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:7285:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7286:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7288:  ColumnOrderings<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7291:  ColumnOrderings<String> get barcode => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7292:      column: $table.barcode, builder: (column) => ColumnOrderings(column));
inventario-Frontend/lib/core/database/app_database.g.dart:7294:  ColumnOrderings<String> get name => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7297:  ColumnOrderings<String> get description => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7300:  ColumnOrderings<double> get purchasePrice => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7304:  ColumnOrderings<double> get salePrice => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7305:      column: $table.salePrice, builder: (column) => ColumnOrderings(column));
inventario-Frontend/lib/core/database/app_database.g.dart:7307:  ColumnOrderings<int> get stockQuantity => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7311:  ColumnOrderings<int> get minimumStock => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7315:  ColumnOrderings<String> get unit => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7318:  ColumnOrderings<String> get status => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7321:  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7324:  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7327:  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7330:  ColumnOrderings<String> get simpleCategory => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7334:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7337:  $$BusinessesTableOrderingComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:7338:    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7339:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7344:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7345:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7346:            $$BusinessesTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7349:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7351:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7352:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7354:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:7357:  $$CategoriesTableOrderingComposer get categoryId {
inventario-Frontend/lib/core/database/app_database.g.dart:7358:    final $$CategoriesTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7359:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7364:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7365:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7366:            $$CategoriesTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7369:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7371:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7372:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7374:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:7378:class $$ProductsTableAnnotationComposer
inventario-Frontend/lib/core/database/app_database.g.dart:7379:    extends Composer<_$AppDatabase, $ProductsTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:7380:  $$ProductsTableAnnotationComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:7384:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7385:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7388:      $composableBuilder(column: $table.id, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:7390:  GeneratedColumn<String> get barcode =>
inventario-Frontend/lib/core/database/app_database.g.dart:7391:      $composableBuilder(column: $table.barcode, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:7394:      $composableBuilder(column: $table.name, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:7396:  GeneratedColumn<String> get description => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7399:  GeneratedColumn<double> get purchasePrice => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7402:  GeneratedColumn<double> get salePrice =>
inventario-Frontend/lib/core/database/app_database.g.dart:7403:      $composableBuilder(column: $table.salePrice, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:7405:  GeneratedColumn<int> get stockQuantity => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7408:  GeneratedColumn<int> get minimumStock => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7412:      $composableBuilder(column: $table.unit, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:7415:      $composableBuilder(column: $table.status, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:7418:      $composableBuilder(column: $table.createdAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:7421:      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:7424:      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:7426:  GeneratedColumn<String> get simpleCategory => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7430:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7433:  $$BusinessesTableAnnotationComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:7434:    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7435:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7440:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7441:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7442:            $$BusinessesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7445:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7447:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7448:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7450:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:7453:  $$CategoriesTableAnnotationComposer get categoryId {
inventario-Frontend/lib/core/database/app_database.g.dart:7454:    final $$CategoriesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7455:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7460:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7461:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7462:            $$CategoriesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7465:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7467:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7468:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7470:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:7473:  Expression<T> saleItemsRefs<T extends Object>(
inventario-Frontend/lib/core/database/app_database.g.dart:7474:      Expression<T> Function($$SaleItemsTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:7475:    final $$SaleItemsTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7476:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7478:        referencedTable: $db.saleItems,
inventario-Frontend/lib/core/database/app_database.g.dart:7479:        getReferencedColumn: (t) => t.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:7481:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7482:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7483:            $$SaleItemsTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7485:              $table: $db.saleItems,
inventario-Frontend/lib/core/database/app_database.g.dart:7486:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7488:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7489:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7491:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:7495:      Expression<T> Function($$PurchaseItemsTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:7496:    final $$PurchaseItemsTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7497:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7500:        getReferencedColumn: (t) => t.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:7502:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7503:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7504:            $$PurchaseItemsTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7507:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7509:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7510:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7512:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:7516:class $$ProductsTableTableManager extends RootTableManager<
inventario-Frontend/lib/core/database/app_database.g.dart:7518:    $ProductsTable,
inventario-Frontend/lib/core/database/app_database.g.dart:7519:    Product,
inventario-Frontend/lib/core/database/app_database.g.dart:7520:    $$ProductsTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7521:    $$ProductsTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7522:    $$ProductsTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7523:    $$ProductsTableCreateCompanionBuilder,
inventario-Frontend/lib/core/database/app_database.g.dart:7524:    $$ProductsTableUpdateCompanionBuilder,
inventario-Frontend/lib/core/database/app_database.g.dart:7525:    (Product, $$ProductsTableReferences),
inventario-Frontend/lib/core/database/app_database.g.dart:7526:    Product,
inventario-Frontend/lib/core/database/app_database.g.dart:7530:        bool saleItemsRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:7532:  $$ProductsTableTableManager(_$AppDatabase db, $ProductsTable table)
inventario-Frontend/lib/core/database/app_database.g.dart:7536:          createFilteringComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:7537:              $$ProductsTableFilterComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:7538:          createOrderingComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:7539:              $$ProductsTableOrderingComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:7540:          createComputedFieldComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:7541:              $$ProductsTableAnnotationComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:7546:            Value<String?> barcode = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:7550:            Value<double> salePrice = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:7562:              ProductsCompanion(
inventario-Frontend/lib/core/database/app_database.g.dart:7566:            barcode: barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:7570:            salePrice: salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:7586:            Value<String?> barcode = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:7590:            required double salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:7602:              ProductsCompanion.insert(
inventario-Frontend/lib/core/database/app_database.g.dart:7606:            barcode: barcode,
inventario-Frontend/lib/core/database/app_database.g.dart:7610:            salePrice: salePrice,
inventario-Frontend/lib/core/database/app_database.g.dart:7624:                  (e.readTable(table), $$ProductsTableReferences(db, table, e)))
inventario-Frontend/lib/core/database/app_database.g.dart:7629:              saleItemsRefs = false,
inventario-Frontend/lib/core/database/app_database.g.dart:7634:                if (saleItemsRefs) db.saleItems,
inventario-Frontend/lib/core/database/app_database.g.dart:7655:                        $$ProductsTableReferences._businessIdTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:7657:                        $$ProductsTableReferences._businessIdTable(db).id,
inventario-Frontend/lib/core/database/app_database.g.dart:7665:                        $$ProductsTableReferences._categoryIdTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:7667:                        $$ProductsTableReferences._categoryIdTable(db).id,
inventario-Frontend/lib/core/database/app_database.g.dart:7675:                  if (saleItemsRefs)
inventario-Frontend/lib/core/database/app_database.g.dart:7676:                    await $_getPrefetchedData<Product, $ProductsTable,
inventario-Frontend/lib/core/database/app_database.g.dart:7677:                            SaleItem>(
inventario-Frontend/lib/core/database/app_database.g.dart:7680:                            $$ProductsTableReferences._saleItemsRefsTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:7682:                            $$ProductsTableReferences(db, table, p0)
inventario-Frontend/lib/core/database/app_database.g.dart:7683:                                .saleItemsRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:7686:                                .where((e) => e.productId == item.id),
inventario-Frontend/lib/core/database/app_database.g.dart:7689:                    await $_getPrefetchedData<Product, $ProductsTable,
inventario-Frontend/lib/core/database/app_database.g.dart:7692:                        referencedTable: $$ProductsTableReferences
inventario-Frontend/lib/core/database/app_database.g.dart:7695:                            $$ProductsTableReferences(db, table, p0)
inventario-Frontend/lib/core/database/app_database.g.dart:7699:                                .where((e) => e.productId == item.id),
inventario-Frontend/lib/core/database/app_database.g.dart:7708:typedef $$ProductsTableProcessedTableManager = ProcessedTableManager<
inventario-Frontend/lib/core/database/app_database.g.dart:7710:    $ProductsTable,
inventario-Frontend/lib/core/database/app_database.g.dart:7711:    Product,
inventario-Frontend/lib/core/database/app_database.g.dart:7712:    $$ProductsTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7713:    $$ProductsTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7714:    $$ProductsTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7715:    $$ProductsTableCreateCompanionBuilder,
inventario-Frontend/lib/core/database/app_database.g.dart:7716:    $$ProductsTableUpdateCompanionBuilder,
inventario-Frontend/lib/core/database/app_database.g.dart:7717:    (Product, $$ProductsTableReferences),
inventario-Frontend/lib/core/database/app_database.g.dart:7718:    Product,
inventario-Frontend/lib/core/database/app_database.g.dart:7722:        bool saleItemsRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:7724:typedef $$SalesTableCreateCompanionBuilder = SalesCompanion Function({
inventario-Frontend/lib/core/database/app_database.g.dart:7738:typedef $$SalesTableUpdateCompanionBuilder = SalesCompanion Function({
inventario-Frontend/lib/core/database/app_database.g.dart:7753:final class $$SalesTableReferences
inventario-Frontend/lib/core/database/app_database.g.dart:7754:    extends BaseReferences<_$AppDatabase, $SalesTable, Sale> {
inventario-Frontend/lib/core/database/app_database.g.dart:7755:  $$SalesTableReferences(super.$_db, super.$_table, super.$_typedResult);
inventario-Frontend/lib/core/database/app_database.g.dart:7758:      .createAlias($_aliasNameGenerator(db.sales.businessId, db.businesses.id));
inventario-Frontend/lib/core/database/app_database.g.dart:7772:      .createAlias($_aliasNameGenerator(db.sales.userId, db.profiles.id));
inventario-Frontend/lib/core/database/app_database.g.dart:7786:      .createAlias($_aliasNameGenerator(db.sales.customerId, db.customers.id));
inventario-Frontend/lib/core/database/app_database.g.dart:7799:  static MultiTypedResultKey<$SaleItemsTable, List<SaleItem>>
inventario-Frontend/lib/core/database/app_database.g.dart:7800:      _saleItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
inventario-Frontend/lib/core/database/app_database.g.dart:7801:          db.saleItems,
inventario-Frontend/lib/core/database/app_database.g.dart:7802:          aliasName: $_aliasNameGenerator(db.sales.id, db.saleItems.saleId));
inventario-Frontend/lib/core/database/app_database.g.dart:7804:  $$SaleItemsTableProcessedTableManager get saleItemsRefs {
inventario-Frontend/lib/core/database/app_database.g.dart:7805:    final manager = $$SaleItemsTableTableManager($_db, $_db.saleItems)
inventario-Frontend/lib/core/database/app_database.g.dart:7806:        .filter((f) => f.saleId.id.sqlEquals($_itemColumn<String>('id')!));
inventario-Frontend/lib/core/database/app_database.g.dart:7808:    final cache = $_typedResult.readTableOrNull(_saleItemsRefsTable($_db));
inventario-Frontend/lib/core/database/app_database.g.dart:7814:class $$SalesTableFilterComposer extends Composer<_$AppDatabase, $SalesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:7815:  $$SalesTableFilterComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:7819:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7820:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7822:  ColumnFilters<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7825:  ColumnFilters<double> get total => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7828:  ColumnFilters<String> get paymentMethod => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7831:  ColumnFilters<String> get status => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7834:  ColumnFilters<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7837:  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7840:  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7844:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7848:  $$BusinessesTableFilterComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:7849:    final $$BusinessesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7850:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7855:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7856:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7857:            $$BusinessesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7860:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7862:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7863:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7865:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:7868:  $$ProfilesTableFilterComposer get userId {
inventario-Frontend/lib/core/database/app_database.g.dart:7869:    final $$ProfilesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7870:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7875:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7876:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7877:            $$ProfilesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7880:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7882:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7883:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7885:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:7888:  $$CustomersTableFilterComposer get customerId {
inventario-Frontend/lib/core/database/app_database.g.dart:7889:    final $$CustomersTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7890:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7895:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7896:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7897:            $$CustomersTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7900:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7902:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7903:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7905:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:7908:  Expression<bool> saleItemsRefs(
inventario-Frontend/lib/core/database/app_database.g.dart:7909:      Expression<bool> Function($$SaleItemsTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:7910:    final $$SaleItemsTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7911:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7913:        referencedTable: $db.saleItems,
inventario-Frontend/lib/core/database/app_database.g.dart:7914:        getReferencedColumn: (t) => t.saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:7916:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7917:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7918:            $$SaleItemsTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7920:              $table: $db.saleItems,
inventario-Frontend/lib/core/database/app_database.g.dart:7921:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7923:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7924:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7926:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:7930:class $$SalesTableOrderingComposer
inventario-Frontend/lib/core/database/app_database.g.dart:7931:    extends Composer<_$AppDatabase, $SalesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:7932:  $$SalesTableOrderingComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:7936:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7937:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7939:  ColumnOrderings<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7942:  ColumnOrderings<double> get total => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7945:  ColumnOrderings<String> get paymentMethod => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7949:  ColumnOrderings<String> get status => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7952:  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7955:  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7958:  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7961:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7964:  $$BusinessesTableOrderingComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:7965:    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7966:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7971:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7972:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7973:            $$BusinessesTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7976:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7978:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7979:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7981:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:7984:  $$ProfilesTableOrderingComposer get userId {
inventario-Frontend/lib/core/database/app_database.g.dart:7985:    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:7986:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:7991:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7992:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:7993:            $$ProfilesTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:7996:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:7998:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:7999:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8001:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8004:  $$CustomersTableOrderingComposer get customerId {
inventario-Frontend/lib/core/database/app_database.g.dart:8005:    final $$CustomersTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8006:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8011:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8012:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8013:            $$CustomersTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8016:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8018:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8019:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8021:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8025:class $$SalesTableAnnotationComposer
inventario-Frontend/lib/core/database/app_database.g.dart:8026:    extends Composer<_$AppDatabase, $SalesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:8027:  $$SalesTableAnnotationComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:8031:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8032:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8035:      $composableBuilder(column: $table.id, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8038:      $composableBuilder(column: $table.total, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8040:  GeneratedColumn<String> get paymentMethod => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8044:      $composableBuilder(column: $table.status, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8047:      $composableBuilder(column: $table.createdAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8050:      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8053:      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8056:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8059:  $$BusinessesTableAnnotationComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:8060:    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8061:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8066:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8067:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8068:            $$BusinessesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8071:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8073:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8074:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8076:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8079:  $$ProfilesTableAnnotationComposer get userId {
inventario-Frontend/lib/core/database/app_database.g.dart:8080:    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8081:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8086:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8087:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8088:            $$ProfilesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8091:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8093:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8094:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8096:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8099:  $$CustomersTableAnnotationComposer get customerId {
inventario-Frontend/lib/core/database/app_database.g.dart:8100:    final $$CustomersTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8101:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8106:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8107:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8108:            $$CustomersTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8111:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8113:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8114:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8116:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8119:  Expression<T> saleItemsRefs<T extends Object>(
inventario-Frontend/lib/core/database/app_database.g.dart:8120:      Expression<T> Function($$SaleItemsTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:8121:    final $$SaleItemsTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8122:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8124:        referencedTable: $db.saleItems,
inventario-Frontend/lib/core/database/app_database.g.dart:8125:        getReferencedColumn: (t) => t.saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:8127:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8128:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8129:            $$SaleItemsTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8131:              $table: $db.saleItems,
inventario-Frontend/lib/core/database/app_database.g.dart:8132:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8134:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8135:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8137:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:8141:class $$SalesTableTableManager extends RootTableManager<
inventario-Frontend/lib/core/database/app_database.g.dart:8143:    $SalesTable,
inventario-Frontend/lib/core/database/app_database.g.dart:8144:    Sale,
inventario-Frontend/lib/core/database/app_database.g.dart:8145:    $$SalesTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8146:    $$SalesTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8147:    $$SalesTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8148:    $$SalesTableCreateCompanionBuilder,
inventario-Frontend/lib/core/database/app_database.g.dart:8149:    $$SalesTableUpdateCompanionBuilder,
inventario-Frontend/lib/core/database/app_database.g.dart:8150:    (Sale, $$SalesTableReferences),
inventario-Frontend/lib/core/database/app_database.g.dart:8151:    Sale,
inventario-Frontend/lib/core/database/app_database.g.dart:8153:        {bool businessId, bool userId, bool customerId, bool saleItemsRefs})> {
inventario-Frontend/lib/core/database/app_database.g.dart:8154:  $$SalesTableTableManager(_$AppDatabase db, $SalesTable table)
inventario-Frontend/lib/core/database/app_database.g.dart:8158:          createFilteringComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:8159:              $$SalesTableFilterComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:8160:          createOrderingComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:8161:              $$SalesTableOrderingComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:8162:          createComputedFieldComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:8163:              $$SalesTableAnnotationComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:8178:              SalesCompanion(
inventario-Frontend/lib/core/database/app_database.g.dart:8206:              SalesCompanion.insert(
inventario-Frontend/lib/core/database/app_database.g.dart:8222:                  (e.readTable(table), $$SalesTableReferences(db, table, e)))
inventario-Frontend/lib/core/database/app_database.g.dart:8228:              saleItemsRefs = false}) {
inventario-Frontend/lib/core/database/app_database.g.dart:8231:              explicitlyWatchedTables: [if (saleItemsRefs) db.saleItems],
inventario-Frontend/lib/core/database/app_database.g.dart:8250:                        $$SalesTableReferences._businessIdTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:8252:                        $$SalesTableReferences._businessIdTable(db).id,
inventario-Frontend/lib/core/database/app_database.g.dart:8259:                    referencedTable: $$SalesTableReferences._userIdTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:8261:                        $$SalesTableReferences._userIdTable(db).id,
inventario-Frontend/lib/core/database/app_database.g.dart:8269:                        $$SalesTableReferences._customerIdTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:8271:                        $$SalesTableReferences._customerIdTable(db).id,
inventario-Frontend/lib/core/database/app_database.g.dart:8279:                  if (saleItemsRefs)
inventario-Frontend/lib/core/database/app_database.g.dart:8280:                    await $_getPrefetchedData<Sale, $SalesTable, SaleItem>(
inventario-Frontend/lib/core/database/app_database.g.dart:8283:                            $$SalesTableReferences._saleItemsRefsTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:8285:                            $$SalesTableReferences(db, table, p0).saleItemsRefs,
inventario-Frontend/lib/core/database/app_database.g.dart:8288:                            referencedItems.where((e) => e.saleId == item.id),
inventario-Frontend/lib/core/database/app_database.g.dart:8297:typedef $$SalesTableProcessedTableManager = ProcessedTableManager<
inventario-Frontend/lib/core/database/app_database.g.dart:8299:    $SalesTable,
inventario-Frontend/lib/core/database/app_database.g.dart:8300:    Sale,
inventario-Frontend/lib/core/database/app_database.g.dart:8301:    $$SalesTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8302:    $$SalesTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8303:    $$SalesTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8304:    $$SalesTableCreateCompanionBuilder,
inventario-Frontend/lib/core/database/app_database.g.dart:8305:    $$SalesTableUpdateCompanionBuilder,
inventario-Frontend/lib/core/database/app_database.g.dart:8306:    (Sale, $$SalesTableReferences),
inventario-Frontend/lib/core/database/app_database.g.dart:8307:    Sale,
inventario-Frontend/lib/core/database/app_database.g.dart:8309:        {bool businessId, bool userId, bool customerId, bool saleItemsRefs})>;
inventario-Frontend/lib/core/database/app_database.g.dart:8310:typedef $$SaleItemsTableCreateCompanionBuilder = SaleItemsCompanion Function({
inventario-Frontend/lib/core/database/app_database.g.dart:8312:  Value<String?> saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:8313:  Value<String?> productId,
inventario-Frontend/lib/core/database/app_database.g.dart:8321:typedef $$SaleItemsTableUpdateCompanionBuilder = SaleItemsCompanion Function({
inventario-Frontend/lib/core/database/app_database.g.dart:8323:  Value<String?> saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:8324:  Value<String?> productId,
inventario-Frontend/lib/core/database/app_database.g.dart:8333:final class $$SaleItemsTableReferences
inventario-Frontend/lib/core/database/app_database.g.dart:8334:    extends BaseReferences<_$AppDatabase, $SaleItemsTable, SaleItem> {
inventario-Frontend/lib/core/database/app_database.g.dart:8335:  $$SaleItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);
inventario-Frontend/lib/core/database/app_database.g.dart:8337:  static $SalesTable _saleIdTable(_$AppDatabase db) => db.sales
inventario-Frontend/lib/core/database/app_database.g.dart:8338:      .createAlias($_aliasNameGenerator(db.saleItems.saleId, db.sales.id));
inventario-Frontend/lib/core/database/app_database.g.dart:8340:  $$SalesTableProcessedTableManager? get saleId {
inventario-Frontend/lib/core/database/app_database.g.dart:8341:    final $_column = $_itemColumn<String>('sale_id');
inventario-Frontend/lib/core/database/app_database.g.dart:8343:    final manager = $$SalesTableTableManager($_db, $_db.sales)
inventario-Frontend/lib/core/database/app_database.g.dart:8345:    final item = $_typedResult.readTableOrNull(_saleIdTable($_db));
inventario-Frontend/lib/core/database/app_database.g.dart:8351:  static $ProductsTable _productIdTable(_$AppDatabase db) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8352:      db.products.createAlias(
inventario-Frontend/lib/core/database/app_database.g.dart:8353:          $_aliasNameGenerator(db.saleItems.productId, db.products.id));
inventario-Frontend/lib/core/database/app_database.g.dart:8355:  $$ProductsTableProcessedTableManager? get productId {
inventario-Frontend/lib/core/database/app_database.g.dart:8356:    final $_column = $_itemColumn<String>('product_id');
inventario-Frontend/lib/core/database/app_database.g.dart:8358:    final manager = $$ProductsTableTableManager($_db, $_db.products)
inventario-Frontend/lib/core/database/app_database.g.dart:8360:    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
inventario-Frontend/lib/core/database/app_database.g.dart:8367:class $$SaleItemsTableFilterComposer
inventario-Frontend/lib/core/database/app_database.g.dart:8368:    extends Composer<_$AppDatabase, $SaleItemsTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:8369:  $$SaleItemsTableFilterComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:8373:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8374:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8376:  ColumnFilters<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8379:  ColumnFilters<int> get quantity => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8382:  ColumnFilters<double> get unitPrice => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8385:  ColumnFilters<double> get subtotal => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8388:  ColumnFilters<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8392:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8396:  $$SalesTableFilterComposer get saleId {
inventario-Frontend/lib/core/database/app_database.g.dart:8397:    final $$SalesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8398:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8399:        getCurrentColumn: (t) => t.saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:8400:        referencedTable: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:8403:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8404:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8405:            $$SalesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8407:              $table: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:8408:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8410:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8411:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8413:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8416:  $$ProductsTableFilterComposer get productId {
inventario-Frontend/lib/core/database/app_database.g.dart:8417:    final $$ProductsTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8418:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8419:        getCurrentColumn: (t) => t.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:8420:        referencedTable: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:8423:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8424:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8425:            $$ProductsTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8427:              $table: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:8428:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8430:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8431:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8433:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8437:class $$SaleItemsTableOrderingComposer
inventario-Frontend/lib/core/database/app_database.g.dart:8438:    extends Composer<_$AppDatabase, $SaleItemsTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:8439:  $$SaleItemsTableOrderingComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:8443:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8444:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8446:  ColumnOrderings<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8449:  ColumnOrderings<int> get quantity => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8452:  ColumnOrderings<double> get unitPrice => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8455:  ColumnOrderings<double> get subtotal => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8458:  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8461:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8464:  $$SalesTableOrderingComposer get saleId {
inventario-Frontend/lib/core/database/app_database.g.dart:8465:    final $$SalesTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8466:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8467:        getCurrentColumn: (t) => t.saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:8468:        referencedTable: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:8471:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8472:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8473:            $$SalesTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8475:              $table: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:8476:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8478:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8479:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8481:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8484:  $$ProductsTableOrderingComposer get productId {
inventario-Frontend/lib/core/database/app_database.g.dart:8485:    final $$ProductsTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8486:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8487:        getCurrentColumn: (t) => t.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:8488:        referencedTable: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:8491:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8492:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8493:            $$ProductsTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8495:              $table: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:8496:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8498:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8499:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8501:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8505:class $$SaleItemsTableAnnotationComposer
inventario-Frontend/lib/core/database/app_database.g.dart:8506:    extends Composer<_$AppDatabase, $SaleItemsTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:8507:  $$SaleItemsTableAnnotationComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:8511:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8512:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8515:      $composableBuilder(column: $table.id, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8518:      $composableBuilder(column: $table.quantity, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8521:      $composableBuilder(column: $table.unitPrice, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8524:      $composableBuilder(column: $table.subtotal, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8527:      $composableBuilder(column: $table.createdAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8530:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8533:  $$SalesTableAnnotationComposer get saleId {
inventario-Frontend/lib/core/database/app_database.g.dart:8534:    final $$SalesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8535:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8536:        getCurrentColumn: (t) => t.saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:8537:        referencedTable: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:8540:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8541:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8542:            $$SalesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8544:              $table: $db.sales,
inventario-Frontend/lib/core/database/app_database.g.dart:8545:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8547:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8548:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8550:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8553:  $$ProductsTableAnnotationComposer get productId {
inventario-Frontend/lib/core/database/app_database.g.dart:8554:    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8555:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8556:        getCurrentColumn: (t) => t.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:8557:        referencedTable: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:8560:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8561:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8562:            $$ProductsTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8564:              $table: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:8565:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8567:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8568:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8570:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8574:class $$SaleItemsTableTableManager extends RootTableManager<
inventario-Frontend/lib/core/database/app_database.g.dart:8576:    $SaleItemsTable,
inventario-Frontend/lib/core/database/app_database.g.dart:8577:    SaleItem,
inventario-Frontend/lib/core/database/app_database.g.dart:8578:    $$SaleItemsTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8579:    $$SaleItemsTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8580:    $$SaleItemsTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8581:    $$SaleItemsTableCreateCompanionBuilder,
inventario-Frontend/lib/core/database/app_database.g.dart:8582:    $$SaleItemsTableUpdateCompanionBuilder,
inventario-Frontend/lib/core/database/app_database.g.dart:8583:    (SaleItem, $$SaleItemsTableReferences),
inventario-Frontend/lib/core/database/app_database.g.dart:8584:    SaleItem,
inventario-Frontend/lib/core/database/app_database.g.dart:8585:    PrefetchHooks Function({bool saleId, bool productId})> {
inventario-Frontend/lib/core/database/app_database.g.dart:8586:  $$SaleItemsTableTableManager(_$AppDatabase db, $SaleItemsTable table)
inventario-Frontend/lib/core/database/app_database.g.dart:8590:          createFilteringComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:8591:              $$SaleItemsTableFilterComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:8592:          createOrderingComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:8593:              $$SaleItemsTableOrderingComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:8594:          createComputedFieldComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:8595:              $$SaleItemsTableAnnotationComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:8598:            Value<String?> saleId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:8599:            Value<String?> productId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:8607:              SaleItemsCompanion(
inventario-Frontend/lib/core/database/app_database.g.dart:8609:            saleId: saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:8610:            productId: productId,
inventario-Frontend/lib/core/database/app_database.g.dart:8620:            Value<String?> saleId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:8621:            Value<String?> productId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:8629:              SaleItemsCompanion.insert(
inventario-Frontend/lib/core/database/app_database.g.dart:8631:            saleId: saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:8632:            productId: productId,
inventario-Frontend/lib/core/database/app_database.g.dart:8643:                    $$SaleItemsTableReferences(db, table, e)
inventario-Frontend/lib/core/database/app_database.g.dart:8646:          prefetchHooksCallback: ({saleId = false, productId = false}) {
inventario-Frontend/lib/core/database/app_database.g.dart:8663:                if (saleId) {
inventario-Frontend/lib/core/database/app_database.g.dart:8666:                    currentColumn: table.saleId,
inventario-Frontend/lib/core/database/app_database.g.dart:8668:                        $$SaleItemsTableReferences._saleIdTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:8670:                        $$SaleItemsTableReferences._saleIdTable(db).id,
inventario-Frontend/lib/core/database/app_database.g.dart:8673:                if (productId) {
inventario-Frontend/lib/core/database/app_database.g.dart:8676:                    currentColumn: table.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:8678:                        $$SaleItemsTableReferences._productIdTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:8680:                        $$SaleItemsTableReferences._productIdTable(db).id,
inventario-Frontend/lib/core/database/app_database.g.dart:8694:typedef $$SaleItemsTableProcessedTableManager = ProcessedTableManager<
inventario-Frontend/lib/core/database/app_database.g.dart:8696:    $SaleItemsTable,
inventario-Frontend/lib/core/database/app_database.g.dart:8697:    SaleItem,
inventario-Frontend/lib/core/database/app_database.g.dart:8698:    $$SaleItemsTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8699:    $$SaleItemsTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8700:    $$SaleItemsTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8701:    $$SaleItemsTableCreateCompanionBuilder,
inventario-Frontend/lib/core/database/app_database.g.dart:8702:    $$SaleItemsTableUpdateCompanionBuilder,
inventario-Frontend/lib/core/database/app_database.g.dart:8703:    (SaleItem, $$SaleItemsTableReferences),
inventario-Frontend/lib/core/database/app_database.g.dart:8704:    SaleItem,
inventario-Frontend/lib/core/database/app_database.g.dart:8705:    PrefetchHooks Function({bool saleId, bool productId})>;
inventario-Frontend/lib/core/database/app_database.g.dart:8788:class $$PurchasesTableFilterComposer
inventario-Frontend/lib/core/database/app_database.g.dart:8789:    extends Composer<_$AppDatabase, $PurchasesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:8790:  $$PurchasesTableFilterComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:8794:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8795:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8797:  ColumnFilters<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8800:  ColumnFilters<String> get supplierId => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8803:  ColumnFilters<double> get total => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8806:  ColumnFilters<String> get status => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8809:  ColumnFilters<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8812:  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8815:  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8818:  ColumnFilters<String> get invoicePhotoUrl => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8822:  ColumnFilters<String> get processingStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8826:  ColumnFilters<String> get supplierName => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8830:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8834:  $$BusinessesTableFilterComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:8835:    final $$BusinessesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8836:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8841:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8842:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8843:            $$BusinessesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8846:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8848:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8849:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8851:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8854:  $$ProfilesTableFilterComposer get userId {
inventario-Frontend/lib/core/database/app_database.g.dart:8855:    final $$ProfilesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8856:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8861:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8862:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8863:            $$ProfilesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8866:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8868:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8869:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8871:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8875:      Expression<bool> Function($$PurchaseItemsTableFilterComposer f) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:8876:    final $$PurchaseItemsTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8877:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8882:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8883:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8884:            $$PurchaseItemsTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8887:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8889:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8890:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8892:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:8896:class $$PurchasesTableOrderingComposer
inventario-Frontend/lib/core/database/app_database.g.dart:8897:    extends Composer<_$AppDatabase, $PurchasesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:8898:  $$PurchasesTableOrderingComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:8902:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8903:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8905:  ColumnOrderings<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8908:  ColumnOrderings<String> get supplierId => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8911:  ColumnOrderings<double> get total => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8914:  ColumnOrderings<String> get status => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8917:  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8920:  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8923:  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8926:  ColumnOrderings<String> get invoicePhotoUrl => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8930:  ColumnOrderings<String> get processingStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8934:  ColumnOrderings<String> get supplierName => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8938:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8941:  $$BusinessesTableOrderingComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:8942:    final $$BusinessesTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8943:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8948:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8949:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8950:            $$BusinessesTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8953:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8955:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8956:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8958:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8961:  $$ProfilesTableOrderingComposer get userId {
inventario-Frontend/lib/core/database/app_database.g.dart:8962:    final $$ProfilesTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8963:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:8968:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8969:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:8970:            $$ProfilesTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:8973:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8975:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:8976:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8978:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:8982:class $$PurchasesTableAnnotationComposer
inventario-Frontend/lib/core/database/app_database.g.dart:8983:    extends Composer<_$AppDatabase, $PurchasesTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:8984:  $$PurchasesTableAnnotationComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:8988:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8989:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:8992:      $composableBuilder(column: $table.id, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:8994:  GeneratedColumn<String> get supplierId => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:8998:      $composableBuilder(column: $table.total, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:9001:      $composableBuilder(column: $table.status, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:9004:      $composableBuilder(column: $table.createdAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:9007:      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:9010:      $composableBuilder(column: $table.deletedAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:9012:  GeneratedColumn<String> get invoicePhotoUrl => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9015:  GeneratedColumn<String> get processingStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9018:  GeneratedColumn<String> get supplierName => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9022:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9025:  $$BusinessesTableAnnotationComposer get businessId {
inventario-Frontend/lib/core/database/app_database.g.dart:9026:    final $$BusinessesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9027:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:9032:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9033:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:9034:            $$BusinessesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:9037:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9039:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:9040:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9042:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:9045:  $$ProfilesTableAnnotationComposer get userId {
inventario-Frontend/lib/core/database/app_database.g.dart:9046:    final $$ProfilesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9047:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:9052:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9053:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:9054:            $$ProfilesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:9057:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9059:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:9060:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9062:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:9066:      Expression<T> Function($$PurchaseItemsTableAnnotationComposer a) f) {
inventario-Frontend/lib/core/database/app_database.g.dart:9067:    final $$PurchaseItemsTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9068:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:9073:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9074:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:9075:            $$PurchaseItemsTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:9078:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9080:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:9081:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9083:    return f(composer);
inventario-Frontend/lib/core/database/app_database.g.dart:9091:    $$PurchasesTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9092:    $$PurchasesTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9093:    $$PurchasesTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9104:          createFilteringComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:9105:              $$PurchasesTableFilterComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:9106:          createOrderingComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:9107:              $$PurchasesTableOrderingComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:9108:          createComputedFieldComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:9109:              $$PurchasesTableAnnotationComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:9249:    $$PurchasesTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9250:    $$PurchasesTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9251:    $$PurchasesTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9262:  Value<String?> productId,
inventario-Frontend/lib/core/database/app_database.g.dart:9274:  Value<String?> productId,
inventario-Frontend/lib/core/database/app_database.g.dart:9303:  static $ProductsTable _productIdTable(_$AppDatabase db) =>
inventario-Frontend/lib/core/database/app_database.g.dart:9304:      db.products.createAlias(
inventario-Frontend/lib/core/database/app_database.g.dart:9305:          $_aliasNameGenerator(db.purchaseItems.productId, db.products.id));
inventario-Frontend/lib/core/database/app_database.g.dart:9307:  $$ProductsTableProcessedTableManager? get productId {
inventario-Frontend/lib/core/database/app_database.g.dart:9308:    final $_column = $_itemColumn<String>('product_id');
inventario-Frontend/lib/core/database/app_database.g.dart:9310:    final manager = $$ProductsTableTableManager($_db, $_db.products)
inventario-Frontend/lib/core/database/app_database.g.dart:9312:    final item = $_typedResult.readTableOrNull(_productIdTable($_db));
inventario-Frontend/lib/core/database/app_database.g.dart:9319:class $$PurchaseItemsTableFilterComposer
inventario-Frontend/lib/core/database/app_database.g.dart:9320:    extends Composer<_$AppDatabase, $PurchaseItemsTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:9321:  $$PurchaseItemsTableFilterComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:9325:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9326:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9328:  ColumnFilters<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9331:  ColumnFilters<int> get quantity => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9334:  ColumnFilters<double> get unitCost => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9337:  ColumnFilters<double> get subtotal => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9340:  ColumnFilters<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9344:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9348:  $$PurchasesTableFilterComposer get purchaseId {
inventario-Frontend/lib/core/database/app_database.g.dart:9349:    final $$PurchasesTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9350:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:9355:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9356:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:9357:            $$PurchasesTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:9360:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9362:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:9363:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9365:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:9368:  $$ProductsTableFilterComposer get productId {
inventario-Frontend/lib/core/database/app_database.g.dart:9369:    final $$ProductsTableFilterComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9370:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:9371:        getCurrentColumn: (t) => t.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:9372:        referencedTable: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:9375:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9376:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:9377:            $$ProductsTableFilterComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:9379:              $table: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:9380:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9382:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:9383:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9385:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:9389:class $$PurchaseItemsTableOrderingComposer
inventario-Frontend/lib/core/database/app_database.g.dart:9390:    extends Composer<_$AppDatabase, $PurchaseItemsTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:9391:  $$PurchaseItemsTableOrderingComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:9395:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9396:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9398:  ColumnOrderings<String> get id => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9401:  ColumnOrderings<int> get quantity => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9404:  ColumnOrderings<double> get unitCost => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9407:  ColumnOrderings<double> get subtotal => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9410:  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9413:  ColumnOrderings<int> get syncStatus => $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9416:  $$PurchasesTableOrderingComposer get purchaseId {
inventario-Frontend/lib/core/database/app_database.g.dart:9417:    final $$PurchasesTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9418:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:9423:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9424:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:9425:            $$PurchasesTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:9428:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9430:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:9431:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9433:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:9436:  $$ProductsTableOrderingComposer get productId {
inventario-Frontend/lib/core/database/app_database.g.dart:9437:    final $$ProductsTableOrderingComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9438:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:9439:        getCurrentColumn: (t) => t.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:9440:        referencedTable: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:9443:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9444:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:9445:            $$ProductsTableOrderingComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:9447:              $table: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:9448:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9450:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:9451:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9453:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:9457:class $$PurchaseItemsTableAnnotationComposer
inventario-Frontend/lib/core/database/app_database.g.dart:9458:    extends Composer<_$AppDatabase, $PurchaseItemsTable> {
inventario-Frontend/lib/core/database/app_database.g.dart:9459:  $$PurchaseItemsTableAnnotationComposer({
inventario-Frontend/lib/core/database/app_database.g.dart:9463:    super.$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9464:    super.$removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9467:      $composableBuilder(column: $table.id, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:9470:      $composableBuilder(column: $table.quantity, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:9473:      $composableBuilder(column: $table.unitCost, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:9476:      $composableBuilder(column: $table.subtotal, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:9479:      $composableBuilder(column: $table.createdAt, builder: (column) => column);
inventario-Frontend/lib/core/database/app_database.g.dart:9482:      $composableBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9485:  $$PurchasesTableAnnotationComposer get purchaseId {
inventario-Frontend/lib/core/database/app_database.g.dart:9486:    final $$PurchasesTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9487:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:9492:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9493:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:9494:            $$PurchasesTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:9497:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9499:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:9500:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9502:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:9505:  $$ProductsTableAnnotationComposer get productId {
inventario-Frontend/lib/core/database/app_database.g.dart:9506:    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
inventario-Frontend/lib/core/database/app_database.g.dart:9507:        composer: this,
inventario-Frontend/lib/core/database/app_database.g.dart:9508:        getCurrentColumn: (t) => t.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:9509:        referencedTable: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:9512:                {$addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9513:                $removeJoinBuilderFromRootComposer}) =>
inventario-Frontend/lib/core/database/app_database.g.dart:9514:            $$ProductsTableAnnotationComposer(
inventario-Frontend/lib/core/database/app_database.g.dart:9516:              $table: $db.products,
inventario-Frontend/lib/core/database/app_database.g.dart:9517:              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9519:              $removeJoinBuilderFromRootComposer:
inventario-Frontend/lib/core/database/app_database.g.dart:9520:                  $removeJoinBuilderFromRootComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9522:    return composer;
inventario-Frontend/lib/core/database/app_database.g.dart:9530:    $$PurchaseItemsTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9531:    $$PurchaseItemsTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9532:    $$PurchaseItemsTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9537:    PrefetchHooks Function({bool purchaseId, bool productId})> {
inventario-Frontend/lib/core/database/app_database.g.dart:9542:          createFilteringComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:9543:              $$PurchaseItemsTableFilterComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:9544:          createOrderingComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:9545:              $$PurchaseItemsTableOrderingComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:9546:          createComputedFieldComposer: () =>
inventario-Frontend/lib/core/database/app_database.g.dart:9547:              $$PurchaseItemsTableAnnotationComposer($db: db, $table: table),
inventario-Frontend/lib/core/database/app_database.g.dart:9551:            Value<String?> productId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:9562:            productId: productId,
inventario-Frontend/lib/core/database/app_database.g.dart:9573:            Value<String?> productId = const Value.absent(),
inventario-Frontend/lib/core/database/app_database.g.dart:9584:            productId: productId,
inventario-Frontend/lib/core/database/app_database.g.dart:9598:          prefetchHooksCallback: ({purchaseId = false, productId = false}) {
inventario-Frontend/lib/core/database/app_database.g.dart:9625:                if (productId) {
inventario-Frontend/lib/core/database/app_database.g.dart:9628:                    currentColumn: table.productId,
inventario-Frontend/lib/core/database/app_database.g.dart:9630:                        $$PurchaseItemsTableReferences._productIdTable(db),
inventario-Frontend/lib/core/database/app_database.g.dart:9632:                        $$PurchaseItemsTableReferences._productIdTable(db).id,
inventario-Frontend/lib/core/database/app_database.g.dart:9650:    $$PurchaseItemsTableFilterComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9651:    $$PurchaseItemsTableOrderingComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9652:    $$PurchaseItemsTableAnnotationComposer,
inventario-Frontend/lib/core/database/app_database.g.dart:9657:    PrefetchHooks Function({bool purchaseId, bool productId})>;
inventario-Frontend/lib/core/database/app_database.g.dart:9670:  $$ProductsTableTableManager get products =>
inventario-Frontend/lib/core/database/app_database.g.dart:9671:      $$ProductsTableTableManager(_db, _db.products);
inventario-Frontend/lib/core/database/app_database.g.dart:9672:  $$SalesTableTableManager get sales =>
inventario-Frontend/lib/core/database/app_database.g.dart:9673:      $$SalesTableTableManager(_db, _db.sales);
inventario-Frontend/lib/core/database/app_database.g.dart:9674:  $$SaleItemsTableTableManager get saleItems =>
inventario-Frontend/lib/core/database/app_database.g.dart:9675:      $$SaleItemsTableTableManager(_db, _db.saleItems);
inventario-Frontend/lib/core/database/app_database.g.dart:9739:mixin _$ProductDaoMixin on DatabaseAccessor<AppDatabase> {
inventario-Frontend/lib/core/database/app_database.g.dart:9742:  $ProductsTable get products => attachedDatabase.products;
inventario-Frontend/lib/core/database/app_database.g.dart:9743:  ProductDaoManager get managers => ProductDaoManager(this);
inventario-Frontend/lib/core/database/app_database.g.dart:9746:class ProductDaoManager {
inventario-Frontend/lib/core/database/app_database.g.dart:9747:  final _$ProductDaoMixin _db;
inventario-Frontend/lib/core/database/app_database.g.dart:9748:  ProductDaoManager(this._db);
inventario-Frontend/lib/core/database/app_database.g.dart:9753:  $$ProductsTableTableManager get products =>
inventario-Frontend/lib/core/database/app_database.g.dart:9754:      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
inventario-Frontend/lib/core/database/app_database.g.dart:9757:mixin _$SaleDaoMixin on DatabaseAccessor<AppDatabase> {
inventario-Frontend/lib/core/database/app_database.g.dart:9761:  $SalesTable get sales => attachedDatabase.sales;
inventario-Frontend/lib/core/database/app_database.g.dart:9763:  $ProductsTable get products => attachedDatabase.products;
inventario-Frontend/lib/core/database/app_database.g.dart:9764:  $SaleItemsTable get saleItems => attachedDatabase.saleItems;
inventario-Frontend/lib/core/database/app_database.g.dart:9765:  SaleDaoManager get managers => SaleDaoManager(this);
inventario-Frontend/lib/core/database/app_database.g.dart:9768:class SaleDaoManager {
inventario-Frontend/lib/core/database/app_database.g.dart:9769:  final _$SaleDaoMixin _db;
inventario-Frontend/lib/core/database/app_database.g.dart:9770:  SaleDaoManager(this._db);
inventario-Frontend/lib/core/database/app_database.g.dart:9777:  $$SalesTableTableManager get sales =>
inventario-Frontend/lib/core/database/app_database.g.dart:9778:      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
inventario-Frontend/lib/core/database/app_database.g.dart:9781:  $$ProductsTableTableManager get products =>
inventario-Frontend/lib/core/database/app_database.g.dart:9782:      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
inventario-Frontend/lib/core/database/app_database.g.dart:9783:  $$SaleItemsTableTableManager get saleItems =>
inventario-Frontend/lib/core/database/app_database.g.dart:9784:      $$SaleItemsTableTableManager(_db.attachedDatabase, _db.saleItems);
inventario-Frontend/lib/core/database/app_database.g.dart:9792:  $ProductsTable get products => attachedDatabase.products;
inventario-Frontend/lib/core/database/app_database.g.dart:9808:  $$ProductsTableTableManager get products =>
inventario-Frontend/lib/core/database/app_database.g.dart:9809:      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
inventario-Frontend/lib/features/auth/data/datasources/business_dao.dart:1:part of 'package:inventario_frontend/core/database/app_database.dart';
inventario-Frontend/lib/features/auth/data/datasources/profile_dao.dart:1:part of 'package:inventario_frontend/core/database/app_database.dart';
inventario-Frontend/lib/features/customers/data/datasources/customer_dao.dart:1:part of 'package:inventario_frontend/core/database/app_database.dart';
inventario-Frontend/lib/features/inventory/data/datasources/category_dao.dart:1:part of 'package:inventario_frontend/core/database/app_database.dart';
inventario-Frontend/lib/features/inventory/data/datasources/category_dao.dart:7:  // Transmitir las categorías activas a los formularios del inventario
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:1:part of 'package:inventario_frontend/core/database/app_database.dart';
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:3:@DriftAccessor(tables: [Products, Categories])
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:4:class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:5:  ProductDao(AppDatabase db) : super(db);
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:9:  // Obtener todos los productos activos de un negocio
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:10:  Stream<List<Product>> watchActiveProducts(String businessId) {
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:11:    return (select(products)
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:18:  // Buscar productos por nombre o código de barras (POS/Inventario)
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:19:  Future<List<Product>> searchProducts(String businessId, String query) async {
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:20:    return (select(products)
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:23:          ..where((t) => t.name.like('%$query%') | t.barcode.like('%$query%')))
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:28:  Future<void> saveProductLocal(Product companion) async {
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:29:    await into(products).insertOnConflictUpdate(companion);
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:33:  Future<void> softDeleteProduct(String id) async {
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:34:    await (update(products)..where((t) => t.id.equals(id))).write(
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:35:      ProductsCompanion(
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:46:  Future<List<Product>> getPendingSyncProducts(String businessId) {
inventario-Frontend/lib/features/inventory/data/datasources/product_dao.dart:47:    return (select(products)
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:1:part of 'package:inventario_frontend/core/database/app_database.dart';
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:3:@DriftAccessor(tables: [Purchases, PurchaseItems, Products])
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:30:      // 2. Insertar cada ítem e incrementar el stock local del producto
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:34:        // Buscar producto local para actualizar existencias y costos
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:35:        final product = await (select(products)..where((t) => t.id.equals(item.productId!))).getSingle();
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:36:        final newStock = product.stockQuantity + item.quantity;
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:38:        await (update(products)..where((t) => t.id.equals(product.id))).write(
inventario-Frontend/lib/features/inventory/data/datasources/purchase_dao.dart:39:          ProductsCompanion(
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:1:part of 'package:inventario_frontend/core/database/app_database.dart';
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:3:@DriftAccessor(tables: [Sales, SaleItems, Products])
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:4:class SaleDao extends DatabaseAccessor<AppDatabase> with _$SaleDaoMixin {
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:5:  SaleDao(AppDatabase db) : super(db);
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:7:  // Ver historial de ventas en tiempo real
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:8:  Stream<List<Sale>> watchSalesHistory(String businessId) {
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:9:    return (select(sales)
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:16:  // Obtener los artículos específicos de una venta seleccionada
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:17:  Future<List<SaleItem>> getItemsBySaleId(String saleId) {
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:18:    return (select(saleItems)..where((t) => t.saleId.equals(saleId))).get();
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:22:  Future<void> insertCompleteSale({
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:23:    required Sale saleRecord,
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:24:    required List<SaleItem> itemsList,
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:27:      // 1. Guardar cabecera de la venta
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:28:      await into(sales).insert(saleRecord);
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:30:      // 2. Procesar ítems e impactar inventario
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:32:        await into(saleItems).insert(item);
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:34:        // Descontar inventario local inmediatamente para dar feedback ágil a la UI
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:35:        final product = await (select(products)..where((t) => t.id.equals(item.productId!))).getSingle();
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:36:        final newStock = product.stockQuantity - item.quantity;
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:38:        await (update(products)..where((t) => t.id.equals(product.id))).write(
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:39:          ProductsCompanion(
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:49:  // Sync Engine: Obtener ventas pendientes de subir a la nube
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:50:  Future<List<Sale>> getPendingSyncSales(String businessId) {
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:51:    return (select(sales)
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:57:  // Sync Engine: Obtener ítems de venta pendientes vinculados a esas ventas
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:58:  Future<List<SaleItem>> getPendingSyncSaleItems(List<String> pendingSaleIds) {
inventario-Frontend/lib/features/sales/data/datasources/sale_dao.dart:59:    return (select(saleItems)..where((t) => t.saleId.isIn(pendingSaleIds))).get();
inventario-Frontend/lib/main.dart:10:  const appName = String.fromEnvironment('APP_NAME', defaultValue: 'Inventario Base');

