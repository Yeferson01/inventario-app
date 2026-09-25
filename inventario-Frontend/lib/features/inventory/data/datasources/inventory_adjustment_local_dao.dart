import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/utils/app_uuid.dart';
import '../../../sync/application/app_context_models.dart';
import '../../../sync/data/datasources/authorized_operational_context_local_dao.dart';
import '../../application/inventory_adjustment_models.dart';

class InventoryAdjustmentLocalDao {
  InventoryAdjustmentLocalDao(this._db);
  final AppDatabase _db;

  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

  Future<void> validateContext(AppCurrentContext context) async {
    final profile = await _db.customSelect(
        'select status from profiles where id = ?',
        variables: [Variable(context.profileId!)]).getSingleOrNull();
    final business = await _db.customSelect(
        'select status, deleted_at from businesses where id = ?',
        variables: [Variable(context.businessId)]).getSingleOrNull();
    final branch = await _db.customSelect(
        'select status, deleted_at, business_id from branches where id = ?',
        variables: [Variable(context.branchId!)]).getSingleOrNull();
    if (profile?.data['status'] != 'active' ||
        business?.data['status'] != 'active' ||
        business?.data['deleted_at'] != null ||
        branch?.data['status'] != 'active' ||
        branch?.data['deleted_at'] != null ||
        branch?.data['business_id'] != context.businessId) {
      throw const InventoryAdjustmentException(
          InventoryAdjustmentFailure.invalidContext);
    }
    final permissions = await AuthorizedOperationalContextLocalDao(_db)
        .getEffectivePermissions(
            profileId: context.profileId!,
            businessId: context.businessId,
            branchId: context.branchId!);
    if (!permissions.contains('inventory.adjust')) {
      throw const InventoryAdjustmentException(
          InventoryAdjustmentFailure.permissionDenied);
    }
  }

  Future<void> validateProduct(String businessId, String productId) async {
    final product = await _db.customSelect(
        'select business_id, status, deleted_at from products where id = ?',
        variables: [Variable(productId)]).getSingleOrNull();
    if (product == null ||
        product.data['business_id'] != businessId ||
        product.data['status'] != 'active' ||
        product.data['deleted_at'] != null) {
      throw const InventoryAdjustmentException(
          InventoryAdjustmentFailure.invalidProduct);
    }
  }

  Future<LocalInventoryMovement?> findMovement(String key) async {
    final row = await _db.customSelect(
        'select * from local_inventory_movements where idempotency_key = ?',
        variables: [Variable(key)]).getSingleOrNull();
    return row == null
        ? null
        : _db.localInventoryMovements.map(_typedDates(row.data, [
            'occurred_at',
            'created_at',
            'updated_at',
            'deleted_at',
            'last_synced_at'
          ]));
  }

  Future<bool> hasOutboxKey(String key) async => (await _db.customSelect(
          'select id from local_sync_mutations where idempotency_key = ?',
          variables: [Variable(key)]).get())
      .isNotEmpty;

  Future<LocalProductStockBalance?> balance(
      String business, String branch, String product) async {
    final row = await _db.customSelect(
        'select * from local_product_stock_balances where business_id = ? and branch_id = ? and product_id = ?',
        variables: [
          Variable(business),
          Variable(branch),
          Variable(product)
        ]).getSingleOrNull();
    return row == null
        ? null
        : _db.localProductStockBalances.map(_typedDates(row.data, [
            'last_movement_at',
            'remote_updated_at',
            'last_synced_at',
            'created_at',
            'updated_at',
            'deleted_at'
          ]));
  }

  // Existing raw DAOs persist ISO timestamps; typed Drift writes use Unix seconds.
  // Adapt only the read projection. Never rewrite existing ledger/remote metadata.
  Map<String, dynamic> _typedDates(
      Map<String, dynamic> row, List<String> fields) {
    final result = Map<String, dynamic>.from(row);
    for (final key in fields) {
      final value = result[key];
      if (value is String) {
        result[key] = int.tryParse(value) ??
            DateTime.parse(value).toUtc().millisecondsSinceEpoch ~/ 1000;
      }
    }
    return result;
  }

  Future<void> writeBalance(
      {required LocalProductStockBalance? previous,
      required AppCurrentContext context,
      required String productId,
      required int onHand,
      required int reserved,
      required DateTime occurredAt,
      required DateTime now}) async {
    if (previous == null) {
      // Same companion/scope pattern as PurchaseLocalDao; unknown cost stays NULL.
      await _db.into(_db.localProductStockBalances).insert(
          LocalProductStockBalancesCompanion.insert(
              id: AppUuid.v7(),
              businessId: context.businessId,
              branchId: context.branchId!,
              productId: productId,
              quantityOnHand: Value(onHand),
              quantityReserved: Value(reserved),
              quantityAvailable: Value(onHand - reserved),
              lastMovementAt: Value(occurredAt),
              syncStatus: const Value('dirty'),
              createdAt: Value(now),
              updatedAt: Value(now)));
    } else {
      final last = previous.lastMovementAt;
      await (_db.update(_db.localProductStockBalances)
            ..where((t) => t.id.equals(previous.id)))
          .write(LocalProductStockBalancesCompanion(
              quantityOnHand: Value(onHand),
              quantityAvailable: Value(onHand - reserved),
              syncStatus: const Value('dirty'),
              lastMovementAt: Value(
                  last != null && last.isAfter(occurredAt) ? last : occurredAt),
              updatedAt: Value(now)));
    }
  }

  Future<void> insertMovement(LocalInventoryMovementsCompanion row) async {
    await _db.into(_db.localInventoryMovements).insert(row);
  }
}
