import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../../../../core/utils/app_uuid.dart';

class PurchaseLocalDao {
  PurchaseLocalDao(this._db);

  final AppDatabase _db;

  Future<Map<String, dynamic>> getRequiredProductSnapshot({
    required String businessId,
    required String productId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        business_id,
        name,
        barcode,
        sale_price,
        purchase_price
      from products
      where id = ?
        and business_id = ?
        and deleted_at is null
      limit 1
      ''',
      variables: [
        Variable<String>(productId),
        Variable<String>(businessId),
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

      for (final item in items) {
        await _insertPurchaseItem(item);
      }

      for (final movement in inventoryMovements) {
        await _insertInventoryMovement(movement);
        await _applyLocalStockMovement(movement);
      }
    });
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
        unit_cost,
        subtotal,
        idempotency_key,
        local_status,
        metadata_json,
        version,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at,
        sync_status
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        item['id'],
        item['purchase_id'],
        item['business_id'],
        item['branch_id'],
        item['product_id'],
        item['quantity'],
        item['unit_cost'],
        item['subtotal'],
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
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        movement['id'],
        movement['business_id'],
        movement['branch_id'],
        movement['product_id'],
        movement['movement_type'],
        movement['quantity_change'],
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

    await _customStatement(
      '''
      insert into local_product_stock_balances (
        id,
        business_id,
        branch_id,
        product_id,
        quantity_on_hand,
        quantity_reserved,
        quantity_available,
        average_cost,
        last_movement_at,
        remote_updated_at,
        last_synced_at,
        sync_status,
        metadata_json,
        created_at,
        updated_at
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        AppUuid.v7(),
        businessId,
        branchId,
        productId,
        quantityChange,
        0,
        quantityChange,
        _nextAverageCost(
          oldQuantity: 0,
          oldAverageCost: null,
          quantityChange: quantityChange,
          unitCost: unitCost,
        ),
        movement['occurred_at'],
        null,
        null,
        'dirty',
        jsonEncode({
          'source': 'purchase_local_dao',
          'created_from_local_purchase_movement': movement['id'],
        }),
        now,
        now,
      ],
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
        unit_cost,
        subtotal,
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
