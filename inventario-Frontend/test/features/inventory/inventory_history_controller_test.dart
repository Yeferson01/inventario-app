import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inventario_frontend/features/inventory/application/inventory_history_controller.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_history_providers.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_history_service.dart';
import 'package:inventario_frontend/features/inventory/data/models/inventory_history_models.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';

void main() {
  group('InventoryHistoryViewRequest', () {
    test('identity ignores connectivity but includes security scope', () {
      final baseContext = _context();

      final offlineSameScope = _context(
        isOnline: false,
      );

      final base = InventoryHistoryViewRequest(
        context: baseContext,
      );

      final sameSecurityScopeOffline = InventoryHistoryViewRequest(
        context: offlineSameScope,
      );

      expect(base, sameSecurityScopeOffline);
      expect(base.hashCode, sameSecurityScopeOffline.hashCode);

      expect(
        base,
        isNot(
          InventoryHistoryViewRequest(
            context: _context(profileId: 'profile-2'),
          ),
        ),
      );

      expect(
        base,
        isNot(
          InventoryHistoryViewRequest(
            context: _context(branchId: 'branch-2'),
          ),
        ),
      );

      expect(
        base,
        isNot(
          InventoryHistoryViewRequest(
            context: _context(
              permissions: const {'inventory.read'},
            ),
          ),
        ),
      );

      expect(
        base,
        isNot(
          InventoryHistoryViewRequest(
            context: _context(
              authorizationValidatedAt: DateTime.utc(2026, 9, 18, 13),
            ),
          ),
        ),
      );

      expect(
        base,
        isNot(
          InventoryHistoryViewRequest(
            context: baseContext,
            productId: 'product-1',
          ),
        ),
      );
    });
  });

  group('InventoryHistoryController', () {
    test('renders cached rows before refresh completes', () async {
      final cached = _row(
        id: 'movement-cached',
        occurredAt: DateTime.utc(2026, 9, 18, 12),
      );
      final refreshCompleter = Completer<InventoryHistoryHydrationResult>();

      final service = _FakeInventoryHistoryService(
        cachedRows: [cached],
        coverage: _coverage(
          hasCachedRows: true,
          hasMoreRemote: true,
        ),
      );

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) {
        return refreshCompleter.future;
      };

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: _context(),
        ),
      );

      final state = mounted.container.read(mounted.provider);

      expect(state.rows.map((row) => row.id), ['movement-cached']);
      expect(state.phase, InventoryHistoryScreenPhase.ready);
      expect(state.isRefreshing, isTrue);

      refreshCompleter.complete(
        InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.cachedOffline,
          coverage: _coverage(
            hasCachedRows: true,
            hasMoreRemote: true,
          ),
        ),
      );

      await _flush();
    });

    test('successful refresh reloads latest local rows', () async {
      var cachedRows = [
        _row(
          id: 'movement-old',
          occurredAt: DateTime.utc(2026, 9, 18, 11),
        ),
      ];

      final service = _FakeInventoryHistoryService(
        cachedRows: cachedRows,
        coverage: _coverage(
          hasCachedRows: true,
          hasMoreRemote: true,
        ),
      );

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) async {
        cachedRows = [
          _row(
            id: 'movement-new',
            occurredAt: DateTime.utc(2026, 9, 18, 12),
          ),
          ...cachedRows,
        ];
        service.cachedRows = cachedRows;

        return InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.hydrated,
          coverage: _coverage(
            hasCachedRows: true,
            hasMoreRemote: true,
          ),
          rowsApplied: 1,
        );
      };

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: _context(),
        ),
      );

      await _flush();

      final state = mounted.container.read(mounted.provider);

      expect(
        state.rows.map((row) => row.id),
        ['movement-new', 'movement-old'],
      );
      expect(state.isRefreshing, isFalse);
      expect(state.isOffline, isFalse);
      expect(state.phase, InventoryHistoryScreenPhase.ready);
    });

    test('refresh failure preserves cached rows', () async {
      final service = _FakeInventoryHistoryService(
        cachedRows: [
          _row(
            id: 'movement-cached',
            occurredAt: DateTime.utc(2026, 9, 18, 12),
          ),
        ],
        coverage: _coverage(
          hasCachedRows: true,
          hasMoreRemote: true,
        ),
      );

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) async {
        throw StateError('network failure');
      };

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: _context(),
        ),
      );

      await _flush();

      final state = mounted.container.read(mounted.provider);

      expect(state.rows.single.id, 'movement-cached');
      expect(state.phase, InventoryHistoryScreenPhase.ready);
      expect(
        state.notice,
        InventoryHistoryScreenNotice.refreshFailed,
      );
      expect(state.failure, isNull);
    });

    test('offline with cache preserves data and marks state offline', () async {
      final service = _FakeInventoryHistoryService(
        cachedRows: [
          _row(
            id: 'movement-cached',
            occurredAt: DateTime.utc(2026, 9, 18, 12),
          ),
        ],
        coverage: _coverage(
          hasCachedRows: true,
          hasMoreRemote: true,
        ),
      );

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) async {
        return InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.cachedOffline,
          coverage: service.coverage,
        );
      };

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: _context(),
        ),
      );

      await _flush();

      final state = mounted.container.read(mounted.provider);

      expect(state.rows.single.id, 'movement-cached');
      expect(state.isOffline, isTrue);
      expect(state.phase, InventoryHistoryScreenPhase.ready);
    });

    test('offline without cache produces emptyOffline', () async {
      final service = _FakeInventoryHistoryService(
        cachedRows: const [],
        coverage: _coverage(
          hasCachedRows: false,
          hasMoreRemote: true,
        ),
      );

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) async {
        return InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.noCachedHistory,
          coverage: service.coverage,
        );
      };

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: _context(),
        ),
      );

      await _flush();

      final state = mounted.container.read(mounted.provider);

      expect(state.rows, isEmpty);
      expect(state.isOffline, isTrue);
      expect(state.phase, InventoryHistoryScreenPhase.emptyOffline);
    });

    test('loadOlder consumes cached local page before remote hydration',
        () async {
      final firstPage = List.generate(
        50,
        (index) => _row(
          id: 'movement-${100 - index}',
          occurredAt: DateTime.utc(
            2026,
            9,
            18,
            12,
            0,
            100 - index,
          ),
        ),
      );

      final secondPage = [
        _row(
          id: 'movement-older',
          occurredAt: DateTime.utc(2026, 9, 18, 10),
        ),
      ];

      final service = _FakeInventoryHistoryService(
        cachedRows: firstPage,
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
        return cursor == null ? firstPage : secondPage;
      };

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) async {
        return InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.hydrated,
          coverage: service.coverage,
        );
      };

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: _context(),
        ),
      );

      await _flush();

      await mounted.notifier.loadOlder();
      await _flush();

      final state = mounted.container.read(mounted.provider);

      expect(state.rows.length, 51);
      expect(state.rows.last.id, 'movement-older');
      expect(service.loadOlderCalls, 0);
    });

    test('loadOlder hydrates remote after local cache is exhausted', () async {
      final firstPage = List.generate(
        50,
        (index) => _row(
          id: 'movement-${100 - index}',
          occurredAt: DateTime.utc(
            2026,
            9,
            18,
            12,
            0,
            100 - index,
          ),
        ),
      );

      var olderHydrated = false;

      final service = _FakeInventoryHistoryService(
        cachedRows: firstPage,
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
          return firstPage;
        }

        if (!olderHydrated) {
          return const [];
        }

        return [
          _row(
            id: 'movement-remote-older',
            occurredAt: DateTime.utc(2026, 9, 17, 12),
          ),
        ];
      };

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) async {
        return InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.hydrated,
          coverage: service.coverage,
        );
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

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: _context(),
        ),
      );

      await _flush();

      await mounted.notifier.loadOlder();
      await _flush();

      final state = mounted.container.read(mounted.provider);

      expect(service.loadOlderCalls, 1);
      expect(state.rows.last.id, 'movement-remote-older');
      expect(state.hasMoreRemote, isFalse);
    });

    test('loadOlder offline preserves rows and reports connectionRequired',
        () async {
      final firstPage = List.generate(
        50,
        (index) => _row(
          id: 'movement-${100 - index}',
          occurredAt: DateTime.utc(
            2026,
            9,
            18,
            12,
            0,
            100 - index,
          ),
        ),
      );

      final service = _FakeInventoryHistoryService(
        cachedRows: firstPage,
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
        return cursor == null ? firstPage : const [];
      };

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) async {
        return InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.hydrated,
          coverage: service.coverage,
        );
      };

      service.onLoadOlder = ({
        required context,
        required limit,
      }) async {
        return InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.connectionRequired,
          coverage: service.coverage,
        );
      };

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: _context(),
        ),
      );

      await _flush();

      await mounted.notifier.loadOlder();
      await _flush();

      final state = mounted.container.read(mounted.provider);

      expect(state.rows.length, 50);
      expect(state.isOffline, isTrue);
      expect(
        state.notice,
        InventoryHistoryScreenNotice.connectionRequired,
      );
    });

    test('effective type filter reloads local cache without remote hydration',
        () async {
      final service = _FakeInventoryHistoryService(
        cachedRows: [
          _row(
            id: 'movement-all',
            occurredAt: DateTime.utc(2026, 9, 18, 12),
          ),
        ],
        coverage: _coverage(
          hasCachedRows: true,
          hasMoreRemote: true,
        ),
      );

      String? lastEffectiveType;

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

        if (effectiveType == 'purchase') {
          return [
            _row(
              id: 'movement-purchase',
              occurredAt: DateTime.utc(2026, 9, 18, 11),
              effectiveType: 'purchase',
            ),
          ];
        }

        return service.cachedRows;
      };

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) async {
        return InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.hydrated,
          coverage: service.coverage,
        );
      };

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: _context(),
        ),
      );

      await _flush();

      final refreshCallsBeforeFilter = service.refreshLatestCalls;
      final loadOlderCallsBeforeFilter = service.loadOlderCalls;

      await mounted.notifier.setEffectiveType(' PURCHASE ');
      await _flush();

      final state = mounted.container.read(mounted.provider);

      expect(lastEffectiveType, 'purchase');
      expect(state.effectiveType, 'purchase');
      expect(state.rows.single.id, 'movement-purchase');
      expect(service.refreshLatestCalls, refreshCallsBeforeFilter);
      expect(service.loadOlderCalls, loadOlderCallsBeforeFilter);
    });

    test('refresh is single-flight', () async {
      final service = _FakeInventoryHistoryService(
        cachedRows: [
          _row(
            id: 'movement',
            occurredAt: DateTime.utc(2026, 9, 18, 12),
          ),
        ],
        coverage: _coverage(
          hasCachedRows: true,
          hasMoreRemote: false,
        ),
      );

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) async {
        return InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.hydrated,
          coverage: service.coverage,
        );
      };

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: _context(),
        ),
      );

      await _flush();

      final completer = Completer<InventoryHistoryHydrationResult>();

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) {
        return completer.future;
      };

      service.refreshLatestCalls = 0;

      final first = mounted.notifier.refresh();
      final second = mounted.notifier.refresh();

      await _flush(2);

      expect(service.refreshLatestCalls, 1);

      completer.complete(
        InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.hydrated,
          coverage: service.coverage,
        ),
      );

      await Future.wait([first, second]);
      await _flush();
    });

    test('loadOlder is single-flight', () async {
      final firstPage = List.generate(
        50,
        (index) => _row(
          id: 'movement-${100 - index}',
          occurredAt: DateTime.utc(
            2026,
            9,
            18,
            12,
            0,
            100 - index,
          ),
        ),
      );

      final olderCompleter = Completer<InventoryHistoryHydrationResult>();

      final service = _FakeInventoryHistoryService(
        cachedRows: firstPage,
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
        return cursor == null ? firstPage : const [];
      };

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) async {
        return InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.hydrated,
          coverage: service.coverage,
        );
      };

      service.onLoadOlder = ({
        required context,
        required limit,
      }) {
        return olderCompleter.future;
      };

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: _context(),
        ),
      );

      await _flush();

      service.loadOlderCalls = 0;

      final first = mounted.notifier.loadOlder();
      await _flush(2);
      final second = mounted.notifier.loadOlder();

      await _flush(2);

      expect(service.loadOlderCalls, 1);

      olderCompleter.complete(
        InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.noMoreRemote,
          coverage: _coverage(
            hasCachedRows: true,
            hasMoreRemote: false,
          ),
        ),
      );

      await Future.wait([first, second]);
      await _flush();
    });

    test('access failure becomes fail-closed presentation state', () async {
      final service = _FakeInventoryHistoryService(
        cachedRows: const [],
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

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: _context(
            permissions: const {},
          ),
        ),
      );

      await _flush();

      final state = mounted.container.read(mounted.provider);

      expect(state.rows, isEmpty);
      expect(state.phase, InventoryHistoryScreenPhase.error);
      expect(
        state.failure,
        InventoryHistoryScreenFailure.accessDenied,
      );
    });

    test(
        'warehouse controller receives hidden cost from permission-aware service',
        () async {
      final warehouseContext = _context(
        profileId: 'warehouse-profile',
        permissions: const {'inventory.read'},
      );

      final service = _FakeInventoryHistoryService(
        cachedRows: const [],
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
        return [
          _row(
            id: 'movement-secret-cost',
            occurredAt: DateTime.utc(2026, 9, 18, 12),
            unitCost:
                context.hasPermission('inventory.view_costs') ? 1234 : null,
          ),
        ];
      };

      service.onRefreshLatest = ({
        required context,
        required limit,
      }) async {
        return InventoryHistoryHydrationResult(
          outcome: InventoryHistoryHydrationOutcome.hydrated,
          coverage: service.coverage,
        );
      };

      final mounted = await _mount(
        service: service,
        request: InventoryHistoryViewRequest(
          context: warehouseContext,
        ),
      );

      await _flush();

      final state = mounted.container.read(mounted.provider);

      expect(state.canViewCosts, isFalse);
      expect(state.rows.single.unitCost, isNull);
    });
  });
}

class _FakeInventoryHistoryService implements InventoryHistoryService {
  _FakeInventoryHistoryService({
    required this.cachedRows,
    required this.coverage,
  });

  List<InventoryMovementHistoryEntry> cachedRows;
  InventoryHistoryCoverage coverage;

  int refreshLatestCalls = 0;
  int loadOlderCalls = 0;
  int loadCachedHistoryCalls = 0;
  int getCoverageCalls = 0;

  Future<InventoryHistoryHydrationResult> Function({
    required AppCurrentContext context,
    required int limit,
  })? onRefreshLatest;

  Future<InventoryHistoryHydrationResult> Function({
    required AppCurrentContext context,
    required int limit,
  })? onLoadOlder;

  Future<List<InventoryMovementHistoryEntry>> Function({
    required AppCurrentContext context,
    String? productId,
    String? effectiveType,
    DateTime? from,
    DateTime? to,
    InventoryHistoryCursor? cursor,
    required int limit,
  })? onLoadCachedHistory;

  Future<InventoryHistoryCoverage> Function({
    required AppCurrentContext context,
  })? onGetCoverage;

  @override
  Future<InventoryHistoryHydrationResult> refreshLatest({
    required AppCurrentContext context,
    int limit = 50,
  }) async {
    refreshLatestCalls++;

    final callback = onRefreshLatest;
    if (callback != null) {
      return callback(
        context: context,
        limit: limit,
      );
    }

    return InventoryHistoryHydrationResult(
      outcome: InventoryHistoryHydrationOutcome.hydrated,
      coverage: coverage,
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
    loadCachedHistoryCalls++;

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

    return cachedRows;
  }

  @override
  Future<InventoryHistoryCoverage> getCoverage({
    required AppCurrentContext context,
  }) async {
    getCoverageCalls++;

    final callback = onGetCoverage;
    if (callback != null) {
      return callback(context: context);
    }

    return coverage;
  }
}

class _MountedController {
  const _MountedController({
    required this.container,
    required this.provider,
    required this.notifier,
  });

  final ProviderContainer container;
  final dynamic provider;
  final InventoryHistoryController notifier;
}

Future<_MountedController> _mount({
  required _FakeInventoryHistoryService service,
  required InventoryHistoryViewRequest request,
}) async {
  final container = ProviderContainer(
    overrides: [
      inventoryHistoryServiceProvider.overrideWithValue(service),
    ],
  );

  addTearDown(container.dispose);

  final provider = inventoryHistoryControllerProvider(request);

  final subscription = container.listen<InventoryHistoryScreenState>(
    provider,
    (_, __) {},
    fireImmediately: true,
  );

  addTearDown(subscription.close);

  await _flush();

  return _MountedController(
    container: container,
    provider: provider,
    notifier: container.read(provider.notifier),
  );
}

Future<void> _flush([int turns = 8]) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
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
  DateTime? authorizationValidatedAt,
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
    authorizationValidatedAt:
        authorizationValidatedAt ?? DateTime.utc(2026, 9, 18, 12),
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
            occurredAt: DateTime.utc(2026, 9, 18, 10),
            id: 'oldest',
          )
        : null,
    lastRefreshedAt: DateTime.utc(2026, 9, 18, 12),
  );
}

InventoryMovementHistoryEntry _row({
  required String id,
  required DateTime occurredAt,
  String effectiveType = 'purchase',
  double? unitCost = 1000,
}) {
  return InventoryMovementHistoryEntry(
    id: id,
    businessId: 'business-1',
    branchId: 'branch-1',
    productId: 'product-1',
    productName: 'Producto de prueba',
    productBarcode: '7700000000001',
    movementType: effectiveType,
    effectiveType: effectiveType,
    quantityDelta: 1,
    occurredAt: occurredAt,
    unitCost: unitCost,
  );
}
