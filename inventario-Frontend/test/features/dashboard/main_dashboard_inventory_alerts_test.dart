import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/core/providers/device_provider.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_models.dart';
import 'package:inventario_frontend/features/auth/application/authenticated_access_providers.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_provider.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_service.dart';
import 'package:inventario_frontend/features/cash/data/datasources/cash_session_local_dao.dart';
import 'package:inventario_frontend/features/dashboard/presentation/screens/main_dashboard_screen.dart';
import 'package:inventario_frontend/features/inventory/application/product_stock_balance_providers.dart';
import 'package:inventario_frontend/features/inventory/presentation/screens/inventory_product_stock_list_screen.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';
import 'package:inventario_frontend/features/sync/application/app_current_context_provider.dart';

void main() {
  testWidgets(
      'shows branch-scoped local inventory alert counts when authorized',
      (tester) async {
    final observedKeys = <InventoryAlertSummaryKey>[];

    await _pumpDashboard(
      tester,
      permissions: const {'inventory.read'},
      onSummaryRead: observedKeys.add,
    );

    expect(find.text('Atención de inventario'), findsOneWidget);
    expect(find.text('Agotados: 3'), findsOneWidget);
    expect(find.text('Bajo stock: 4'), findsOneWidget);
    expect(observedKeys, isNotEmpty);
    expect(observedKeys.last.businessId, 'business-1');
    expect(observedKeys.last.branchId, 'branch-1');
  });

  testWidgets('does not expose inventory counts without inventory.read',
      (tester) async {
    var summaryRead = false;

    await _pumpDashboard(
      tester,
      permissions: const {},
      onSummaryRead: (_) => summaryRead = true,
    );

    expect(find.text('Atención de inventario'), findsNothing);
    expect(find.text('Agotados: 3'), findsNothing);
    expect(summaryRead, isFalse);
  });

  testWidgets('refreshing an operational branch replaces the alert summary',
      (tester) async {
    var branchId = 'branch-a';

    await _pumpDashboard(
      tester,
      permissions: const {'inventory.read'},
      currentBranchId: () => branchId,
      summaryForKey: (key) => key.branchId == 'branch-a'
          ? const InventoryAlertSummary(
              outOfStockCount: 1,
              lowStockCount: 2,
            )
          : const InventoryAlertSummary(
              outOfStockCount: 3,
              lowStockCount: 4,
            ),
    );

    expect(find.text('Agotados: 1'), findsOneWidget);
    expect(find.text('Bajo stock: 2'), findsOneWidget);

    branchId = 'branch-b';
    await tester.tap(find.byTooltip('Actualizar'));
    await tester.pumpAndSettle();

    expect(find.text('Agotados: 3'), findsOneWidget);
    expect(find.text('Bajo stock: 4'), findsOneWidget);
    expect(find.text('Agotados: 1'), findsNothing);
  });

  testWidgets('alert actions open Inventory with the corresponding filter',
      (tester) async {
    final inventoryKeys = <ProductsWithLocalStockKey>[];

    await _pumpDashboard(
      tester,
      permissions: const {'inventory.read'},
      onInventoryRead: inventoryKeys.add,
    );

    final outOfStockAction = find.byKey(
      const Key('inventory-alerts-out-of-stock'),
    );
    await tester.ensureVisible(outOfStockAction);
    await tester.tap(outOfStockAction);
    await tester.pumpAndSettle();

    expect(find.byType(InventoryProductStockListScreen), findsOneWidget);
    expect(
        inventoryKeys.last.stockFilter, InventoryProductStockFilter.outOfStock);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const Key('inventory-filter-out-of-stock')),
          )
          .selected,
      isTrue,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();

    final lowStockAction = find.byKey(
      const Key('inventory-alerts-low-stock'),
    );
    await tester.ensureVisible(lowStockAction);
    await tester.tap(lowStockAction);
    await tester.pumpAndSettle();

    expect(find.byType(InventoryProductStockListScreen), findsOneWidget);
    expect(
        inventoryKeys.last.stockFilter, InventoryProductStockFilter.lowStock);
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const Key('inventory-filter-low-stock')),
          )
          .selected,
      isTrue,
    );
  });
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required Set<String> permissions,
  void Function(InventoryAlertSummaryKey key)? onSummaryRead,
  void Function(ProductsWithLocalStockKey key)? onInventoryRead,
  String Function()? currentBranchId,
  InventoryAlertSummary Function(InventoryAlertSummaryKey key)? summaryForKey,
}) async {
  final database = AppDatabase.executor(NativeDatabase.memory());
  addTearDown(database.close);
  final cashService = CashSessionLocalService(
    dao: CashSessionLocalDao(database),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        installationIdProvider.overrideWith((ref) async => 'installation-1'),
        appCurrentContextProvider.overrideWith((ref, request) async {
          return AppCurrentContext(
            businessId: 'business-1',
            branchId: currentBranchId?.call() ?? 'branch-1',
            profileId: 'profile-1',
            installationId: request.installationId,
            appDeviceId: 'device-1',
            isOnline: false,
            permissions: AppPermissionSet.fromIterable(permissions),
            authorizationContextReady: true,
          );
        }),
        cashSessionLocalServiceProvider.overrideWithValue(cashService),
        authenticatedAccessResolverProvider.overrideWith((ref, profileId) {
          return Future.value(
            const AuthenticatedAccessResult(
              outcome: AuthenticatedAccessOutcome.noAuthorizedAccess,
              contexts: [],
              pendingInvitations: [],
              message: 'Sin contextos adicionales para el test.',
            ),
          );
        }),
        inventoryAlertSummaryProvider.overrideWith((ref, key) {
          onSummaryRead?.call(key);
          return Stream.value(
            summaryForKey?.call(key) ??
                const InventoryAlertSummary(
                  outOfStockCount: 3,
                  lowStockCount: 4,
                ),
          );
        }),
        localProductsWithStockProvider.overrideWith((ref, key) {
          onInventoryRead?.call(key);
          return Stream.value(const <Map<String, dynamic>>[]);
        }),
      ],
      child: const MaterialApp(home: MainDashboardScreen()),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}
