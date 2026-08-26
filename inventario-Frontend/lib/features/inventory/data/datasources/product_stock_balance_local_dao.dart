import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../../../../core/utils/app_uuid.dart';
import '../../../../core/utils/barcode_normalizer.dart';
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
        remote_balance_id,
        remote_quantity_on_hand,
        remote_quantity_reserved,
        remote_quantity_available,
        remote_average_cost,
        last_movement_at,
        remote_updated_at,
        last_synced_at,
        sync_status,
        metadata_json,
        created_at,
        updated_at
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(business_id, branch_id, product_id) do update set
        quantity_on_hand = excluded.quantity_on_hand,
        quantity_reserved = excluded.quantity_reserved,
        quantity_available = excluded.quantity_available,
        average_cost = excluded.average_cost,
        remote_balance_id = excluded.remote_balance_id,
        remote_quantity_on_hand = excluded.remote_quantity_on_hand,
        remote_quantity_reserved = excluded.remote_quantity_reserved,
        remote_quantity_available = excluded.remote_quantity_available,
        remote_average_cost = excluded.remote_average_cost,
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
        balance.remoteBalanceId,
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

  Future<void> upsertRemoteBaseByScope({
    required String businessId,
    required String branchId,
    required String productId,
    required String remoteBalanceId,
    required int remoteQuantityOnHand,
    required int remoteQuantityReserved,
    required int remoteQuantityAvailable,
    double? remoteAverageCost,
    DateTime? remoteUpdatedAt,
    String? remoteSnapshotId,
    DateTime? deletedAt,
  }) async {
    final now = DateTime.now().toUtc();

    await _customStatement(
      '''
      insert into local_product_stock_balances (
        id,
        business_id,
        branch_id,
        product_id,
        remote_balance_id,
        remote_quantity_on_hand,
        remote_quantity_reserved,
        remote_quantity_available,
        remote_average_cost,
        remote_updated_at,
        remote_snapshot_id,
        deleted_at,
        created_at,
        updated_at
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(business_id, branch_id, product_id) do update set
        remote_balance_id = excluded.remote_balance_id,
        remote_quantity_on_hand = excluded.remote_quantity_on_hand,
        remote_quantity_reserved = excluded.remote_quantity_reserved,
        remote_quantity_available = excluded.remote_quantity_available,
        remote_average_cost = excluded.remote_average_cost,
        remote_updated_at = excluded.remote_updated_at,
        remote_snapshot_id = excluded.remote_snapshot_id,
        deleted_at = excluded.deleted_at,
        updated_at = excluded.updated_at
      ''',
      [
        AppUuid.v7(),
        businessId,
        branchId,
        productId,
        remoteBalanceId,
        remoteQuantityOnHand,
        remoteQuantityReserved,
        remoteQuantityAvailable,
        remoteAverageCost,
        remoteUpdatedAt,
        remoteSnapshotId,
        deletedAt,
        now,
        now,
      ],
    );
  }

  Future<void> stageRemoteBaseByScope({
    required String businessId,
    required String branchId,
    required String productId,
    required String remoteBalanceId,
    required int remoteQuantityOnHand,
    required int remoteQuantityReserved,
    required int remoteQuantityAvailable,
    required double? remoteAverageCost,
    required DateTime remoteUpdatedAt,
    required String remoteSnapshotId,
    required bool remoteTombstone,
    required DateTime? remoteDeletedAt,
  }) async {
    final now = DateTime.now().toUtc();
    final metadata = jsonEncode({
      'remote_record_state': remoteTombstone ? 'tombstone' : 'present',
      'remote_deleted_at': remoteDeletedAt?.toIso8601String(),
    });
    await _customStatement(
      '''
      insert into local_product_stock_balances (
        id, business_id, branch_id, product_id, remote_balance_id,
        remote_quantity_on_hand, remote_quantity_reserved,
        remote_quantity_available, remote_average_cost, remote_updated_at,
        remote_snapshot_id, metadata_json, created_at, updated_at
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(business_id, branch_id, product_id) do update set
        remote_balance_id = excluded.remote_balance_id,
        remote_quantity_on_hand = excluded.remote_quantity_on_hand,
        remote_quantity_reserved = excluded.remote_quantity_reserved,
        remote_quantity_available = excluded.remote_quantity_available,
        remote_average_cost = excluded.remote_average_cost,
        remote_updated_at = excluded.remote_updated_at,
        remote_snapshot_id = excluded.remote_snapshot_id,
        metadata_json = excluded.metadata_json,
        updated_at = excluded.updated_at
      ''',
      [
        AppUuid.v7(),
        businessId,
        branchId,
        productId,
        remoteBalanceId,
        remoteQuantityOnHand,
        remoteQuantityReserved,
        remoteQuantityAvailable,
        remoteAverageCost,
        remoteUpdatedAt.millisecondsSinceEpoch,
        remoteSnapshotId,
        metadata,
        now.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getScopeBalances({
    required String businessId,
    required String branchId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select * from local_product_stock_balances
      where business_id = ? and branch_id = ?
      order by product_id
      ''',
      variables: [Variable<String>(businessId), Variable<String>(branchId)],
      readsFrom: {_db.localProductStockBalances},
    ).get();
    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }

  Future<void> finalizeOperativeBalance({
    required String businessId,
    required String branchId,
    required String productId,
    required int quantityOnHand,
    required int quantityReserved,
    required int quantityAvailable,
    required double? averageCost,
    required DateTime? lastMovementAt,
    required DateTime? deletedAt,
  }) async {
    final now = DateTime.now().toUtc();
    await _customStatement(
      '''
      update local_product_stock_balances
      set quantity_on_hand = ?, quantity_reserved = ?, quantity_available = ?,
          average_cost = ?, last_movement_at = ?, deleted_at = ?,
          sync_status = 'synced', last_synced_at = ?, updated_at = ?
      where business_id = ? and branch_id = ? and product_id = ?
      ''',
      [
        quantityOnHand,
        quantityReserved,
        quantityAvailable,
        averageCost,
        lastMovementAt?.millisecondsSinceEpoch,
        deletedAt?.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
        businessId,
        branchId,
        productId,
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
        remote_balance_id,
        remote_quantity_on_hand,
        remote_quantity_reserved,
        remote_quantity_available,
        remote_average_cost,
        last_movement_at,
        remote_updated_at,
        remote_snapshot_id,
        last_synced_at,
        sync_status,
        metadata_json,
        created_at,
        updated_at
        ,deleted_at
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
    String searchTerm = '',
    int? limit = 100,
  }) async {
    final search = _ProductStockSearch.from(searchTerm);
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
       and b.deleted_at is null
      where p.business_id = ?
        and p.status = 'active'
        and p.deleted_at is null
        ${search.whereClause}
      order by
        ${search.orderByPrefix}
        lower(p.name) asc
      $limitClause
      ''',
      variables: [
        Variable<String>(branchId),
        Variable<String>(branchId),
        Variable<String>(businessId),
        ...search.variables,
        if (limit != null) Variable<int>(limit),
      ],
      readsFrom: {
        _db.products,
        _db.localProductStockBalances,
        if (search.isActive) _db.localProductBarcodes,
      },
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Stream<List<Map<String, dynamic>>> watchProductsWithLocalStock({
    required String businessId,
    required String branchId,
    String searchTerm = '',
    int? limit = 100,
  }) {
    final search = _ProductStockSearch.from(searchTerm);
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
           and b.deleted_at is null
          where p.business_id = ?
            and p.status = 'active'
            and p.deleted_at is null
            ${search.whereClause}
          order by
            ${search.orderByPrefix}
            lower(p.name) asc
          $limitClause
          ''',
          variables: [
            Variable<String>(branchId),
            Variable<String>(branchId),
            Variable<String>(businessId),
            ...search.variables,
            if (limit != null) Variable<int>(limit),
          ],
          readsFrom: {
            _db.products,
            _db.localProductStockBalances,
            if (search.isActive) _db.localProductBarcodes,
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
            remote_balance_id,
            remote_quantity_on_hand,
            remote_quantity_reserved,
            remote_quantity_available,
            remote_average_cost,
            last_movement_at,
            remote_updated_at,
            remote_snapshot_id,
            last_synced_at,
            sync_status,
            metadata_json,
            created_at,
            updated_at,
            deleted_at
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
        remote_balance_id,
        remote_quantity_on_hand,
        remote_quantity_reserved,
        remote_quantity_available,
        remote_average_cost,
        last_movement_at,
        remote_updated_at,
        remote_snapshot_id,
        last_synced_at,
        sync_status,
        metadata_json,
        created_at,
        updated_at,
        deleted_at
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

class _ProductStockSearch {
  const _ProductStockSearch._({
    required this.whereClause,
    required this.orderByPrefix,
    required this.variables,
    required this.isActive,
  });

  factory _ProductStockSearch.from(String rawTerm) {
    final nameTerm = rawTerm.trim().toLowerCase();

    if (nameTerm.isEmpty) {
      return const _ProductStockSearch._(
        whereClause: '',
        orderByPrefix: '',
        variables: <Variable>[],
        isActive: false,
      );
    }

    final barcodeTerm = BarcodeNormalizer.normalize(rawTerm);
    final variables = <Variable>[
      Variable<String>('%${_escapeLike(nameTerm)}%'),
    ];
    var barcodeClause = '';
    var orderByPrefix = '';

    if (barcodeTerm.isNotEmpty) {
      barcodeClause = '''
        or exists (
          select 1
          from local_product_barcodes pb
          where pb.scope = 'business'
            and pb.business_id = p.business_id
            and pb.product_id = p.id
            and pb.status = 'active'
            and pb.deleted_at is null
            and pb.barcode_normalized like ? escape '\\'
        )
      ''';
      orderByPrefix = '''
        case when exists (
          select 1
          from local_product_barcodes exact_pb
          where exact_pb.scope = 'business'
            and exact_pb.business_id = p.business_id
            and exact_pb.product_id = p.id
            and exact_pb.status = 'active'
            and exact_pb.deleted_at is null
            and exact_pb.barcode_normalized = ?
        ) then 0 else 1 end,
      ''';
      variables
        ..add(Variable<String>('%${_escapeLike(barcodeTerm)}%'))
        ..add(Variable<String>(barcodeTerm));
    }

    return _ProductStockSearch._(
      whereClause: '''
        and (
          lower(p.name) like ? escape '\\'
          $barcodeClause
        )
      ''',
      orderByPrefix: orderByPrefix,
      variables: variables,
      isActive: true,
    );
  }

  final String whereClause;
  final String orderByPrefix;
  final List<Variable> variables;
  final bool isActive;

  static String _escapeLike(String value) {
    return value
        .replaceAll(r'\', r'\\')
        .replaceAll('%', r'\%')
        .replaceAll('_', r'\_');
  }
}
