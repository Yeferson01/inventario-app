import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/inventory_history_local_dao.dart';
import 'package:inventario_frontend/features/inventory/data/models/inventory_history_models.dart';

void main() {
  final instant = DateTime.utc(2026, 9, 25, 15, 30);

  test('ISO, seconds and milliseconds parse to the same UTC instant', () {
    final seconds = instant.millisecondsSinceEpoch ~/ 1000;
    final milliseconds = instant.millisecondsSinceEpoch;
    expect(parseInventoryHistoryTimestamp(instant.toIso8601String()), instant);
    expect(parseInventoryHistoryTimestamp(seconds), instant);
    expect(parseInventoryHistoryTimestamp(milliseconds), instant);
    expect(parseInventoryHistoryTimestamp(seconds)?.year, 2026);
    expect(parseInventoryHistoryTimestamp(seconds)?.isUtc, isTrue);
  });

  test('invalid and out-of-range dates fail closed', () {
    for (final bad in [null, 'not-a-date', 0, 12345, 99999999999999]) {
      expect(parseInventoryHistoryTimestamp(bad), isNull);
    }
    expect(
        () => InventoryHistoryRemoteRow.fromJson({
              'occurred_at': 'not-a-date',
            }),
        throwsFormatException);
  });

  late AppDatabase db;
  late InventoryHistoryLocalDao history;
  setUp(() {
    db = AppDatabase.executor(NativeDatabase.memory());
    history = InventoryHistoryLocalDao(db);
  });
  tearDown(() => db.close());

  Future<void> insertRaw(String id, Object date,
      {String product = 'product', String type = 'purchase'}) async {
    await db.customStatement('''
      insert into local_inventory_movements
        (id, business_id, branch_id, product_id, movement_type,
         source_type, quantity_change, idempotency_key, occurred_at)
      values (?, 'business', 'branch', ?, ?, ?, 1, ?, ?)
    ''', [id, product, type, type, id, date]);
  }

  Future<void> insertB1(String id, DateTime date, String type) async {
    await db.into(db.localInventoryMovements).insert(
          LocalInventoryMovementsCompanion.insert(
            id: id,
            businessId: 'business',
            branchId: const Value('branch'),
            productId: 'product',
            movementType: type,
            sourceType: Value(type),
            quantityChange: -1,
            idempotencyKey: id,
            occurredAt: date,
          ),
        );
  }

  InventoryHistoryLocalQuery query({
    String? product,
    DateTime? from,
    DateTime? to,
    InventoryHistoryCursor? cursor,
    int limit = 50,
  }) =>
      InventoryHistoryLocalQuery(
        businessId: 'business',
        branchId: 'branch',
        productId: product,
        from: from,
        to: to,
        cursor: cursor,
        limit: limit,
      );

  test('typed B1 loss and manual adjustment retain their real UTC dates',
      () async {
    await insertB1('loss', instant, 'loss');
    await insertB1(
        'manual', instant.add(const Duration(seconds: 1)), 'manual_adjustment');
    final raw = await db
        .customSelect(
          "select occurred_at from local_inventory_movements where id = 'loss'",
        )
        .getSingle();
    expect(raw.data['occurred_at'], instant.millisecondsSinceEpoch ~/ 1000);
    final rows = await history.loadHistory(query: query(), canViewCosts: false);
    expect(rows.map((r) => r.id), ['manual', 'loss']);
    expect(rows.first.occurredAt, instant.add(const Duration(seconds: 1)));
    expect(rows.last.occurredAt, instant);
  });

  test(
      'pending seconds, hydrated ISO and legacy milliseconds sort chronologically',
      () async {
    await insertB1(
        'local-loss', instant.add(const Duration(minutes: 3)), 'loss');
    await history.applyRefreshPage(
      businessId: 'business',
      branchId: 'branch',
      page: InventoryHistoryRemotePage(rows: [
        InventoryHistoryRemoteRow(
          id: 'hydrated-sale',
          businessId: 'business',
          branchId: 'branch',
          productId: 'product',
          movementType: 'sale',
          effectiveType: 'sale',
          quantityDelta: -1,
          occurredAt: instant.add(const Duration(minutes: 2)),
          idempotencyKey: 'hydrated-sale',
        ),
      ], hasMore: false),
      canViewCosts: false,
    );
    await insertRaw('legacy-purchase',
        instant.add(const Duration(minutes: 1)).millisecondsSinceEpoch);
    await insertRaw('historical-iso',
        instant.subtract(const Duration(minutes: 1)).toIso8601String());
    final rows = await history.loadHistory(query: query(), canViewCosts: false);
    expect(rows.map((r) => r.id),
        ['local-loss', 'hydrated-sale', 'legacy-purchase', 'historical-iso']);
    expect(
        rows.map((r) => r.occurredAt),
        orderedEquals([
          instant.add(const Duration(minutes: 3)),
          instant.add(const Duration(minutes: 2)),
          instant.add(const Duration(minutes: 1)),
          instant.subtract(const Duration(minutes: 1)),
        ]));
    final coverage =
        await history.getCoverage(businessId: 'business', branchId: 'branch');
    expect(coverage.hasCachedRows, isTrue);
    expect(coverage.hasMoreRemote, isFalse);
  });

  test('close timestamps and product filter preserve descending order',
      () async {
    await insertRaw('ms-new',
        instant.add(const Duration(milliseconds: 2)).millisecondsSinceEpoch);
    await insertRaw('iso-middle',
        instant.add(const Duration(milliseconds: 1)).toIso8601String());
    await insertB1('sec-old', instant, 'loss');
    await insertRaw(
        'foreign', instant.add(const Duration(minutes: 1)).toIso8601String(),
        product: 'other');
    final rows = await history.loadHistory(
        query: query(product: 'product'), canViewCosts: false);
    expect(rows.map((r) => r.id), ['ms-new', 'iso-middle', 'sec-old']);
  });

  test('range, cursor and pagination use the same chronology', () async {
    await insertB1('a', instant.add(const Duration(minutes: 3)), 'loss');
    await insertRaw(
        'b', instant.add(const Duration(minutes: 2)).toIso8601String());
    await insertRaw(
        'c', instant.add(const Duration(minutes: 1)).millisecondsSinceEpoch);
    await insertRaw('d', instant.toIso8601String());
    final first =
        await history.loadHistory(query: query(limit: 2), canViewCosts: false);
    expect(first.map((r) => r.id), ['a', 'b']);
    final second = await history.loadHistory(
        query: query(
            limit: 2,
            cursor: InventoryHistoryCursor(
              occurredAt: first.last.occurredAt,
              id: first.last.id,
            )),
        canViewCosts: false);
    expect(second.map((r) => r.id), ['c', 'd']);
    final range = await history.loadHistory(
        query: query(
          from: instant.add(const Duration(minutes: 1)),
          to: instant.add(const Duration(minutes: 2)),
        ),
        canViewCosts: false);
    expect(range.map((r) => r.id), ['b', 'c']);
  });

  test('malformed local timestamp never becomes a 1970 date', () async {
    await insertRaw('bad', 'not-a-date');
    expect(history.loadHistory(query: query(), canViewCosts: false),
        throwsFormatException);
  });
}
