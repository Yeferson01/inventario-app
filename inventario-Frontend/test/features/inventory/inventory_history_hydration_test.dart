import 'dart:collection';

import 'package:drift/drift.dart' show Variable;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_history_service.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/inventory_history_local_dao.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/inventory_history_remote_datasource.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/inventory_movement_local_dao.dart';
import 'package:inventario_frontend/features/inventory/data/models/inventory_history_models.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';

void main() {
  test('HY-01 refreshLatest downloads and persists the first page', () async {
    final h = await _Harness.create([
      [_row(id: 'm-1')]
    ]);
    addTearDown(h.close);

    final result = await h.service.refreshLatest(context: _context());
    final entries = await h.service.loadCachedHistory(context: _context());

    expect(result.outcome, InventoryHistoryHydrationOutcome.hydrated);
    expect(result.rowsApplied, 1);
    expect(entries.single.id, 'm-1');
  });

  test('HY-02 first hydration creates branch-wide hydration state', () async {
    final h = await _Harness.create([
      [_row(id: 'm-1')]
    ]);
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context());
    final state = await h.database
        .customSelect(
          'select * from local_history_hydration_states',
        )
        .getSingle();

    expect(state.data['business_id'], 'business-a');
    expect(state.data['branch_id'], 'branch-x');
    expect(state.data['domain'], InventoryHistoryLocalDao.domain);
  });

  test('HY-03 loadOlder sends the persisted compound cursor', () async {
    final timestamp = DateTime.utc(2026, 9, 18, 12);
    final h = await _Harness.create([
      [
        _row(id: 'm-2', occurredAt: timestamp),
        _row(id: 'm-1', occurredAt: timestamp),
      ],
      [
        _row(id: 'm-0', occurredAt: timestamp.subtract(const Duration(days: 1)))
      ],
    ]);
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context(), limit: 2);
    await h.service.loadOlder(context: _context(), limit: 2);

    expect(h.requests[1]['p_cursor_id'], 'm-1');
    expect(h.requests[1]['p_cursor_occurred_at'], timestamp.toIso8601String());
  });

  test('HY-04 loadOlder advances the tail cursor', () async {
    final h = await _pagedHarness();
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context(), limit: 2);
    await h.service.loadOlder(context: _context(), limit: 2);
    final coverage = await h.service.getCoverage(context: _context());

    expect(coverage.oldestCursor?.id, 'm-0');
  });

  test('HY-05 later refreshLatest preserves the existing tail cursor',
      () async {
    final h = await _Harness.create([
      [_row(id: 'm-2'), _row(id: 'm-1', offsetMinutes: -1)],
      [_row(id: 'm-0', offsetMinutes: -2)],
      [_row(id: 'm-3', offsetMinutes: 1)],
    ]);
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context(), limit: 2);
    await h.service.loadOlder(context: _context(), limit: 2);
    final tail =
        (await h.service.getCoverage(context: _context())).oldestCursor;
    await h.service.refreshLatest(context: _context(), limit: 2);

    expect(
        (await h.service.getCoverage(context: _context())).oldestCursor, tail);
  });

  test('HY-06 hasMore false is preserved after a later refresh', () async {
    final h = await _Harness.create([
      [_row(id: 'm-1')],
      [_row(id: 'm-2', offsetMinutes: 1)],
    ]);
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context(), limit: 2);
    expect((await h.service.getCoverage(context: _context())).hasMoreRemote,
        false);
    await h.service.refreshLatest(context: _context(), limit: 2);
    expect((await h.service.getCoverage(context: _context())).hasMoreRemote,
        false);
  });

  test('HY-07 equal timestamps remain ordered by descending id', () async {
    final timestamp = DateTime.utc(2026, 9, 18, 12);
    final h = await _Harness.create([
      [
        _row(id: 'm-z', occurredAt: timestamp),
        _row(id: 'm-a', occurredAt: timestamp),
      ],
    ]);
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context(), limit: 3);
    final entries = await h.service.loadCachedHistory(context: _context());

    expect(entries.map((entry) => entry.id), ['m-z', 'm-a']);
  });

  test('HY-08 row created by another device is hydrated', () async {
    final h = await _Harness.create([
      [_row(id: 'm-1', deviceId: 'other-device')],
    ]);
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context());
    final entries = await h.service.loadCachedHistory(context: _context());

    expect(entries.single.deviceId, 'other-device');
  });

  test('HY-09 hydration does not modify stock balances', () async {
    final h = await _Harness.create([
      [_row(id: 'm-1')]
    ]);
    addTearDown(h.close);
    await h.database.customStatement('''
      insert into local_product_stock_balances (
        id, business_id, branch_id, product_id, quantity_on_hand,
        quantity_available
      ) values ('balance-1', 'business-a', 'branch-x', 'product-1', 7, 7)
    ''');

    await h.service.refreshLatest(context: _context());
    final balance = await h.database
        .customSelect(
          "select quantity_on_hand from local_product_stock_balances where id = 'balance-1'",
        )
        .getSingle();

    expect(balance.data['quantity_on_hand'], 7);
  });

  test('HY-10 hydration creates no outbox rows', () async {
    final h = await _Harness.create([
      [_row(id: 'm-1')]
    ]);
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context());

    expect(await _count(h.database, 'local_sync_batches'), 0);
    expect(await _count(h.database, 'local_sync_mutations'), 0);
  });

  test('HY-11 caller with cost permission persists a normal cost', () async {
    final h = await _Harness.create([
      [_row(id: 'm-1', unitCost: 12.5)]
    ]);
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context(viewCosts: true));
    final row = await _movement(h.database, 'm-1');

    expect(row['unit_cost'], 12.5);
  });

  test('HY-12 caller with cost permission preserves authoritative zero',
      () async {
    final h = await _Harness.create([
      [_row(id: 'm-1', unitCost: 0)]
    ]);
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context(viewCosts: true));

    expect((await _movement(h.database, 'm-1'))['unit_cost'], 0.0);
  });

  test('HY-13 caller with cost permission persists authoritative null',
      () async {
    final h = await _Harness.create([
      [_row(id: 'm-1', unitCost: 15)],
      [_row(id: 'm-1')],
    ]);
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context(viewCosts: true));
    await h.service.refreshLatest(context: _context(viewCosts: true));

    expect((await _movement(h.database, 'm-1'))['unit_cost'], isNull);
  });

  test('HY-14 redacted null does not overwrite a known local cost', () async {
    final h = await _Harness.create([
      [_row(id: 'm-1', unitCost: 15)],
      [_row(id: 'm-1')],
    ]);
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context(viewCosts: true));
    await h.service.refreshLatest(context: _context());

    expect((await _movement(h.database, 'm-1'))['unit_cost'], 15.0);
  });

  test('HY-15 redacted new row is inserted with null cost', () async {
    final h = await _Harness.create([
      [_row(id: 'm-1')]
    ]);
    addTearDown(h.close);

    await h.service.refreshLatest(context: _context());

    expect((await _movement(h.database, 'm-1'))['unit_cost'], isNull);
  });

  test('HY-16 read model without cost permission hides stored cost', () async {
    final h = await _Harness.create([
      [_row(id: 'm-1', unitCost: 15)]
    ]);
    addTearDown(h.close);
    await h.service.refreshLatest(context: _context(viewCosts: true));

    final entries = await h.service.loadCachedHistory(context: _context());

    expect(entries.single.unitCost, isNull);
  });

  test('HY-17 read model with cost permission returns stored cost', () async {
    final h = await _Harness.create([
      [_row(id: 'm-1', unitCost: 15)]
    ]);
    addTearDown(h.close);
    await h.service.refreshLatest(context: _context(viewCosts: true));

    final entries = await h.service.loadCachedHistory(
      context: _context(viewCosts: true),
    );

    expect(entries.single.unitCost, 15.0);
  });

  test('HY-18 local read model isolates businesses', () async {
    final h = await _Harness.create([
      [_row(id: 'm-a')],
      [_row(id: 'm-b', businessId: 'business-b')],
    ]);
    addTearDown(h.close);
    await h.service.refreshLatest(context: _context());
    await h.service.refreshLatest(context: _context(businessId: 'business-b'));

    final entries = await h.service.loadCachedHistory(context: _context());

    expect(entries.map((entry) => entry.id), ['m-a']);
  });

  test('HY-19 local read model isolates branches', () async {
    final h = await _Harness.create([
      [_row(id: 'm-x')],
      [_row(id: 'm-y', branchId: 'branch-y')],
    ]);
    addTearDown(h.close);
    await h.service.refreshLatest(context: _context());
    await h.service.refreshLatest(context: _context(branchId: 'branch-y'));

    final entries = await h.service.loadCachedHistory(context: _context());

    expect(entries.map((entry) => entry.id), ['m-x']);
  });

  test('HY-20 local product filter is scoped and selective', () async {
    final h = await _Harness.create([
      [
        _row(id: 'm-2', productId: 'product-2'),
        _row(id: 'm-1', productId: 'product-1', offsetMinutes: -1),
      ],
    ]);
    addTearDown(h.close);
    await h.service.refreshLatest(context: _context(), limit: 3);

    final entries = await h.service.loadCachedHistory(
      context: _context(),
      productId: 'product-1',
    );

    expect(entries.map((entry) => entry.id), ['m-1']);
  });

  test('HY-21 type filter uses effective initial-stock semantics', () async {
    final h = await _Harness.create([
      [
        _row(id: 'm-2', sourceType: 'purchase', effectiveType: 'purchase'),
        _row(
          id: 'm-1',
          sourceType: null,
          referenceType: 'manual_initial_stock',
          effectiveType: 'initial_stock',
          offsetMinutes: -1,
        ),
      ],
    ]);
    addTearDown(h.close);
    await h.service.refreshLatest(context: _context(), limit: 3);

    final entries = await h.service.loadCachedHistory(
      context: _context(),
      effectiveType: 'initial_stock',
    );

    expect(entries.map((entry) => entry.id), ['m-1']);
  });

  test('HY-22 local date range is inclusive and scoped', () async {
    final base = DateTime.utc(2026, 9, 18, 12);
    final h = await _Harness.create([
      [
        _row(id: 'm-3', occurredAt: base.add(const Duration(hours: 1))),
        _row(id: 'm-2', occurredAt: base),
        _row(id: 'm-1', occurredAt: base.subtract(const Duration(hours: 1))),
      ],
    ]);
    addTearDown(h.close);
    await h.service.refreshLatest(context: _context(), limit: 4);

    final entries = await h.service.loadCachedHistory(
      context: _context(),
      from: base,
      to: base,
    );

    expect(entries.map((entry) => entry.id), ['m-2']);
  });

  test('HY-23 offline refresh with cache returns local availability', () async {
    final h = await _Harness.create([
      [_row(id: 'm-1')]
    ]);
    addTearDown(h.close);
    await h.service.refreshLatest(context: _context());
    h.online = false;

    final result = await h.service.refreshLatest(context: _context());

    expect(result.outcome, InventoryHistoryHydrationOutcome.cachedOffline);
    expect(result.coverage.hasCachedRows, true);
    expect(h.requests, hasLength(1));
  });

  test('HY-24 offline refresh without cache is noCachedHistory', () async {
    final h = await _Harness.create([])
      ..online = false;
    addTearDown(h.close);

    final result = await h.service.refreshLatest(context: _context());

    expect(result.outcome, InventoryHistoryHydrationOutcome.noCachedHistory);
    expect(h.requests, isEmpty);
  });

  test('HY-25 offline loadOlder preserves cache and hydration state', () async {
    final h = await _Harness.create([
      [_row(id: 'm-2'), _row(id: 'm-1', offsetMinutes: -1)],
    ]);
    addTearDown(h.close);
    await h.service.refreshLatest(context: _context(), limit: 2);
    final before = await h.service.getCoverage(context: _context());
    h.online = false;

    final result = await h.service.loadOlder(context: _context(), limit: 2);
    final after = await h.service.getCoverage(context: _context());

    expect(result.outcome, InventoryHistoryHydrationOutcome.connectionRequired);
    expect(after.oldestCursor, before.oldestCursor);
    expect(
        await h.service.loadCachedHistory(context: _context()), hasLength(2));
  });

  test('HY-26 malformed page fails without partial application', () async {
    final valid = _row(id: 'm-2');
    final malformed = _row(id: 'm-1')..remove('occurred_at');
    final h = await _Harness.create([
      [valid, malformed],
    ]);
    addTearDown(h.close);

    await expectLater(
      h.service.refreshLatest(context: _context()),
      throwsA(isA<FormatException>()),
    );

    expect(await _count(h.database, 'local_inventory_movements'), 0);
    expect(await _count(h.database, 'local_history_hydration_states'), 0);
  });

  test('HY-27 pending local movement is not degraded by hydration', () async {
    final h = await _Harness.create([
      [_row(id: 'pending-1', quantity: 99, unitCost: 9)],
    ]);
    addTearDown(h.close);
    await InventoryMovementLocalDao(h.database).insertInitialMovement(
      id: 'pending-1',
      businessId: 'business-a',
      branchId: 'branch-x',
      productId: 'product-1',
      movementType: 'purchase',
      quantityChange: 5,
      unitCost: 6,
      sourceType: 'purchase',
      referenceType: 'purchase',
      notes: 'local pending',
      idempotencyKey: 'local-key',
      occurredAt: DateTime.utc(2026, 9, 18, 12),
      metadata: const {},
    );

    await h.service.refreshLatest(context: _context(viewCosts: true));
    final row = await _movement(h.database, 'pending-1');

    expect(row['quantity_change'], 5);
    expect(row['sync_status'], 0);
    expect(row['local_status'], 'dirty');
    expect(row['idempotency_key'], 'local-key');
  });

  test('history merge preserves existing synced operational idempotency',
      () async {
    final h = await _Harness.create([
      [_row(id: 'synced-1')]
    ]);
    addTearDown(h.close);
    await h.database.customStatement('''
      insert into local_inventory_movements (
        id, business_id, branch_id, product_id, movement_type,
        quantity_change, idempotency_key, sync_status, local_status,
        occurred_at, created_at, updated_at
      ) values (
        'synced-1', 'business-a', 'branch-x', 'product-1', 'purchase',
        1, 'existing-local-key', 1, 'synced',
        '2026-09-18T12:00:00.000Z', '2026-09-18T12:00:00.000Z',
        '2026-09-18T12:00:00.000Z'
      )
    ''');

    await h.service.refreshLatest(context: _context(viewCosts: true));

    expect(
      (await _movement(h.database, 'synced-1'))['idempotency_key'],
      'existing-local-key',
    );
  });
}

class _Harness {
  _Harness._({
    required this.database,
    required this.service,
    required this.requests,
    required this.responses,
  });

  final AppDatabase database;
  final InventoryHistoryService service;
  final List<Map<String, Object?>> requests;
  final Queue<List<Map<String, dynamic>>> responses;
  bool online = true;

  static Future<_Harness> create(
    List<List<Map<String, dynamic>>> responsePages,
  ) async {
    final database = AppDatabase.executor(NativeDatabase.memory());
    final requests = <Map<String, Object?>>[];
    final responses = Queue<List<Map<String, dynamic>>>.from(responsePages);
    late _Harness harness;
    final remote =
        InventoryHistoryRemoteDatasource.withInvoker((parameters) async {
      requests.add(Map<String, Object?>.from(parameters));
      if (responses.isEmpty) {
        throw StateError('No fake inventory history response remains.');
      }
      return responses.removeFirst();
    });
    harness = _Harness._(
      database: database,
      service: InventoryHistoryService(
        localDao: InventoryHistoryLocalDao(database),
        remoteDatasource: remote,
        isOnline: () async => harness.online,
      ),
      requests: requests,
      responses: responses,
    );
    return harness;
  }

  Future<void> close() => database.close();
}

Future<_Harness> _pagedHarness() {
  return _Harness.create([
    [_row(id: 'm-2'), _row(id: 'm-1', offsetMinutes: -1)],
    [_row(id: 'm-0', offsetMinutes: -2)],
  ]);
}

AppCurrentContext _context({
  String businessId = 'business-a',
  String branchId = 'branch-x',
  bool viewCosts = false,
}) {
  return AppCurrentContext(
    businessId: businessId,
    branchId: branchId,
    profileId: 'profile-a',
    installationId: 'installation-a',
    isOnline: true,
    authorizationContextReady: true,
    permissions: AppPermissionSet.fromIterable([
      'inventory.read',
      if (viewCosts) 'inventory.view_costs',
    ]),
  );
}

Map<String, dynamic> _row({
  required String id,
  String businessId = 'business-a',
  String branchId = 'branch-x',
  String productId = 'product-1',
  String movementType = 'purchase',
  String? sourceType = 'purchase',
  String effectiveType = 'purchase',
  String? referenceType = 'purchase',
  DateTime? occurredAt,
  int offsetMinutes = 0,
  int quantity = 1,
  String? deviceId = 'device-a',
  double? unitCost,
}) {
  final time = (occurredAt ?? DateTime.utc(2026, 9, 18, 12))
      .add(Duration(minutes: offsetMinutes));
  return {
    'id': id,
    'business_id': businessId,
    'branch_id': branchId,
    'product_id': productId,
    'movement_type': movementType,
    'source_type': sourceType,
    'effective_type': effectiveType,
    'source_id': 'source-$id',
    'reference_type': referenceType,
    'reference_id': 'reference-$id',
    'quantity_delta': quantity,
    'occurred_at': time.toIso8601String(),
    'previous_stock': 1,
    'new_stock': 1 + quantity,
    'created_by': 'profile-a',
    'device_id': deviceId,
    'reversed_movement_id': null,
    'idempotency_key': 'remote-$id',
    'unit_cost': unitCost,
  };
}

Future<int> _count(AppDatabase database, String table) async {
  final row = await database
      .customSelect('select count(*) as value from $table')
      .getSingle();
  return (row.data['value'] as num).toInt();
}

Future<Map<String, Object?>> _movement(AppDatabase database, String id) async {
  final row = await database.customSelect(
    'select * from local_inventory_movements where id = ?',
    variables: [Variable<String>(id)],
  ).getSingle();
  return row.data;
}
