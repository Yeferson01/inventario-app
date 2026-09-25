import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_adjustment_models.dart';
import 'package:inventario_frontend/features/inventory/application/inventory_adjustment_service.dart';
import 'package:inventario_frontend/features/inventory/data/datasources/product_stock_balance_local_dao.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/inventory_balance_reconciliation_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/inventory_movement_acknowledgement_models.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';

void main() {
  late AppDatabase db;
  late InventoryAdjustmentService service;
  late AppCurrentContext? context;
  Future<void> projection(
          {List<String> permissions = const ['inventory.adjust'],
          String status = 'active'}) =>
      AuthorizedOperationalContextLocalDao(db).replaceContext(
          AuthorizedOperationalContextProjection(
              profileId: 'profile',
              businessId: 'business',
              branchId: 'branch',
              effectivePermissions: permissions,
              effectiveRoles: const ['custom-role'],
              applicableMembershipIds: const ['membership'],
              authorizationValidatedAt: DateTime.utc(2026, 9, 25),
              snapshotId: 'snapshot',
              status: status));
  Future<void> balance(
          {int quantity = 10, int reserved = 0, double? cost = 2500}) =>
      db.into(db.localProductStockBalances).insertOnConflictUpdate(
          LocalProductStockBalancesCompanion.insert(
              id: 'balance',
              businessId: 'business',
              branchId: 'branch',
              productId: 'product',
              quantityOnHand: Value(quantity),
              quantityReserved: Value(reserved),
              quantityAvailable: Value(quantity - reserved),
              averageCost: Value(cost)));
  Future<LocalProductStockBalance> currentBalance() =>
      db.select(db.localProductStockBalances).getSingle();
  Future<LocalInventoryMovement> movement() =>
      db.select(db.localInventoryMovements).getSingle();
  Future<void> unchanged() async {
    expect((await currentBalance()).quantityOnHand, 10);
    expect(await db.select(db.localInventoryMovements).get(), isEmpty);
    expect(await db.customSelect('select * from local_sync_mutations').get(),
        isEmpty);
    expect(await db.customSelect('select * from local_sync_batches').get(),
        isEmpty);
  }

  setUp(() async {
    db = AppDatabase.executor(NativeDatabase.memory());
    await db
        .into(db.businesses)
        .insert(BusinessesCompanion.insert(id: 'business', name: 'Business'));
    await db.into(db.branches).insert(BranchesCompanion.insert(
        id: 'branch', businessId: 'business', name: 'Branch'));
    await db.into(db.profiles).insert(ProfilesCompanion.insert(id: 'profile'));
    await db.into(db.products).insert(ProductsCompanion.insert(
        id: 'product',
        businessId: const Value('business'),
        name: 'Product',
        salePrice: 3000,
        purchasePrice: const Value(99999),
        minimumStock: const Value(3),
        stockQuantity: const Value(987)));
    context = _context();
    await projection();
    await balance();
    service = InventoryAdjustmentService(
        database: db, loadCurrentContext: () async => context);
  });
  tearDown(() => db.close());

  test('denies missing permission even with active projection', () async {
    context = _context(permissions: const []);
    await expectLater(service.applyAdjustment(_loss()),
        _fails(InventoryAdjustmentFailure.permissionDenied));
    await unchanged();
  });
  for (final mismatch in [
    'business',
    'branch',
    'profile',
    'not-ready',
    'no-device',
    'no-installation',
    'no-context'
  ]) {
    test('rejects canonical context mismatch: $mismatch', () async {
      context = mismatch == 'no-context'
          ? null
          : _context(
              business: mismatch == 'business' ? 'foreign' : 'business',
              branch: mismatch == 'branch' ? 'foreign' : 'branch',
              profile: mismatch == 'profile' ? 'foreign' : 'profile',
              ready: mismatch != 'not-ready',
              device: mismatch == 'no-device' ? null : 'device',
              installation:
                  mismatch == 'no-installation' ? '' : 'installation');
      await expectLater(service.applyAdjustment(_loss()),
          _fails(InventoryAdjustmentFailure.invalidContext));
      await unchanged();
    });
  }
  test('rechecks persisted permissions, not caller/context permissions alone',
      () async {
    await projection(permissions: []);
    await expectLater(service.applyAdjustment(_loss()),
        _fails(InventoryAdjustmentFailure.permissionDenied));
    await unchanged();
  });
  test('revoked projection rejects stale ready context', () async {
    await projection(status: 'revoked');
    await expectLater(service.applyAdjustment(_loss()),
        _fails(InventoryAdjustmentFailure.permissionDenied));
    await unchanged();
  });
  test('inactive profile rejected', () async {
    await db
        .update(db.profiles)
        .write(const ProfilesCompanion(status: Value('inactive')));
    await expectLater(service.applyAdjustment(_loss()),
        _fails(InventoryAdjustmentFailure.invalidContext));
    await unchanged();
  });
  for (final reason
      in InventoryAdjustmentReason.values.where((r) => r.isLoss)) {
    test('${reason.code} maps positive quantity to loss -2, 10 -> 8 offline',
        () async {
      final result = await service.applyAdjustment(_loss(reason: reason));
      expect(result.resultingOnHand, 8);
      expect(result.alreadyApplied, isFalse);
      final row = await movement();
      expect(row.quantityChange, -2);
      expect(row.movementType, 'loss');
      expect(row.sourceType, 'loss');
      expect(jsonDecode(row.metadataJson!)['adjustment_reason'], reason.code);
      expect((await currentBalance()).quantityOnHand, 8);
    });
  }
  for (final invalid in [0, -2]) {
    test('loss quantity $invalid rejected without double sign conversion',
        () async {
      await expectLater(service.applyAdjustment(_loss(quantity: invalid)),
          _fails(InventoryAdjustmentFailure.invalidRequest));
      await unchanged();
    });
  }
  test('loss reason cannot be supplied to correction API', () async {
    await expectLater(
        service.applyAdjustment(
            _correction(reason: InventoryAdjustmentReason.expired)),
        _fails(InventoryAdjustmentFailure.invalidRequest));
    await unchanged();
  });
  test('manual reason cannot be supplied to loss API', () async {
    await expectLater(
        service.applyAdjustment(
            _loss(reason: InventoryAdjustmentReason.manualCorrection)),
        _fails(InventoryAdjustmentFailure.invalidRequest));
    await unchanged();
  });
  test('zero correction rejected', () async {
    await expectLater(service.applyAdjustment(_correction(delta: 0)),
        _fails(InventoryAdjustmentFailure.invalidRequest));
  });
  for (final mode in ['deleted', 'inactive', 'missing', 'foreign-business']) {
    test('product $mode rejected', () async {
      if (mode == 'deleted') {
        await db
            .update(db.products)
            .write(ProductsCompanion(deletedAt: Value(DateTime.now())));
      } else if (mode == 'inactive') {
        await db
            .update(db.products)
            .write(const ProductsCompanion(status: Value('inactive')));
      } else if (mode == 'foreign-business') {
        await db
            .into(db.businesses)
            .insert(BusinessesCompanion.insert(id: 'other', name: 'Other'));
        await db
            .update(db.products)
            .write(const ProductsCompanion(businessId: Value('other')));
      }
      await expectLater(
          service.applyAdjustment(
              _loss(product: mode == 'missing' ? 'missing' : 'product')),
          _fails(InventoryAdjustmentFailure.invalidProduct));
      await unchanged();
    });
  }
  for (final stock in [0, 3]) {
    test('stock $stock cannot cover loss 4', () async {
      await balance(quantity: stock);
      await expectLater(service.applyAdjustment(_loss(quantity: 4)),
          _fails(InventoryAdjustmentFailure.insufficientStock));
      expect((await currentBalance()).quantityOnHand, stock);
      expect(await db.select(db.localInventoryMovements).get(), isEmpty);
    });
  }
  test('missing balance rejects negative delta', () async {
    await db.delete(db.localProductStockBalances).go();
    await expectLater(service.applyAdjustment(_loss()),
        _fails(InventoryAdjustmentFailure.insufficientStock));
    expect(await db.select(db.localProductStockBalances).get(), isEmpty);
  });
  for (final reason in [
    InventoryAdjustmentReason.manualCorrection,
    InventoryAdjustmentReason.other
  ]) {
    for (final delta in [-2, 2]) {
      test('${reason.code} supports signed delta $delta', () async {
        await service
            .applyAdjustment(_correction(reason: reason, delta: delta));
        expect((await currentBalance()).quantityOnHand, 10 + delta);
        expect((await movement()).sourceType, 'manual_adjustment');
        expect((await movement()).movementType, 'manual_adjustment');
      });
    }
  }
  test('positive correction creates missing balance with NULL cost', () async {
    await db.delete(db.localProductStockBalances).go();
    await service.applyAdjustment(_correction());
    expect((await currentBalance()).quantityOnHand, 2);
    expect((await currentBalance()).quantityAvailable, 2);
    expect((await currentBalance()).quantityReserved, 0);
    expect((await currentBalance()).averageCost, isNull);
    expect((await movement()).unitCost, isNull);
  });
  for (final cost in <double?>[2500, 0, null]) {
    for (final delta in [-2, 2]) {
      test(
          'delta $delta preserves cost $cost and snapshots it, never purchase price',
          () async {
        await balance(cost: cost);
        await service.applyAdjustment(_correction(delta: delta));
        expect((await currentBalance()).averageCost, cost);
        expect((await movement()).unitCost, cost);
        expect((await db.select(db.products).getSingle()).purchasePrice, 99999);
      });
    }
  }
  test('cost snapshot immutable after later average changes and retry',
      () async {
    final first = await service.applyAdjustment(_loss());
    await db.update(db.localProductStockBalances).write(
        const LocalProductStockBalancesCompanion(averageCost: Value(3000)));
    final again = await service.applyAdjustment(_loss());
    expect(again.movementId, first.movementId);
    expect(again.unitCost, 2500);
    expect((await movement()).unitCost, 2500);
    expect((await currentBalance()).averageCost, 3000);
  });
  test('reservation retained and available recalculated', () async {
    await balance(reserved: 3);
    await service.applyAdjustment(_loss());
    expect((await currentBalance()).quantityOnHand, 8);
    expect((await currentBalance()).quantityReserved, 3);
    expect((await currentBalance()).quantityAvailable, 5);
  });
  test('cannot consume reserved stock', () async {
    await balance(reserved: 8);
    await expectLater(service.applyAdjustment(_loss(quantity: 4)),
        _fails(InventoryAdjustmentFailure.reservedStockConflict));
    await unchanged();
  });
  test('inconsistent available fails closed', () async {
    await db.update(db.localProductStockBalances).write(
        const LocalProductStockBalancesCompanion(quantityAvailable: Value(5)));
    await expectLater(service.applyAdjustment(_loss()),
        _fails(InventoryAdjustmentFailure.invalidBalance));
    await unchanged();
  });
  test('durable ledger carries actor, note, timestamps, IDs and pending state',
      () async {
    final at = DateTime.utc(2026, 9, 25, 10);
    final result = await service
        .applyAdjustment(_loss(note: 'Expired package', occurredAt: at));
    final row = await movement();
    expect(row.id, result.movementId);
    expect(row.sourceId, row.id);
    expect(row.referenceId, row.id);
    expect(row.referenceType, 'inventory_adjustment');
    expect(row.createdBy, 'profile');
    expect(row.deviceId, 'device');
    expect(row.notes, 'Expired package');
    expect(row.occurredAt.toUtc(), at);
    expect(row.idempotencyKey, 'intent');
    expect(row.localStatus, 'dirty');
    expect(row.syncStatus, 0);
    expect(row.lastSyncedAt, isNull);
    expect(row.previousStock, 10);
    expect(row.newStock, 8);
    expect((await db.select(db.products).getSingle()).stockQuantity, 987);
  });
  test(
      'one canonical inventory outbox mutation with exact ledger payload/A2 evidence',
      () async {
    await service.applyAdjustment(_loss());
    final row = await movement();
    final outbox =
        await db.customSelect('select * from local_sync_mutations').getSingle();
    final batch =
        await db.customSelect('select * from local_sync_batches').getSingle();
    expect(batch.data['domain'], 'inventory');
    expect(batch.data['status'], 'pending');
    expect(outbox.data['status'], 'pending');
    expect(outbox.data['entity_table'], 'inventory_movements');
    expect(outbox.data['entity_id'], row.id);
    expect(outbox.data['idempotency_key'], row.idempotencyKey);
    expect(outbox.data['profile_id'], 'profile');
    expect(outbox.data['app_device_id'], 'device');
    final payload = jsonDecode(outbox.data['payload_json']) as Map;
    expect(payload['id'], row.id);
    expect(payload['business_id'], 'business');
    expect(payload['branch_id'], 'branch');
    expect(payload['product_id'], 'product');
    expect(payload['movement_type'], 'loss');
    expect(payload['source_type'], 'loss');
    expect(payload['quantity_change'], -2);
    expect(payload['unit_cost'], 2500);
    expect(payload['metadata']['adjustment_reason'], 'expired');
    final observations = await InventoryBalanceReconciliationLocalDao(db)
        .getMovements(businessId: 'business', branchId: 'branch');
    expect(observations.single.canRequestAcknowledgement, isTrue);
    expect(observations.single.transportState,
        InventoryMovementTransportState.pending);
    expect(observations.single.transportEvidence, ['pending/pending']);
    expect(observations.single.acknowledgementOperation.idempotencyKey,
        row.idempotencyKey);
  });
  for (final table in ['local_inventory_movements', 'local_sync_mutations']) {
    test('insert failure in $table rolls back balance, movement and batch',
        () async {
      await db.customStatement(
          "CREATE TRIGGER fail_b1 BEFORE INSERT ON $table BEGIN SELECT RAISE(ABORT, 'B1 injected failure'); END");
      await expectLater(
          service.applyAdjustment(_loss()), throwsA(isA<Exception>()));
      await unchanged();
    });
  }
  test('same intent retry no duplicate movement/batch/mutation or stock change',
      () async {
    final a = await service.applyAdjustment(_loss());
    final b = await service.applyAdjustment(_loss());
    expect(b.alreadyApplied, isTrue);
    expect(a.movementId, b.movementId);
    expect((await currentBalance()).quantityOnHand, 8);
    expect(await db.select(db.localInventoryMovements).get(), hasLength(1));
    expect(await db.customSelect('select * from local_sync_batches').get(),
        hasLength(1));
    expect(await db.customSelect('select * from local_sync_mutations').get(),
        hasLength(1));
  });
  for (final field in ['product', 'quantity', 'reason', 'note', 'occurredAt']) {
    test('same key different $field is explicit idempotency conflict',
        () async {
      await service.applyAdjustment(_loss());
      await db.into(db.products).insert(ProductsCompanion.insert(
          id: 'other-product',
          businessId: const Value('business'),
          name: 'Other',
          salePrice: 1));
      await expectLater(
          service.applyAdjustment(_loss(
              product: field == 'product' ? 'other-product' : 'product',
              quantity: field == 'quantity' ? 3 : 2,
              reason: field == 'reason'
                  ? InventoryAdjustmentReason.gift
                  : InventoryAdjustmentReason.expired,
              note: field == 'note' ? 'different' : null,
              occurredAt: field == 'occurredAt' ? DateTime.utc(2020) : null)),
          _fails(InventoryAdjustmentFailure.idempotencyConflict));
      expect((await currentBalance()).quantityOnHand, 8);
      expect(await db.customSelect('select * from local_sync_mutations').get(),
          hasLength(1));
    });
  }
  test(
      'concurrent same intent through different service instances applies once',
      () async {
    final other = InventoryAdjustmentService(
        database: db, loadCurrentContext: () async => context);
    final results = await Future.wait(
        [service.applyAdjustment(_loss()), other.applyAdjustment(_loss())]);
    expect(results.map((r) => r.movementId).toSet(), hasLength(1));
    expect((await currentBalance()).quantityOnHand, 8);
    expect(await db.customSelect('select * from local_sync_mutations').get(),
        hasLength(1));
  });
  test('concurrent distinct intents cannot oversell', () async {
    final results = await Future.wait(['a', 'b'].map((key) async {
      try {
        await service.applyAdjustment(_loss(key: key, quantity: 6));
        return true;
      } on InventoryAdjustmentException catch (e) {
        expect(e.kind, InventoryAdjustmentFailure.insufficientStock);
        return false;
      }
    }));
    expect(results.where((v) => v), hasLength(1));
    expect((await currentBalance()).quantityOnHand, 4);
  });
  test('existing raw DAO ISO balance/context timestamps remain readable',
      () async {
    const iso = '2026-09-25T10:00:00.123Z';
    for (final table in ['products', 'profiles', 'businesses', 'branches']) {
      await db.customStatement(
          'update $table set created_at = ?, updated_at = ?', [iso, iso]);
    }
    await db.customStatement(
        'update local_product_stock_balances set created_at = ?, updated_at = ?, last_movement_at = ?',
        [iso, iso, iso]);
    final result = await service.applyAdjustment(_loss());
    expect(result.resultingOnHand, 8);
    expect(
        (await db
                .customSelect(
                    'select quantity_on_hand from local_product_stock_balances')
                .getSingle())
            .data['quantity_on_hand'],
        8);
  });

  test('retry after sync ISO timestamp updates never re-enqueues', () async {
    final first = await service.applyAdjustment(_loss());
    await db.customStatement(
        "update local_inventory_movements set sync_status=1, local_status='synced', updated_at=?, last_synced_at=?",
        ['2026-09-26T00:00:00Z', '2026-09-26T00:00:00Z']);
    await db
        .customStatement("update local_sync_mutations set status='applied'");
    final retry = await service.applyAdjustment(_loss());
    expect(retry.movementId, first.movementId);
    expect(retry.alreadyApplied, isTrue);
    expect((await currentBalance()).quantityOnHand, 8);
    final mutations =
        await db.customSelect('select status from local_sync_mutations').get();
    expect(mutations, hasLength(1));
    expect(mutations.single.data['status'], 'applied');
  });

  test('outbox key belonging to another operation is never overwritten',
      () async {
    await db.customStatement('''insert into local_sync_mutations
      (id,client_mutation_id,client_sequence,business_id,entity_table,entity_id,operation,payload_json,idempotency_key,created_at,updated_at)
      values ('foreign','foreign',1,'business','products','product','insert','{}','intent',?,?)''',
        ['2026-09-25T00:00:00Z', '2026-09-25T00:00:00Z']);
    await expectLater(service.applyAdjustment(_loss()),
        _fails(InventoryAdjustmentFailure.idempotencyConflict));
    expect((await currentBalance()).quantityOnHand, 10);
    expect(await db.select(db.localInventoryMovements).get(), isEmpty);
    final rows = await db
        .customSelect('select entity_table from local_sync_mutations')
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.data['entity_table'], 'products');
  });

  test('idempotency key cannot be reused in a different authorized branch',
      () async {
    await service.applyAdjustment(_loss());
    await db.into(db.branches).insert(BranchesCompanion.insert(
        id: 'other-branch', businessId: 'business', name: 'Other'));
    await AuthorizedOperationalContextLocalDao(db).replaceContext(
        AuthorizedOperationalContextProjection(
            profileId: 'profile',
            businessId: 'business',
            branchId: 'other-branch',
            effectivePermissions: const ['inventory.adjust'],
            effectiveRoles: const [],
            applicableMembershipIds: const ['membership'],
            authorizationValidatedAt: DateTime.utc(2026, 9, 25),
            snapshotId: 'other'));
    context = _context(branch: 'other-branch');
    await expectLater(
        service.applyAdjustment(const InventoryAdjustmentRequest.loss(
            profileId: 'profile',
            businessId: 'business',
            branchId: 'other-branch',
            productId: 'product',
            reason: InventoryAdjustmentReason.expired,
            quantity: 2,
            idempotencyKey: 'intent')),
        _fails(InventoryAdjustmentFailure.idempotencyConflict));
    expect((await currentBalance()).quantityOnHand, 8);
  });

  test('stock watcher observes committed delta', () async {
    final stream = StreamIterator(ProductStockBalanceLocalDao(db)
        .watchProductsWithLocalStock(
            businessId: 'business', branchId: 'branch'));
    addTearDown(stream.cancel);
    await stream.moveNext();
    expect(stream.current.single['quantity_on_hand'], 10);
    await service.applyAdjustment(_loss());
    await stream.moveNext().timeout(const Duration(seconds: 3));
    expect(stream.current.single['quantity_on_hand'], 8);
  });
  test('valuation inputs react with unchanged cost', () async {
    final stream = StreamIterator(ProductStockBalanceLocalDao(db)
        .watchBranchInventoryValuationInputs(
            businessId: 'business', branchId: 'branch'));
    addTearDown(stream.cancel);
    await stream.moveNext();
    await service.applyAdjustment(_loss());
    await stream.moveNext().timeout(const Duration(seconds: 3));
    expect(
        stream.current.single['quantity_on_hand'] *
            stream.current.single['stock_average_cost'],
        20000);
  });
  test('alerts react normal to low-stock to out-of-stock', () async {
    final stream = StreamIterator(ProductStockBalanceLocalDao(db)
        .watchInventoryAlertCounts(businessId: 'business', branchId: 'branch'));
    addTearDown(stream.cancel);
    await stream.moveNext();
    expect(stream.current['low_stock_count'], 0);
    await service.applyAdjustment(_loss(quantity: 7));
    await stream.moveNext().timeout(const Duration(seconds: 3));
    expect(stream.current['low_stock_count'], 1);
    await service.applyAdjustment(_loss(key: 'second', quantity: 3));
    await stream.moveNext().timeout(const Duration(seconds: 3));
    expect(stream.current['out_of_stock_count'], 1);
    expect(stream.current['low_stock_count'], 0);
  });
}

AppCurrentContext _context(
        {String business = 'business',
        String branch = 'branch',
        String profile = 'profile',
        bool ready = true,
        String? device = 'device',
        String installation = 'installation',
        List<String> permissions = const ['inventory.adjust']}) =>
    AppCurrentContext(
        businessId: business,
        branchId: branch,
        profileId: profile,
        installationId: installation,
        appDeviceId: device,
        isOnline: false,
        authorizationContextReady: ready,
        permissions: AppPermissionSet(permissions.toSet()));
InventoryAdjustmentRequest _loss(
        {int quantity = 2,
        InventoryAdjustmentReason reason = InventoryAdjustmentReason.expired,
        String product = 'product',
        String key = 'intent',
        String? note,
        DateTime? occurredAt}) =>
    InventoryAdjustmentRequest.loss(
        profileId: 'profile',
        businessId: 'business',
        branchId: 'branch',
        productId: product,
        reason: reason,
        quantity: quantity,
        idempotencyKey: key,
        note: note,
        occurredAt: occurredAt);
InventoryAdjustmentRequest _correction(
        {int delta = 2,
        InventoryAdjustmentReason reason =
            InventoryAdjustmentReason.manualCorrection}) =>
    InventoryAdjustmentRequest.correction(
        profileId: 'profile',
        businessId: 'business',
        branchId: 'branch',
        productId: 'product',
        reason: reason,
        delta: delta,
        idempotencyKey: 'intent');
Matcher _fails(InventoryAdjustmentFailure kind) => throwsA(
    isA<InventoryAdjustmentException>().having((e) => e.kind, 'kind', kind));
