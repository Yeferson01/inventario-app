import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';

void main() {
  late AppDatabase db;
  final at = DateTime.utc(2026, 9, 25, 15);

  setUp(() async {
    db = AppDatabase.executor(NativeDatabase.memory());
    await db
        .into(db.businesses)
        .insert(BusinessesCompanion.insert(id: 'b', name: 'B'));
    await db.into(db.profiles).insert(ProfilesCompanion.insert(id: 'p'));
    for (final branch in ['a', 'z']) {
      await db.customStatement(
          'insert into branches (id,business_id,name) values (?,?,?)',
          [branch, 'b', branch]);
      await db.into(db.cashRegisters).insert(CashRegistersCompanion.insert(
          id: 'r$branch',
          businessId: const Value('b'),
          branchId: Value(branch)));
      await db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
          id: 's$branch',
          businessId: const Value('b'),
          branchId: Value(branch),
          cashRegisterId: Value('r$branch')));
    }
  });
  tearDown(() async => db.close());

  Future<void> insert(String id,
          {String branch = 'a',
          DateTime? time,
          String direction = 'outflow',
          String category = 'utilities',
          String source = 'manual',
          String? sourceId,
          String? reversal,
          BigInt? cents,
          String? key}) =>
      db
          .into(db.localCashMovements)
          .insert(LocalCashMovementsCompanion.insert(
              id: id,
              businessId: 'b',
              branchId: branch,
              cashRegisterId: 'r$branch',
              cashSessionId: 's$branch',
              direction: direction,
              category: category,
              amountCents: cents ?? BigInt.from(12345),
              currency: 'COP',
              sourceType: source,
              sourceId: Value(sourceId),
              occurredAt: time ?? at,
              createdBy: 'p',
              idempotencyKey: key ?? id,
              metadataJson: const Value('{"detail":"fixture"}'),
              reversedMovementId: Value(reversal),
              createdAt: at,
              updatedAt: at))
          .then((_) {});

  Future<LocalCashMovement> row() =>
      db.select(db.localCashMovements).getSingle();

  test('fresh schema is 18 and contains cash movements table', () async {
    expect(db.schemaVersion, 18);
    expect(await db.select(db.localCashMovements).get(), isEmpty);
  });
  test('exact BigInt cents roundtrip at backend maximum, stored as integer',
      () async {
    final cents = BigInt.parse('99999999999999');
    await insert('m', cents: cents);
    expect((await row()).amountCents, cents);
    expect(
        (await db
                .customSelect(
                    'select typeof(amount_cents) t from local_cash_movements')
                .getSingle())
            .read<String>('t'),
        'integer');
  });
  test('inflow and category persist', () async {
    await insert('m', direction: 'inflow', category: 'owner_contribution');
    expect((await row()).direction, 'inflow');
    expect((await row()).category, 'owner_contribution');
  });
  test('manual nullable source and reversal persist', () async {
    await insert('m');
    expect((await row()).sourceId, isNull);
    expect((await row()).reversedMovementId, isNull);
  });
  test('purchase representation persists without purchase integration',
      () async {
    await insert('m',
        source: 'purchase',
        sourceId: 'purchase',
        category: 'supplier_purchase');
    expect((await row()).sourceId, 'purchase');
    expect((await row()).sourceType, 'purchase');
  });
  test('idempotency cannot duplicate within business', () async {
    await insert('m', key: 'device:key');
    expect((await row()).idempotencyKey, 'device:key');
    await expectLater(
        insert('n', key: 'device:key'), throwsA(isA<Exception>()));
  });
  test('metadata preserved', () async {
    await insert('m');
    expect((await row()).metadataJson, '{"detail":"fixture"}');
  });
  test('pending and technical synced status', () async {
    await insert('m');
    expect((await row()).syncStatus, SyncStatus.pendingInsert);
    await db.update(db.localCashMovements).write(
        const LocalCashMovementsCompanion(
            syncStatus: Value(SyncStatus.synced),
            localStatus: Value('synced')));
    expect((await row()).localStatus, 'synced');
  });
  test('chronological query uses scope and stable id tie break', () async {
    await insert('old', time: at.subtract(const Duration(seconds: 1)));
    await insert('new');
    await insert('other', branch: 'z');
    final query = db.select(db.localCashMovements)
      ..where((m) =>
          m.businessId.equals('b') &
          m.branchId.equals('a') &
          m.cashSessionId.equals('sa'))
      ..orderBy([
        (m) => OrderingTerm.desc(m.occurredAt),
        (m) => OrderingTerm.asc(m.id)
      ]);
    expect((await query.get()).map((m) => m.id), ['new', 'old']);
  });
  for (final scope in ['business', 'branch', 'session']) {
    test('$scope isolation', () async {
      await insert('m');
      final query = db.select(db.localCashMovements)
        ..where((m) => switch (scope) {
              'business' => m.businessId.equals('foreign'),
              'branch' => m.branchId.equals('z'),
              _ => m.cashSessionId.equals('sz'),
            });
      expect(await query.get(), isEmpty);
    });
  }
  test('functional edits and deletion rejected', () async {
    await insert('m');
    await expectLater(
        db
            .update(db.localCashMovements)
            .write(const LocalCashMovementsCompanion(category: Value('other'))),
        throwsA(isA<Exception>()));
    await expectLater(
        db.delete(db.localCashMovements).go(), throwsA(isA<Exception>()));
  });
  for (final value in [0, -1]) {
    test(
        'reject invalid cents $value',
        () async => expectLater(
            insert('m', cents: BigInt.from(value)), throwsA(isA<Exception>())));
  }
  test('reversal reference persists; absent target rejected', () async {
    await insert('m');
    await insert('r', direction: 'inflow', reversal: 'm');
    await expectLater(
        insert('bad', reversal: 'missing'), throwsA(isA<Exception>()));
  });
  test('no outbox created by storage tests', () async {
    await insert('m');
    expect(await db.select(db.localSyncBatches).get(), isEmpty);
    expect(await db.select(db.localSyncMutations).get(), isEmpty);
  });
  test('cross-branch register/session pairing is rejected', () async {
    await expectLater(db.customStatement('''
      insert into local_cash_movements
      (id,business_id,branch_id,cash_register_id,cash_session_id,direction,
       category,amount_cents,currency,source_type,occurred_at,created_by,
       idempotency_key,created_at,updated_at)
      values ('bad','b','z','ra','sa','outflow','other',100,'COP','manual',1,'p','bad',1,1)
    '''), throwsA(isA<Exception>()));
  });
}
