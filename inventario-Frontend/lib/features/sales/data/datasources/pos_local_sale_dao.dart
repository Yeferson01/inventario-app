import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';

class PosLocalSaleDao {
  PosLocalSaleDao(this._db);

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

  Future<Map<String, dynamic>> getRequiredStockBalance({
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
      throw StateError(
        'No hay saldo local para product=$productId branch=$branchId. '
        'Ejecuta pull de stock antes de vender offline.',
      );
    }

    return rows.first.data;
  }

  Future<void> insertSaleWithLocalInventoryImpact({
    required Map<String, dynamic> sale,
    required List<Map<String, dynamic>> items,
    required List<Map<String, dynamic>> payments,
    required List<Map<String, dynamic>> inventoryMovements,
  }) async {
    if (items.isEmpty) {
      throw ArgumentError('La venta debe tener al menos un ítem.');
    }

    if (items.length != inventoryMovements.length) {
      throw ArgumentError(
        'Cada sale_item debe tener un inventory_movement local asociado.',
      );
    }

    await _db.transaction(() async {
      await _insertSale(sale);

      for (final item in items) {
        await _insertSaleItem(item);
      }

      for (final payment in payments) {
        await _insertSalePayment(payment);
      }

      for (final movement in inventoryMovements) {
        await _insertInventoryMovement(movement);
        await _applyLocalStockMovement(movement);
      }
    });
  }

  Future<void> _insertSale(Map<String, dynamic> sale) async {
    await _customStatement(
      '''
      insert into sales (
        id,
        business_id,
        user_id,
        customer_id,
        branch_id,
        cash_register_id,
        cash_session_id,
        subtotal,
        discount_total,
        tax_total,
        total,
        payment_method,
        payment_status,
        idempotency_key,
        local_status,
        metadata_json,
        status,
        created_at,
        updated_at,
        deleted_at,
        sync_status
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        sale['id'],
        sale['business_id'],
        sale['user_id'],
        sale['customer_id'],
        sale['branch_id'],
        sale['cash_register_id'],
        sale['cash_session_id'],
        sale['subtotal'],
        sale['discount_total'],
        sale['tax_total'],
        sale['total'],
        sale['payment_method'],
        sale['payment_status'],
        sale['idempotency_key'],
        sale['local_status'],
        jsonEncode(sale['metadata'] ?? {}),
        sale['status'],
        sale['created_at'],
        sale['updated_at'],
        sale['deleted_at'],
        sale['sync_status'],
      ],
    );
  }

  Future<void> _insertSaleItem(Map<String, dynamic> item) async {
    await _customStatement(
      '''
      insert into sale_items (
        id,
        sale_id,
        product_id,
        product_name_snapshot,
        barcode_snapshot,
        quantity,
        unit_price,
        discount_total,
        tax_total,
        subtotal,
        line_total,
        metadata_json,
        created_at,
        updated_at,
        sync_status
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        item['id'],
        item['sale_id'],
        item['product_id'],
        item['product_name_snapshot'],
        item['barcode_snapshot'],
        item['quantity'],
        item['unit_price'],
        item['discount_total'],
        item['tax_total'],
        item['subtotal'],
        item['line_total'],
        jsonEncode(item['metadata'] ?? {}),
        item['created_at'],
        item['updated_at'],
        item['sync_status'],
      ],
    );
  }

  Future<void> _insertSalePayment(Map<String, dynamic> payment) async {
    await _customStatement(
      '''
      insert into sale_payments (
        id,
        business_id,
        branch_id,
        sale_id,
        payment_method,
        amount,
        currency,
        status,
        reference,
        metadata_json,
        sync_status,
        local_status,
        created_at,
        updated_at,
        deleted_at
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        payment['id'],
        payment['business_id'],
        payment['branch_id'],
        payment['sale_id'],
        payment['payment_method'],
        payment['amount'],
        payment['currency'],
        payment['status'],
        payment['reference'],
        jsonEncode(payment['metadata'] ?? {}),
        payment['sync_status'],
        payment['local_status'],
        payment['created_at'],
        payment['updated_at'],
        payment['deleted_at'],
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
    final quantityChange = _requiredInt(movement, 'quantity_change');

    final updatedRows = await _db.customUpdate(
      '''
      update local_product_stock_balances
      set
        quantity_on_hand = quantity_on_hand + ?,
        quantity_available = quantity_available + ?,
        updated_at = ?,
        last_movement_at = ?
      where business_id = ?
        and branch_id = ?
        and product_id = ?
        and quantity_on_hand + ? >= 0
        and quantity_available + ? >= 0
      ''',
      variables: [
        Variable<int>(quantityChange),
        Variable<int>(quantityChange),
        Variable<DateTime>(_requiredDate(movement, 'updated_at')),
        Variable<DateTime>(_requiredDate(movement, 'occurred_at')),
        Variable<String>(_requiredString(movement, 'business_id')),
        Variable<String>(_requiredString(movement, 'branch_id')),
        Variable<String>(_requiredString(movement, 'product_id')),
        Variable<int>(quantityChange),
        Variable<int>(quantityChange),
      ],
      updates: {_db.localProductStockBalances},
    );

    if (updatedRows != 1) {
      throw StateError(
        'No se pudo aplicar movimiento local de inventario. '
        'Posible stock insuficiente o saldo inexistente. '
        'product=${movement['product_id']} quantityChange=$quantityChange',
      );
    }
  }

  Future<List<Map<String, dynamic>>> getPendingDirtySales({
    required String businessId,
    required String branchId,
    int limit = 10,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        business_id,
        user_id,
        customer_id,
        branch_id,
        cash_register_id,
        cash_session_id,
        subtotal,
        discount_total,
        tax_total,
        total,
        payment_method,
        payment_status,
        idempotency_key,
        local_status,
        metadata_json,
        status,
        created_at,
        updated_at,
        deleted_at,
        sync_status
      from sales
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
      readsFrom: {_db.sales},
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Future<List<Map<String, dynamic>>> getSaleItemsForSync({
    required String saleId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        sale_id,
        product_id,
        product_name_snapshot,
        barcode_snapshot,
        quantity,
        unit_price,
        discount_total,
        tax_total,
        subtotal,
        line_total,
        metadata_json,
        created_at,
        updated_at,
        sync_status
      from sale_items
      where sale_id = ?
      order by created_at asc
      ''',
      variables: [
        Variable<String>(saleId),
      ],
      readsFrom: {_db.saleItems},
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Future<List<Map<String, dynamic>>> getSalePaymentsForSync({
    required String saleId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        business_id,
        branch_id,
        sale_id,
        payment_method,
        amount,
        currency,
        status,
        reference,
        metadata_json,
        sync_status,
        local_status,
        created_at,
        updated_at,
        deleted_at
      from sale_payments
      where sale_id = ?
        and deleted_at is null
      order by created_at asc
      ''',
      variables: [
        Variable<String>(saleId),
      ],
      readsFrom: {_db.salePayments},
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Future<List<Map<String, dynamic>>> getSaleInventoryMovementsForSyncContext({
    required String saleId,
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
      where source_type = 'sale'
        and source_id = ?
        and deleted_at is null
      order by created_at asc
      ''',
      variables: [
        Variable<String>(saleId),
      ],
      readsFrom: {_db.localInventoryMovements},
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Future<int> reconcileCompletedPosSalesFromOutbox({
    required String businessId,
    String? branchId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select distinct sm.entity_id as sale_id
      from local_sync_mutations sm
      join local_sync_batches sb
        on sb.id = sm.local_sync_batch_id
      where sm.business_id = ?
        and sm.entity_table = 'sales'
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
      final saleId = row.data['sale_id']?.toString();

      if (saleId == null || saleId.trim().isEmpty) {
        continue;
      }

      await markSaleAndChildrenSyncedAfterPosUpload(saleId: saleId);
      reconciled++;
    }

    return reconciled;
  }

  Future<void> markSaleAndChildrenSyncedAfterPosUpload({
    required String saleId,
  }) async {
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      await _customStatement(
        '''
        update sales
        set
          sync_status = ?,
          local_status = 'synced',
          updated_at = ?
        where id = ?
        ''',
        [
          SyncStatus.synced.index,
          now,
          saleId,
        ],
      );

      await _customStatement(
        '''
        update sale_items
        set
          sync_status = ?,
          updated_at = ?
        where sale_id = ?
        ''',
        [
          SyncStatus.synced.index,
          now,
          saleId,
        ],
      );

      await _customStatement(
        '''
        update sale_payments
        set
          sync_status = ?,
          local_status = 'synced',
          updated_at = ?
        where sale_id = ?
        ''',
        [
          SyncStatus.synced.index,
          now,
          saleId,
        ],
      );

      // Los movimientos locales de venta NO se suben por inventory upload.
      // El backend ya aplica inventario remoto desde sale_items.
      await _customStatement(
        '''
        update local_inventory_movements
        set
          sync_status = ?,
          local_status = 'synced',
          updated_at = ?,
          last_synced_at = ?
        where source_type = 'sale'
          and source_id = ?
        ''',
        [
          SyncStatus.synced.index,
          now,
          now,
          saleId,
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
