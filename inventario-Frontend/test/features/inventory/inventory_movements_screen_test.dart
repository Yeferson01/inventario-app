import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inventario_frontend/features/inventory/application/inventory_history_providers.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_history_service.dart';
import 'package:inventario_frontend/features/inventory/data/models/inventory_history_models.dart';
import 'package:inventario_frontend/features/inventory/presentation/screens/inventory_movements_screen.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';

void main() {
  group('InventoryMovementsScreen', () {
    testWidgets(
      'renders product, type, delta, stock and cost with permission',
      (tester) async {
        final service = _FakeInventoryHistoryService(
          rows: [
            _row(
              id: 'movement-1',
              effectiveType: 'purchase',
              quantityDelta: 2,
              previousStock: 10,
              newStock: 12,
              unitCost: 1234,
            ),
          ],
          coverage: _coverage(
            hasCachedRows: true,
            hasMoreRemote: false,
          ),
        );

        await _pumpScreen(
          tester,
          service: service,
          context: _context(),
        );

        expect(find.text('Producto de prueba'), findsOneWidget);
        expect(find.text('Compra'), findsOneWidget);
        expect(find.text('+2'), findsOneWidget);
        expect(find.text('Stock: 10 → 12'), findsOneWidget);
        expect(find.text('Costo: \$1234.00'), findsOneWidget);
      },
    );

    testWidgets(
      'does not render cost without inventory.view_costs even if row has one',
      (tester) async {
        final service = _FakeInventoryHistoryService(
          rows: [
            _row(
              id: 'movement-secret',
              unitCost: 9876,
            ),
          ],
          coverage: _coverage(
            hasCachedRows: true,
            hasMoreRemote: false,
          ),
        );

        await _pumpScreen(
          tester,
          service: service,
          context: _context(
            permissions: const {'inventory.read'},
          ),
        );

        expect(find.textContaining('Costo:'), findsNothing);
        expect(find.textContaining('9876'), findsNothing);
      },
    );

    testWidgets('WEIGHT sale movement labels grams, not units', (tester) async {
      final service = _FakeInventoryHistoryService(
        rows: [
          _row(
            id: 'weight-sale',
            effectiveType: 'sale',
            isWeight: true,
            quantityDelta: -735,
            previousStock: 13000,
            newStock: 12265,
          ),
        ],
        coverage: _coverage(hasCachedRows: true, hasMoreRemote: false),
      );
      await _pumpScreen(tester, service: service, context: _context());
      expect(find.text('-735 g'), findsOneWidget);
      expect(find.text('Stock: 13000 g → 12265 g'), findsOneWidget);
    });

    testWidgets(
      'distinguishes unknown cost from known zero cost',
      (tester) async {
        final service = _FakeInventoryHistoryService(
          rows: [
            _row(
              id: 'movement-unknown',
              productName: 'Costo desconocido',
              unitCost: null,
            ),
            _row(
              id: 'movement-zero',
              productName: 'Costo cero',
              unitCost: 0,
            ),
          ],
          coverage: _coverage(
            hasCachedRows: true,
            hasMoreRemote: false,
          ),
        );

        await _pumpScreen(
          tester,
          service: service,
          context: _context(),
        );

        expect(find.text('Costo: no disponible'), findsOneWidget);
        expect(find.text('Costo: \$0.00'), findsOneWidget);
      },
    );

    testWidgets(
      'shows cached rows and offline banner when refresh reports cachedOffline',
      (tester) async {
        final service = _FakeInventoryHistoryService(
          rows: [
            _row(id: 'movement-offline'),
          ],
          coverage: _coverage(
            hasCachedRows: true,
            hasMoreRemote: true,
          ),
          refreshOutcome: InventoryHistoryHydrationOutcome.cachedOffline,
        );

        await _pumpScreen(
          tester,
          service: service,
          context: _context(isOnline: false),
        );

        expect(
          find.byKey(const Key('inventory-history-offline-banner')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('inventory-history-row-movement-offline')),
            findsOneWidget);
        expect(
          find.text('Sin conexión · mostrando historial guardado.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'shows specific empty state when offline cache is empty',
      (tester) async {
        final service = _FakeInventoryHistoryService(
          rows: const [],
          coverage: _coverage(
            hasCachedRows: false,
            hasMoreRemote: true,
          ),
          refreshOutcome: InventoryHistoryHydrationOutcome.noCachedHistory,
        );

        await _pumpScreen(
          tester,
          service: service,
          context: _context(isOnline: false),
        );

        expect(
          find.byKey(const Key('inventory-history-empty')),
          findsOneWidget,
        );
        expect(
          find.text('Historial no disponible sin conexión'),
          findsOneWidget,
        );
        expect(
          find.text(
            'Conéctate para descargar el historial de esta sucursal.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'changing movement type filter reloads local data without remote older',
      (tester) async {
        String? lastEffectiveType;

        final service = _FakeInventoryHistoryService(
          rows: [
            _row(
              id: 'purchase-1',
              effectiveType: 'purchase',
            ),
          ],
          coverage: _coverage(
            hasCachedRows: true,
            hasMoreRemote: true,
          ),
        );

        service.onLoadCachedHistory = ({
          required context,
          productId,
          effectiveType,
          from,
          to,
          cursor,
          required limit,
        }) async {
          lastEffectiveType = effectiveType;

          if (effectiveType == 'sale') {
            return [
              _row(
                id: 'sale-1',
                effectiveType: 'sale',
                quantityDelta: -1,
              ),
            ];
          }

          return [
            _row(
              id: 'purchase-1',
              effectiveType: 'purchase',
            ),
          ];
        };

        await _pumpScreen(
          tester,
          service: service,
          context: _context(),
        );

        final loadOlderCallsBefore = service.loadOlderCalls;

        await tester.tap(
          find.byKey(const Key('inventory-history-type-filter')),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Ventas').last);
        await tester.pumpAndSettle();

        expect(lastEffectiveType, 'sale');
        expect(
          find.byKey(const Key('inventory-history-row-sale-1')),
          findsOneWidget,
        );
        expect(find.text('Venta'), findsOneWidget);
        expect(find.text('-1'), findsOneWidget);
        expect(service.loadOlderCalls, loadOlderCallsBefore);
      },
    );

    testWidgets(
      'load older hydrates and appends an older movement',
      (tester) async {
        var olderHydrated = false;

        final newest = _row(
          id: 'movement-new',
          occurredAt: DateTime.utc(2026, 9, 18, 12),
        );

        final older = _row(
          id: 'movement-old',
          occurredAt: DateTime.utc(2026, 9, 17, 12),
        );

        final service = _FakeInventoryHistoryService(
          rows: [newest],
          coverage: _coverage(
            hasCachedRows: true,
            hasMoreRemote: true,
          ),
        );

        service.onLoadCachedHistory = ({
          required context,
          productId,
          effectiveType,
          from,
          to,
          cursor,
          required limit,
        }) async {
          if (cursor == null) {
            return [newest];
          }

          return olderHydrated ? [older] : const [];
        };

        service.onLoadOlder = ({
          required context,
          required limit,
        }) async {
          olderHydrated = true;
          service.coverage = _coverage(
            hasCachedRows: true,
            hasMoreRemote: false,
          );

          return InventoryHistoryHydrationResult(
            outcome: InventoryHistoryHydrationOutcome.hydrated,
            coverage: service.coverage,
            rowsApplied: 1,
          );
        };

        await _pumpScreen(
          tester,
          service: service,
          context: _context(),
        );

        expect(
          find.byKey(const Key('inventory-history-load-older')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const Key('inventory-history-load-older')),
        );
        await tester.pumpAndSettle();

        expect(service.loadOlderCalls, 1);
        expect(
          find.byKey(const Key('inventory-history-row-movement-new')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('inventory-history-row-movement-old')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('inventory-history-end')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'bottom sheet hides cost without permission and identifies other device',
      (tester) async {
        final service = _FakeInventoryHistoryService(
          rows: [
            _row(
              id: 'movement-detail',
              unitCost: 7000,
              deviceId: 'device-other',
              previousStock: 5,
              newStock: 7,
            ),
          ],
          coverage: _coverage(
            hasCachedRows: true,
            hasMoreRemote: false,
          ),
        );

        await _pumpScreen(
          tester,
          service: service,
          context: _context(
            permissions: const {'inventory.read'},
          ),
        );

        await tester.tap(
          find.byKey(const Key('inventory-history-row-movement-detail')),
        );
        await tester.pumpAndSettle();

        expect(find.text('Otro dispositivo'), findsOneWidget);
        expect(find.text('Stock anterior'), findsOneWidget);
        expect(find.text('Stock resultante'), findsOneWidget);

        expect(find.text('Costo unitario'), findsNothing);
        expect(find.textContaining('7000'), findsNothing);
      },
    );

    testWidgets(
      'renders product timeline using the same screen and product scope',
      (tester) async {
        String? lastProductId;

        final service = _FakeInventoryHistoryService(
          rows: [
            _row(
              id: 'movement-product',
              productName: 'Arroz de prueba',
            ),
          ],
          coverage: _coverage(
            hasCachedRows: true,
            hasMoreRemote: false,
          ),
        );

        service.onLoadCachedHistory = ({
          required context,
          productId,
          effectiveType,
          from,
          to,
          cursor,
          required limit,
        }) async {
          lastProductId = productId;
          return service.rows;
        };

        await _pumpScreen(
          tester,
          service: service,
          context: _context(),
          productId: 'product-1',
          productName: 'Arroz de prueba',
        );

        expect(lastProductId, 'product-1');
        expect(find.text('Movimientos del producto'), findsOneWidget);
        expect(
          find.byKey(const Key('inventory-history-product-header')),
          findsOneWidget,
        );
        expect(find.text('Arroz de prueba'), findsWidgets);
        expect(
          find.text('Historial de movimientos del producto'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'access exception is rendered as fail-closed state',
      (tester) async {
        final service = _FakeInventoryHistoryService(
          rows: const [],
          coverage: _coverage(
            hasCachedRows: false,
            hasMoreRemote: false,
          ),
        );

        service.onLoadCachedHistory = ({
          required context,
          productId,
          effectiveType,
          from,
          to,
          cursor,
          required limit,
        }) {
          throw const InventoryHistoryAccessException(
            'inventory.read required',
          );
        };

        await _pumpScreen(
          tester,
          service: service,
          context: _context(
            permissions: const {},
          ),
        );

        expect(
          find.byKey(const Key('inventory-history-error')),
          findsOneWidget,
        );
        expect(
          find.text('No tienes acceso a movimientos'),
          findsOneWidget,
        );
        expect(find.text('Reintentar'), findsNothing);
      },
    );
  });
}

class _FakeInventoryHistoryService implements InventoryHistoryService {
  _FakeInventoryHistoryService({
    required this.rows,
    required this.coverage,
    this.refreshOutcome = InventoryHistoryHydrationOutcome.hydrated,
  });

  List<InventoryMovementHistoryEntry> rows;
  InventoryHistoryCoverage coverage;
  InventoryHistoryHydrationOutcome refreshOutcome;

  int refreshCalls = 0;
  int loadOlderCalls = 0;

  Future<List<InventoryMovementHistoryEntry>> Function({
    required AppCurrentContext context,
    String? productId,
    String? effectiveType,
    DateTime? from,
    DateTime? to,
    InventoryHistoryCursor? cursor,
    required int limit,
  })? onLoadCachedHistory;

  Future<InventoryHistoryHydrationResult> Function({
    required AppCurrentContext context,
    required int limit,
  })? onLoadOlder;

  @override
  Future<InventoryHistoryHydrationResult> refreshLatest({
    required AppCurrentContext context,
    int limit = 50,
  }) async {
    refreshCalls++;

    return InventoryHistoryHydrationResult(
      outcome: refreshOutcome,
      coverage: coverage,
      rowsApplied: refreshOutcome == InventoryHistoryHydrationOutcome.hydrated
          ? rows.length
          : 0,
    );
  }

  @override
  Future<InventoryHistoryHydrationResult> loadOlder({
    required AppCurrentContext context,
    int limit = 50,
  }) async {
    loadOlderCalls++;

    final callback = onLoadOlder;
    if (callback != null) {
      return callback(
        context: context,
        limit: limit,
      );
    }

    return InventoryHistoryHydrationResult(
      outcome: InventoryHistoryHydrationOutcome.noMoreRemote,
      coverage: coverage,
    );
  }

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
    final callback = onLoadCachedHistory;
    if (callback != null) {
      return callback(
        context: context,
        productId: productId,
        effectiveType: effectiveType,
        from: from,
        to: to,
        cursor: cursor,
        limit: limit,
      );
    }

    return rows;
  }

  @override
  Future<InventoryHistoryCoverage> getCoverage({
    required AppCurrentContext context,
  }) async {
    return coverage;
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeInventoryHistoryService service,
  required AppCurrentContext context,
  String? productId,
  String? productName,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        inventoryHistoryServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        home: InventoryMovementsScreen(
          appContext: context,
          branchName: 'Sucursal Principal',
          productId: productId,
          productName: productName,
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

AppCurrentContext _context({
  String profileId = 'profile-1',
  String businessId = 'business-1',
  String branchId = 'branch-1',
  bool isOnline = true,
  Set<String> permissions = const {
    'inventory.read',
    'inventory.view_costs',
  },
}) {
  return AppCurrentContext(
    businessId: businessId,
    branchId: branchId,
    profileId: profileId,
    installationId: 'installation-1',
    appDeviceId: 'device-1',
    isOnline: isOnline,
    permissions: AppPermissionSet.fromIterable(permissions),
    applicableMembershipIds: const ['membership-1'],
    authorizationContextReady: true,
    authorizationValidatedAt: DateTime.utc(2026, 9, 18, 12),
  );
}

InventoryHistoryCoverage _coverage({
  required bool hasCachedRows,
  required bool hasMoreRemote,
}) {
  return InventoryHistoryCoverage(
    hasCachedRows: hasCachedRows,
    hasMoreRemote: hasMoreRemote,
    oldestCursor: hasCachedRows
        ? InventoryHistoryCursor(
            occurredAt: DateTime.utc(2026, 9, 17, 12),
            id: 'oldest',
          )
        : null,
    lastRefreshedAt: DateTime.utc(2026, 9, 18, 12),
  );
}

InventoryMovementHistoryEntry _row({
  required String id,
  bool isWeight = false,
  DateTime? occurredAt,
  String effectiveType = 'purchase',
  String productName = 'Producto de prueba',
  int quantityDelta = 1,
  int? previousStock,
  int? newStock,
  double? unitCost = 1000,
  String? deviceId,
}) {
  return InventoryMovementHistoryEntry(
    id: id,
    businessId: 'business-1',
    branchId: 'branch-1',
    productId: 'product-1',
    productName: productName,
    productBarcode: null,
    isWeight: isWeight,
    movementType: effectiveType,
    effectiveType: effectiveType,
    quantityDelta: quantityDelta,
    occurredAt: occurredAt ?? DateTime.utc(2026, 9, 18, 12),
    previousStock: previousStock,
    newStock: newStock,
    deviceId: deviceId,
    unitCost: unitCost,
  );
}
