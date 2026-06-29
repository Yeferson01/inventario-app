import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../models/product_stock_balance_models.dart';

class ProductStockBalanceLocalDao {
  ProductStockBalanceLocalDao(this._db);

  final AppDatabase _db;

  Future<void> upsertRemoteBalance(RemoteProductStockBalance balance) async {
    final now = DateTime.now().toUtc();

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
      on conflict(id) do update set
        quantity_on_hand = excluded.quantity_on_hand,
        quantity_reserved = excluded.quantity_reserved,
        quantity_available = excluded.quantity_available,
        average_cost = excluded.average_cost,
        last_movement_at = excluded.last_movement_at,
        remote_updated_at = excluded.remote_updated_at,
        last_synced_at = excluded.last_synced_at,
        sync_status = excluded.sync_status,
        metadata_json = excluded.metadata_json,
        updated_at = excluded.updated_at
      ''',
      [
        balance.localId,
        balance.businessId,
        balance.branchId,
        balance.productId,
        balance.quantityOnHand,
        balance.quantityReserved,
        balance.quantityAvailable,
        balance.averageCost,
        balance.lastMovementAt,
        balance.remoteUpdatedAt,
        now,
        'synced',
        jsonEncode(balance.toJson()),
        now,
        now,
      ],
    );
  }

  Future<Map<String, dynamic>?> getProductBalance({
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
        last_synced_at,
        sync_status,
        metadata_json,
        created_at,
        updated_at
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

  Future<List<Map<String, dynamic>>> getBranchBalances({
    required String businessId,
    required String branchId,
    int limit = 100,
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
        last_synced_at,
        sync_status,
        metadata_json,
        created_at,
        updated_at
      from local_product_stock_balances
      where business_id = ?
        and branch_id = ?
      order by remote_updated_at desc nulls last, updated_at desc
      limit ?
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<int>(limit),
      ],
      readsFrom: {_db.localProductStockBalances},
    ).get();

    return rows.map((row) => row.data).toList();
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
}
