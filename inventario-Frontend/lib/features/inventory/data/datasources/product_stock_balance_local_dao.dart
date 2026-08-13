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

  Future<List<Map<String, dynamic>>> getProductsWithLocalStock({
    required String businessId,
    required String branchId,
    int? limit = 100,
  }) async {
    final limitClause = limit == null ? '' : 'limit ?';
    final rows = await _db.customSelect(
      '''
      select
        p.id as product_id,
        p.business_id as business_id,
        ? as branch_id,
        p.name as product_name,
        p.barcode as barcode,
        p.sale_price as sale_price,
        p.purchase_price as purchase_price,
        p.stock_quantity as legacy_stock_quantity,
        p.minimum_stock as legacy_minimum_stock,
        coalesce(b.quantity_on_hand, 0) as quantity_on_hand,
        coalesce(b.quantity_reserved, 0) as quantity_reserved,
        coalesce(b.quantity_available, 0) as quantity_available,
        b.average_cost as stock_average_cost,
        b.last_movement_at as last_movement_at,
        b.remote_updated_at as stock_remote_updated_at,
        b.last_synced_at as stock_last_synced_at
      from products p
      left join local_product_stock_balances b
        on b.business_id = p.business_id
       and b.branch_id = ?
       and b.product_id = p.id
      where p.business_id = ?
        and p.deleted_at is null
      order by lower(p.name) asc
      $limitClause
      ''',
      variables: [
        Variable<String>(branchId),
        Variable<String>(branchId),
        Variable<String>(businessId),
        if (limit != null) Variable<int>(limit),
      ],
      readsFrom: {
        _db.products,
        _db.localProductStockBalances,
      },
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Stream<List<Map<String, dynamic>>> watchProductsWithLocalStock({
    required String businessId,
    required String branchId,
    int? limit = 100,
  }) {
    final limitClause = limit == null ? '' : 'limit ?';

    return _db
        .customSelect(
          '''
          select
            p.id as product_id,
            p.business_id as business_id,
            ? as branch_id,
            p.name as product_name,
            p.barcode as barcode,
            p.sale_price as sale_price,
            p.purchase_price as purchase_price,
            p.stock_quantity as legacy_stock_quantity,
            p.minimum_stock as legacy_minimum_stock,
            coalesce(b.quantity_on_hand, 0) as quantity_on_hand,
            coalesce(b.quantity_reserved, 0) as quantity_reserved,
            coalesce(b.quantity_available, 0) as quantity_available,
            b.average_cost as stock_average_cost,
            b.last_movement_at as last_movement_at,
            b.remote_updated_at as stock_remote_updated_at,
            b.last_synced_at as stock_last_synced_at
          from products p
          left join local_product_stock_balances b
            on b.business_id = p.business_id
           and b.branch_id = ?
           and b.product_id = p.id
          where p.business_id = ?
            and p.deleted_at is null
          order by lower(p.name) asc
          $limitClause
          ''',
          variables: [
            Variable<String>(branchId),
            Variable<String>(branchId),
            Variable<String>(businessId),
            if (limit != null) Variable<int>(limit),
          ],
          readsFrom: {
            _db.products,
            _db.localProductStockBalances,
          },
        )
        .watch()
        .map((rows) => rows.map((row) => row.data).toList());
  }

  Stream<Map<String, dynamic>?> watchProductBalance({
    required String businessId,
    required String branchId,
    required String productId,
  }) {
    return _db
        .customSelect(
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
        )
        .watch()
        .map((rows) {
          if (rows.isEmpty) {
            return null;
          }

          return rows.first.data;
        });
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
