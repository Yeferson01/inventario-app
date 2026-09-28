import 'dart:async';

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
import 'package:inventario_frontend/features/inventory/application/inventory_valuation_models.dart';
import 'package:inventario_frontend/features/inventory/application/product_stock_balance_providers.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_history_providers.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_history_service.dart';
import 'package:inventario_frontend/features/inventory/data/models/inventory_history_models.dart';
import 'package:inventario_frontend/features/inventory/presentation/screens/inventory_movements_screen.dart';
import 'package:inventario_frontend/features/inventory/presentation/screens/inventory_product_stock_list_screen.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_providers.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_service.dart';
import 'package:inventario_frontend/features/reports/application/cash_flow_report_providers.dart';
import 'package:inventario_frontend/features/reports/application/cash_flow_report_service.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';
import 'package:inventario_frontend/features/reports/presentation/screens/sales_report_screen.dart';
import 'package:inventario_frontend/features/reports/presentation/screens/cash_flow_report_screen.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';
import 'package:inventario_frontend/features/sync/application/app_current_context_provider.dart';
import 'package:inventario_frontend/features/sync/application/app_router_sync_bootstrap_provider.dart';
import 'package:inventario_frontend/features/sync/application/productive_manual_sync_service.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status_provider.dart';

void main() {
  testWidgets('shows Reports only with reports.sales', (tester) async {
    await _pumpDashboard(
      tester,
      permissions: const {'reports.sales'},
    );

    expect(find.text('Reportes'), findsOneWidget);
  });

  testWidgets('sales.read alone does not expose Reports', (tester) async {
    await _pumpDashboard(
      tester,
      permissions: const {'sales.read'},
    );

    expect(find.text('Reportes'), findsNothing);
  });

  testWidgets('Reports module opens SalesReportScreen', (tester) async {
    await _pumpDashboard(
      tester,
      permissions: const {'reports.sales'},
    );

    final reports = find.text('Reportes');
    await tester.ensureVisible(reports);
    await tester.tap(reports);
    await tester.pumpAndSettle();

    expect(find.byType(SalesReportScreen), findsOneWidget);
    expect(find.text('Reporte no disponible sin conexión'), findsOneWidget);
  });

  testWidgets('reports.cash alone opens cash-flow report, not sales',
      (tester) async {
    await _pumpDashboard(tester, permissions: const {'reports.cash'});
    final reports = find.text('Reportes');
    await tester.ensureVisible(reports);
    await tester.tap(reports);
    await tester.pumpAndSettle();
    expect(find.byType(CashFlowReportScreen), findsOneWidget);
    expect(find.byType(SalesReportScreen), findsNothing);
  });

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

  testWidgets('manual sync is explicit and prevents a concurrent second run',
      (tester) async {
    final completer = Completer<ProductiveManualSyncResult>();
    var calls = 0;

    await _pumpDashboard(
      tester,
      permissions: const {'inventory.read'},
      manualSyncRunner: () {
        calls++;
        return completer.future;
      },
    );

    final action = find.text('Sincronizar ahora');
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pump();
    await tester.ensureVisible(action);
    await tester.pumpAndSettle();
    await tester.tap(action);
    await tester.pump();

    expect(calls, 1);
    expect(find.text('Sincronizando...'), findsOneWidget);

    completer.complete(
      const ProductiveManualSyncResult(
        outcome: ProductiveManualSyncOutcome.completed,
        message: 'Todo al día.',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Todo al día.'), findsOneWidget);
  });

  testWidgets('Actualizar keeps its reload-only contract', (tester) async {
    var manualSyncCalls = 0;

    await _pumpDashboard(
      tester,
      permissions: const {'inventory.read'},
      manualSyncRunner: () async {
        manualSyncCalls++;
        return const ProductiveManualSyncResult(
          outcome: ProductiveManualSyncOutcome.completed,
          message: 'Completada.',
        );
      },
    );

    await tester.tap(find.byTooltip('Actualizar'));
    await tester.pumpAndSettle();

    expect(manualSyncCalls, 0);
  });

  testWidgets('shows an honest all-up-to-date sync action', (tester) async {
    await _pumpDashboard(
      tester,
      permissions: const {'inventory.read'},
    );

    expect(find.text('Sincronizar ahora'), findsOneWidget);
    expect(find.text('Todo al día'), findsOneWidget);
    expect(find.text('Todos tus cambios están al día.'), findsOneWidget);
  });

  testWidgets(
      'shows local pending operations without technical mutation counts',
      (tester) async {
    await _pumpDashboard(
      tester,
      permissions: const {'inventory.read'},
      productiveSyncStatus: _status(
        pendingSales: 2,
        pendingPurchases: 1,
      ),
    );

    expect(find.text('3 pendientes'), findsOneWidget);
    expect(find.textContaining('2 ventas pendientes'), findsOneWidget);
    expect(find.textContaining('1 compra pendiente'), findsOneWidget);
    expect(find.textContaining('mutations'), findsNothing);
    expect(find.textContaining('batches'), findsNothing);
  });

  testWidgets('offline pending uses productive copy', (tester) async {
    await _pumpDashboard(
      tester,
      permissions: const {'inventory.read'},
      productiveSyncStatus: _status(
        connectivity: ProductiveSyncConnectivity.offline,
        pendingSales: 1,
      ),
    );

    expect(find.text('Sin conexión'), findsOneWidget);
    expect(
      find.textContaining(
        'Tus cambios están guardados en este dispositivo.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('attention uses productive copy', (tester) async {
    await _pumpDashboard(
      tester,
      permissions: const {'inventory.read'},
      productiveSyncStatus: _status(openIssueCount: 1),
    );

    expect(find.text('Necesita atención'), findsOneWidget);
    expect(
      find.text('Algunos cambios necesitan revisión.'),
      findsOneWidget,
    );
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

  testWidgets('opens inventory movement history from dashboard',
      (tester) async {
    await _pumpDashboard(
      tester,
      permissions: const {'inventory.read'},
    );

    final movementsAction = find.text('Movimientos');
    await tester.ensureVisible(movementsAction);
    await tester.pumpAndSettle();

    await tester.tap(movementsAction);
    await tester.pumpAndSettle();

    expect(find.byType(InventoryMovementsScreen), findsOneWidget);

    final screen = tester.widget<InventoryMovementsScreen>(
      find.byType(InventoryMovementsScreen),
    );

    expect(screen.appContext.businessId, 'business-1');
    expect(screen.appContext.branchId, 'branch-1');
    expect(screen.appContext.profileId, 'profile-1');
    expect(screen.branchName, 'Sucursal');
    expect(screen.productId, isNull);

    expect(find.text('Historial no disponible sin conexión'), findsNothing);
  });

  testWidgets(
    'opens product movement timeline from inventory through dashboard wiring',
    (tester) async {
      await _pumpDashboard(
        tester,
        permissions: const {'inventory.read'},
        inventoryProducts: const [
          {
            'product_id': 'product-1',
            'product_name': 'Arroz premium',
            'barcode': '7700000000001',
            'quantity_on_hand': 10,
            'quantity_available': 10,
            'stock_average_cost': 2.67,
            'minimum_stock': 3,
          },
        ],
      );

      final inventoryAction = find.text('Inventario');
      await tester.ensureVisible(inventoryAction);
      await tester.pumpAndSettle();

      await tester.tap(inventoryAction);
      await tester.pumpAndSettle();

      expect(
        find.byType(InventoryProductStockListScreen),
        findsOneWidget,
      );

      final productMovements = find.byKey(
        const Key('inventory-movements-product-1'),
      );

      await tester.ensureVisible(productMovements);
      await tester.pumpAndSettle();

      expect(productMovements, findsOneWidget);

      await tester.tap(productMovements);
      await tester.pumpAndSettle();

      expect(find.byType(InventoryMovementsScreen), findsOneWidget);

      final screen = tester.widget<InventoryMovementsScreen>(
        find.byType(InventoryMovementsScreen),
      );

      expect(screen.appContext.businessId, 'business-1');
      expect(screen.appContext.branchId, 'branch-1');
      expect(screen.appContext.profileId, 'profile-1');

      expect(screen.productId, 'product-1');
      expect(screen.productName, 'Arroz premium');
      expect(screen.productBarcode, '7700000000001');
      expect(screen.branchName, 'Sucursal');

      expect(find.text('Movimientos del producto'), findsOneWidget);
      expect(
        find.byKey(const Key('inventory-history-product-header')),
        findsOneWidget,
      );
      expect(find.text('Arroz premium'), findsWidgets);
    },
  );
}

Future<void> _pumpDashboard(
  WidgetTester tester, {
  required Set<String> permissions,
  void Function(InventoryAlertSummaryKey key)? onSummaryRead,
  void Function(ProductsWithLocalStockKey key)? onInventoryRead,
  String Function()? currentBranchId,
  InventoryAlertSummary Function(InventoryAlertSummaryKey key)? summaryForKey,
  ProductiveManualSyncRunner? manualSyncRunner,
  ProductiveSyncStatus? productiveSyncStatus,
  List<Map<String, dynamic>> inventoryProducts = const [],
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
        inventoryValuationSummaryProvider.overrideWith(
          (ref, key) => Stream.value(InventoryValuationSummary.empty),
        ),
        inventoryHistoryServiceProvider.overrideWithValue(
          const _DashboardInventoryHistoryService(),
        ),
        localProductsWithStockProvider.overrideWith((ref, key) {
          onInventoryRead?.call(key);
          return Stream.value(inventoryProducts);
        }),
        productiveManualSyncRunnerProvider.overrideWithValue(
          manualSyncRunner ??
              () async => const ProductiveManualSyncResult(
                    outcome: ProductiveManualSyncOutcome.completed,
                    message: 'Completada.',
                  ),
        ),
        productiveSyncStatusProvider.overrideWith((ref, request) async {
          return productiveSyncStatus ??
              ProductiveSyncStatus(
                scope: ProductiveSyncScope(
                  profileId: request.profileId,
                  businessId: request.businessId,
                  branchId: request.branchId,
                ),
                connectivity: ProductiveSyncConnectivity.online,
                isSyncing: request.isSyncing,
                pendingSales: 0,
                pendingPurchases: 0,
                pendingCashOperations: 0,
                pendingProductOperations: 0,
                pendingInventoryOperations: 0,
                openIssueCount: 0,
                attentionOperationCount: 0,
              );
        }),
        salesReportServiceProvider.overrideWithValue(
          const _DashboardSalesReportService(),
        ),
        cashFlowReportServiceProvider.overrideWithValue(
          const _DashboardCashFlowReportService(),
        ),
        salesReportOnlineCheckProvider.overrideWithValue(() async => false),
      ],
      child: const MaterialApp(home: MainDashboardScreen()),
    ),
  );
  await tester.pump();
  await tester.pumpAndSettle();
}

class _DashboardSalesReportService implements SalesReportService {
  const _DashboardSalesReportService();

  @override
  Future<SalesReportCacheReadResult> readCached(
    SalesReportScope scope,
  ) async {
    return const SalesReportCacheReadResult(
      outcome: SalesReportCacheReadOutcome.noCache,
    );
  }

  @override
  Future<SalesReportRefreshResult> refresh(SalesReportScope scope) async {
    return const SalesReportRefreshResult(
      outcome: SalesReportRefreshOutcome.remoteFailure,
    );
  }
}

class _DashboardCashFlowReportService implements CashFlowReportService {
  const _DashboardCashFlowReportService();

  @override
  Future<CashFlowCacheResult> readCached(SalesReportScope scope) async =>
      const CashFlowCacheResult(CashFlowCacheOutcome.noCache);

  @override
  Future<CashFlowRefreshResult> refresh(SalesReportScope scope) async =>
      const CashFlowRefreshResult(CashFlowRefreshOutcome.remoteFailure);
}

ProductiveSyncStatus _status({
  ProductiveSyncConnectivity connectivity = ProductiveSyncConnectivity.online,
  int pendingSales = 0,
  int pendingPurchases = 0,
  int pendingCashOperations = 0,
  int pendingProductOperations = 0,
  int pendingInventoryOperations = 0,
  int openIssueCount = 0,
  int attentionOperationCount = 0,
}) {
  return ProductiveSyncStatus(
    scope: const ProductiveSyncScope(
      profileId: 'profile-1',
      businessId: 'business-1',
      branchId: 'branch-1',
    ),
    connectivity: connectivity,
    isSyncing: false,
    pendingSales: pendingSales,
    pendingPurchases: pendingPurchases,
    pendingCashOperations: pendingCashOperations,
    pendingProductOperations: pendingProductOperations,
    pendingInventoryOperations: pendingInventoryOperations,
    openIssueCount: openIssueCount,
    attentionOperationCount: attentionOperationCount,
  );
}

class _DashboardInventoryHistoryService implements InventoryHistoryService {
  const _DashboardInventoryHistoryService();

  static const coverage = InventoryHistoryCoverage(
    hasCachedRows: false,
    hasMoreRemote: false,
  );

  @override
  Future<List<InventoryMovementHistoryEntry>> loadCachedHistory({
    required AppCurrentContext context,
    String? productId,
    String? effectiveType,
    DateTime? from,
    DateTime? to,
    InventoryHistoryCursor? cursor,
    int limit = 50,
  }) async {
    return const [];
  }

  @override
  Future<InventoryHistoryCoverage> getCoverage({
    required AppCurrentContext context,
  }) async {
    return coverage;
  }

  @override
  Future<InventoryHistoryHydrationResult> refreshLatest({
    required AppCurrentContext context,
    int limit = 50,
  }) async {
    return const InventoryHistoryHydrationResult(
      outcome: InventoryHistoryHydrationOutcome.hydrated,
      coverage: coverage,
    );
  }

  @override
  Future<InventoryHistoryHydrationResult> loadOlder({
    required AppCurrentContext context,
    int limit = 50,
  }) async {
    return const InventoryHistoryHydrationResult(
      outcome: InventoryHistoryHydrationOutcome.noMoreRemote,
      coverage: coverage,
    );
  }
}
