import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../../../../core/models/product_sale_mode.dart';
import '../../../../core/utils/app_uuid.dart';
import '../../application/inventory_cost_basis.dart';
import '../../application/purchase_money.dart';

class PurchaseLocalDao {
  PurchaseLocalDao(this._db);

  final AppDatabase _db;

  Future<Map<String, dynamic>?> getPurchasePaymentBasisRow({
    required String purchaseId,
    required String businessId,
    required String branchId,
  }) async {
    final rows = await _db.customSelect('''
      select id, total_cents, financial_finalized_at, monetary_contract_version
      from purchases
      where id = ? and business_id = ? and branch_id = ?
        and deleted_at is null
      limit 1
    ''', variables: [
      Variable<String>(purchaseId),
      Variable<String>(businessId),
      Variable<String>(branchId),
    ], readsFrom: {
      _db.purchases
    }).get();
    return rows.isEmpty ? null : rows.single.data;
  }

  Future<Map<String, dynamic>> getRequiredProductSnapshot({
    required String businessId,
    required String productId,
    ProductSaleMode expectedSaleMode = ProductSaleMode.unit,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        business_id,
        name,
        barcode,
        sale_price,
        purchase_price,
        sale_mode
      from products
      where id = ?
        and business_id = ?
        and deleted_at is null
        and sale_mode = ?
      limit 1
      ''',
      variables: [
        Variable<String>(productId),
        Variable<String>(businessId),
        Variable<String>(expectedSaleMode.wireValue),
      ],
      readsFrom: {_db.products},
    ).get();

    if (rows.isEmpty) {
      throw StateError('Producto local no encontrado: $productId');
    }

    return rows.first.data;
  }

  Future<Map<String, dynamic>?> getLocalStockBalance({
    required String businessId,
    required String branchId,
    required String productId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        business_id,
        branch_id,
        product_id,
        quantity_on_hand,
        quantity_reserved,
        quantity_available,
        cost_basis_cents,
        average_cost,
        last_movement_at,
        remote_updated_at,
        last_synced_at
      from local_product_stock_balances
      where business_id = ?
        and branch_id = ?
        and product_id = ?
      limit 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(productId),
      ],
      readsFrom: {_db.localProductStockBalances},
    ).get();

    if (rows.isEmpty) {
      return null;
    }

    return rows.first.data;
  }

  Future<void> insertPurchaseWithLocalInventoryImpact({
    required Map<String, dynamic> purchase,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> inventoryMovements,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('La compra debe tener al menos un ítem.');
    }

    if (items.length != inventoryMovements.length) {
      throw ArgumentError(
        'Cada purchase_item debe tener un inventory_movement local asociado.',
      );
    }

    await _db.transaction(() async {
      await _insertPurchase(purchase);

      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        _validateWeightedLine(item, inventoryMovements[index], purchase);
        await getRequiredProductSnapshot(
          businessId: item['business_id'] as String,
          productId: item['product_id'] as String,
          expectedSaleMode: ProductSaleMode.parse(
            item['sale_mode_snapshot'] ?? 'unit',
          ),
        );
        await _insertPurchaseItem(item);
      }

      for (final movement in inventoryMovements) {
        await _insertInventoryMovement(movement);
        await _applyLocalStockMovement(movement);
      }

      final exactTotal = purchase['total_cents'];
      if (exactTotal is int) {
        final sums = await _db.customSelect('''
          select count(*) as item_count,
            count(subtotal_cents) as exact_item_count,
            coalesce(sum(subtotal_cents), 0) as total_cents
          from purchase_items where purchase_id = ? and deleted_at is null
        ''', variables: [
          Variable<String>(purchase['id'] as String)
        ]).getSingle();
        if (sums.read<int>('item_count') != items.length ||
            sums.read<int>('exact_item_count') != items.length ||
            sums.read<int>('total_cents') != exactTotal) {
          throw StateError('Purchase exact total does not match its items.');
        }
        await _db.customUpdate('''
          update purchases set total_cents = ?, financial_finalized_at = ?,
            monetary_contract_version = ? where id = ?
        ''', variables: [
          Variable<int>(exactTotal),
          Variable<DateTime>(purchase['updated_at'] as DateTime),
          Variable<String>(
              purchase['monetary_contract_version'] as String? ?? 'exact_v1'),
          Variable<String>(purchase['id'] as String),
        ], updates: {
          _db.purchases
        });
      }
    });
  }

  void _validateWeightedLine(
    Map<String, dynamic> item,
    Map<String, dynamic> movement,
    Map<String, dynamic> purchase,
  ) {
    if (item['sale_mode_snapshot'] != ProductSaleMode.weight.wireValue) return;
    final quantity = item['quantity'];
    final basis = item['cost_basis_quantity_snapshot'];
    final quote = item['unit_cost_cents'];
    final subtotal = item['subtotal_cents'];
    if (quantity is! int ||
        quote is! int ||
        subtotal is! int ||
        (basis != 500 && basis != 1000) ||
        movement['product_id'] != item['product_id'] ||
        movement['reference_id'] != item['id'] ||
        movement['source_type'] != 'purchase' ||
        movement['source_id'] != purchase['id'] ||
        movement['quantity_change'] != quantity ||
        movement['cost_effect_cents'] != subtotal ||
        movement['sale_mode_snapshot'] != ProductSaleMode.weight.wireValue) {
      throw StateError('Weighted purchase item/movement snapshots mismatch.');
    }
    final expected = purchaseBasisLineTotalCents(
      quotedCostCents: BigInt.from(quote),
      quantity: quantity,
      costBasisQuantity: basis as int,
    );
    if (expected != BigInt.from(subtotal)) {
      throw StateError('Weighted purchase subtotal does not match W2A.');
    }
  }

  Future<void> _insertPurchase(Map<String, dynamic> purchase) async {
    await _customStatement(
      '''
      insert into purchases (
        id,
        business_id,
        branch_id,
        supplier_id,
        user_id,
        total,
        status,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at,
        invoice_photo_url,
        processing_status,
        supplier_name,
        idempotency_key,
        local_status,
        metadata_json,
        version,
        sync_status
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        purchase['id'],
        purchase['business_id'],
        purchase['branch_id'],
        purchase['supplier_id'],
        purchase['user_id'],
        purchase['total'],
        purchase['status'],
        purchase['created_at'],
        purchase['updated_at'],
        purchase['deleted_at'],
        purchase['last_synced_at'],
        purchase['invoice_photo_url'],
        purchase['processing_status'],
        purchase['supplier_name'],
        purchase['idempotency_key'],
        purchase['local_status'],
        jsonEncode(purchase['metadata'] ?? {}),
        purchase['version'],
        purchase['sync_status'],
      ],
    );
  }

  Future<void> _insertPurchaseItem(Map<String, dynamic> item) async {
    await _customStatement(
      '''
      insert into purchase_items (
        id,
        purchase_id,
        business_id,
        branch_id,
        product_id,
        quantity,
        sale_mode_snapshot,
        cost_basis_quantity_snapshot,
        unit_cost,
        subtotal,
        unit_cost_cents,
        subtotal_cents,
        idempotency_key,
        local_status,
        metadata_json,
        version,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at,
        sync_status
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        item['id'],
        item['purchase_id'],
        item['business_id'],
        item['branch_id'],
        item['product_id'],
        item['quantity'],
        item['sale_mode_snapshot'] ?? 'unit',
        item['cost_basis_quantity_snapshot'] ?? 1,
        item['unit_cost'],
        item['subtotal'],
        item['unit_cost_cents'],
        item['subtotal_cents'],
        item['idempotency_key'],
        item['local_status'],
        jsonEncode(item['metadata'] ?? {}),
        item['version'],
        item['created_at'],
        item['updated_at'],
        item['deleted_at'],
        item['last_synced_at'],
        item['sync_status'],
      ],
    );
  }

  Future<void> _insertInventoryMovement(
    Map<String, dynamic> movement,
  ) async {
    await _customStatement(
      '''
      insert into local_inventory_movements (
        id,
        business_id,
        branch_id,
        product_id,
        movement_type,
        quantity_change,
        cost_effect_cents,
        unit_cost,
        source_type,
        source_id,
        reference_type,
        reference_id,
        notes,
        idempotency_key,
        sync_status,
        local_status,
        version,
        occurred_at,
        metadata_json,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        movement['id'],
        movement['business_id'],
        movement['branch_id'],
        movement['product_id'],
        movement['movement_type'],
        movement['quantity_change'],
        movement['cost_effect_cents'],
        movement['unit_cost'],
        movement['source_type'],
        movement['source_id'],
        movement['reference_type'],
        movement['reference_id'],
        movement['notes'],
        movement['idempotency_key'],
        movement['sync_status'],
        movement['local_status'],
        movement['version'],
        movement['occurred_at'],
        jsonEncode(movement['metadata'] ?? {}),
        movement['created_at'],
        movement['updated_at'],
        movement['deleted_at'],
        movement['last_synced_at'],
      ],
    );
  }

  Future<void> _applyLocalStockMovement(
    Map<String, dynamic> movement,
  ) async {
    final businessId = _requiredString(movement, 'business_id');
    final branchId = _requiredString(movement, 'branch_id');
    final productId = _requiredString(movement, 'product_id');
    final quantityChange = _requiredInt(movement, 'quantity_change');
    final unitCost = _optionalDouble(movement, 'unit_cost');
    final now = _requiredDate(movement, 'updated_at');
    final currentBalance = await getLocalStockBalance(
      businessId: businessId,
      branchId: branchId,
      productId: productId,
    );

    if (movement['sale_mode_snapshot'] == ProductSaleMode.weight.wireValue) {
      final incomingCost = _requiredInt(movement, 'cost_effect_cents');
      final before = InventoryCostBasisState(
        quantity: BigInt.from(
          currentBalance == null
              ? 0
              : _requiredInt(currentBalance, 'quantity_on_hand'),
        ),
        costBasisCents: currentBalance?['cost_basis_cents'] is int
            ? BigInt.from(currentBalance!['cost_basis_cents'] as int)
            : null,
      );
      final receipt = applyCostedReceipt(
        before: before,
        incomingQuantity: BigInt.from(quantityChange),
        incomingCostCents: BigInt.from(incomingCost),
      );
      if (currentBalance != null) {
        final updatedRows = await _db.customUpdate(
            '''
          update local_product_stock_balances
          set quantity_on_hand = ?, quantity_available = quantity_available + ?,
              cost_basis_cents = ?, sync_status = 'dirty',
              updated_at = ?, last_movement_at = ?
          where business_id = ? and branch_id = ? and product_id = ?
        ''',
            variables: normalizeSqliteParameters([
              receipt.after.quantity.toInt(),
              quantityChange,
              receipt.after.costBasisCents?.toInt(),
              now,
              _requiredDate(movement, 'occurred_at'),
              businessId,
              branchId,
              productId,
            ])
                .map<Variable<Object>>((value) => Variable<Object>(value))
                .toList(),
            updates: {_db.localProductStockBalances});
        if (updatedRows != 1) {
          throw StateError('El balance local cambió durante la recepción.');
        }
      } else {
        await _db.into(_db.localProductStockBalances).insert(
              LocalProductStockBalancesCompanion.insert(
                id: AppUuid.v7(),
                businessId: businessId,
                branchId: branchId,
                productId: productId,
                quantityOnHand: Value(receipt.after.quantity.toInt()),
                quantityReserved: const Value(0),
                quantityAvailable: Value(receipt.after.quantity.toInt()),
                costBasisCents: Value(receipt.after.costBasisCents?.toInt()),
                lastMovementAt: Value(_requiredDate(movement, 'occurred_at')),
                syncStatus: const Value('dirty'),
                metadataJson: Value(jsonEncode({
                  'source': 'purchase_local_dao',
                  'created_from_local_purchase_movement': movement['id'],
                })),
                createdAt: Value(now),
                updatedAt: Value(now),
              ),
            );
      }
      return;
    }

    if (currentBalance != null) {
      final oldQuantity = _requiredInt(currentBalance, 'quantity_on_hand');
      final oldAverageCost = _optionalDouble(currentBalance, 'average_cost');
      final newAverageCost = _nextAverageCost(
        oldQuantity: oldQuantity,
        oldAverageCost: oldAverageCost,
        quantityChange: quantityChange,
        unitCost: unitCost,
      );

      final updatedRows = await _db.customUpdate(
        '''
        update local_product_stock_balances
        set
          quantity_on_hand = quantity_on_hand + ?,
          quantity_available = quantity_available + ?,
          average_cost = ?,
          updated_at = ?,
          last_movement_at = ?
        where business_id = ?
          and branch_id = ?
          and product_id = ?
        ''',
        variables: normalizeSqliteParameters([
          quantityChange,
          quantityChange,
          newAverageCost,
          now,
          _requiredDate(movement, 'occurred_at'),
          businessId,
          branchId,
          productId,
        ]).map<Variable<Object>>((value) => Variable<Object>(value)).toList(
              growable: false,
            ),
        updates: {_db.localProductStockBalances},
      );

      if (updatedRows != 1) {
        throw StateError(
          'El balance local cambió mientras se aplicaba el movimiento.',
        );
      }

      return;
    }

    await _db.into(_db.localProductStockBalances).insert(
          LocalProductStockBalancesCompanion.insert(
            id: AppUuid.v7(),
            businessId: businessId,
            branchId: branchId,
            productId: productId,
            quantityOnHand: Value(quantityChange),
            quantityReserved: const Value(0),
            quantityAvailable: Value(quantityChange),
            averageCost: Value(
              _nextAverageCost(
                oldQuantity: 0,
                oldAverageCost: null,
                quantityChange: quantityChange,
                unitCost: unitCost,
              ),
            ),
            lastMovementAt: Value(
              _requiredDate(movement, 'occurred_at'),
            ),
            syncStatus: const Value('dirty'),
            metadataJson: Value(
              jsonEncode({
                'source': 'purchase_local_dao',
                'created_from_local_purchase_movement': movement['id'],
              }),
            ),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<List<Map<String, dynamic>>> getPendingDirtyPurchases({
    required String businessId,
    required String branchId,
    int limit = 10,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        business_id,
        branch_id,
        supplier_id,
        user_id,
        total,
        status,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at,
        invoice_photo_url,
        processing_status,
        supplier_name,
        idempotency_key,
        local_status,
        metadata_json,
        version,
        sync_status
      from purchases
      where business_id = ?
        and branch_id = ?
        and deleted_at is null
        and (
          local_status = 'dirty'
          or sync_status != 0
        )
      order by created_at asc
      limit ?
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<int>(limit),
      ],
      readsFrom: {_db.purchases},
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Future<Map<String, dynamic>?> getPendingDirtyPurchase({
    required String businessId,
    required String branchId,
    required String purchaseId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id, business_id, branch_id, supplier_id, user_id, total, status,
        created_at, updated_at, deleted_at, last_synced_at, invoice_photo_url,
        processing_status, supplier_name, idempotency_key, local_status,
        metadata_json, version, sync_status
      from purchases
      where id = ? and business_id = ? and branch_id = ?
        and deleted_at is null
        and (local_status = 'dirty' or sync_status != 0)
      limit 1
      ''',
      variables: [
        Variable<String>(purchaseId),
        Variable<String>(businessId),
        Variable<String>(branchId),
      ],
      readsFrom: {_db.purchases},
    ).get();
    return rows.isEmpty ? null : rows.first.data;
  }

  Future<List<Map<String, dynamic>>> getPurchaseItemsForSync({
    required String purchaseId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        purchase_id,
        business_id,
        branch_id,
        product_id,
        quantity,
        sale_mode_snapshot,
        cost_basis_quantity_snapshot,
        unit_cost,
        subtotal,
        unit_cost_cents,
        subtotal_cents,
        idempotency_key,
        local_status,
        metadata_json,
        version,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at,
        sync_status
      from purchase_items
      where purchase_id = ?
        and deleted_at is null
      order by created_at asc
      ''',
      variables: [
        Variable<String>(purchaseId),
      ],
      readsFrom: {_db.purchaseItems},
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Future<List<Map<String, dynamic>>>
      getPurchaseInventoryMovementsForSyncContext({
    required String purchaseId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        business_id,
        branch_id,
        product_id,
        movement_type,
        quantity_change,
        unit_cost,
        source_type,
        source_id,
        reference_type,
        reference_id,
        notes,
        idempotency_key,
        sync_status,
        local_status,
        version,
        occurred_at,
        metadata_json,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at
      from local_inventory_movements
      where source_type = 'purchase'
        and source_id = ?
        and deleted_at is null
      order by created_at asc
      ''',
      variables: [
        Variable<String>(purchaseId),
      ],
      readsFrom: {_db.localInventoryMovements},
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Future<int> reconcileCompletedPurchasesFromOutbox({
    required String businessId,
    String? branchId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select distinct sm.entity_id as purchase_id
      from local_sync_mutations sm
      join local_sync_batches sb
        on sb.id = sm.local_sync_batch_id
      where sm.business_id = ?
        and sm.entity_table = 'purchases'
        and sb.status = 'completed'
        and (
          ? is null
          or sm.branch_id = ?
        )
      order by sm.created_at desc
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(branchId),
      ],
      readsFrom: {
        _db.localSyncMutations,
        _db.localSyncBatches,
      },
    ).get();

    var reconciled = 0;

    for (final row in rows) {
      final purchaseId = row.data['purchase_id']?.toString();

      if (purchaseId == null || purchaseId.trim().isEmpty) {
        continue;
      }

      await markPurchaseAndChildrenSyncedAfterUpload(
        purchaseId: purchaseId,
      );
      reconciled++;
    }

    return reconciled;
  }

  Future<void> markPurchaseAndChildrenSyncedAfterUpload({
    required String purchaseId,
  }) async {
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      await _customStatement(
        '''
        update purchases
        set
          sync_status = ?,
          local_status = 'synced',
          updated_at = ?,
          last_synced_at = ?
        where id = ?
        ''',
        [
          SyncStatus.synced.index,
          now,
          now,
          purchaseId,
        ],
      );

      await _customStatement(
        '''
        update purchase_items
        set
          sync_status = ?,
          local_status = 'synced',
          updated_at = ?,
          last_synced_at = ?
        where purchase_id = ?
        ''',
        [
          SyncStatus.synced.index,
          now,
          now,
          purchaseId,
        ],
      );

      // Los movimientos locales de compra NO se suben por inventory upload.
      // El backend aplica inventario remoto desde purchase_items.
      await _customStatement(
        '''
        update local_inventory_movements
        set
          sync_status = ?,
          local_status = 'synced',
          updated_at = ?,
          last_synced_at = ?
        where source_type = 'purchase'
          and source_id = ?
        ''',
        [
          SyncStatus.synced.index,
          now,
          now,
          purchaseId,
        ],
      );
    });
  }

  Future<void> _customStatement(
    String sql,
    List<Object?> parameters,
  ) async {
    await _db.customStatement(
      sql,
      normalizeSqliteParameters(parameters),
    );
  }

  String _requiredString(Map<String, dynamic> map, String key) {
    final value = map[key];

    if (value == null || value.toString().trim().isEmpty) {
      throw ArgumentError('Campo requerido ausente: $key');
    }

    return value.toString();
  }

  int _requiredInt(Map<String, dynamic> map, String key) {
    final value = map[key];

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    final parsed = int.tryParse(value?.toString() ?? '');

    if (parsed == null) {
      throw ArgumentError('Campo entero inválido: $key');
    }

    return parsed;
  }

  double? _optionalDouble(Map<String, dynamic> map, String key) {
    final value = map[key];

    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    final parsed = double.tryParse(value.toString());

    if (parsed == null) {
      throw ArgumentError('Campo decimal inválido: $key');
    }

    return parsed;
  }

  double? _nextAverageCost({
    required int oldQuantity,
    required double? oldAverageCost,
    required int quantityChange,
    required double? unitCost,
  }) {
    if (quantityChange <= 0 || unitCost == null) {
      return oldAverageCost;
    }

    if (oldQuantity <= 0 || oldAverageCost == null) {
      return _roundMoney(unitCost);
    }

    final newQuantity = oldQuantity + quantityChange;
    return _roundMoney(
      ((oldQuantity * oldAverageCost) + (quantityChange * unitCost)) /
          newQuantity,
    );
  }

  double _roundMoney(double value) => (value * 100).round() / 100;

  DateTime _requiredDate(Map<String, dynamic> map, String key) {
    final value = map[key];

    if (value is DateTime) {
      return value;
    }

    final parsed = DateTime.tryParse(value?.toString() ?? '');

    if (parsed == null) {
      throw ArgumentError('Campo DateTime inválido: $key');
    }

    return parsed;
  }
}
