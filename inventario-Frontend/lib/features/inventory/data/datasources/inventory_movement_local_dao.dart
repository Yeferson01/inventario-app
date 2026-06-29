import 'dart:convert';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';

class InventoryMovementLocalDao {
  InventoryMovementLocalDao(this._db);

  final AppDatabase _db;

  Future<void> insertInitialMovement({
    required String id,
    required String businessId,
    required String branchId,
    required String productId,
    required String movementType,
    required int quantityChange,
    required double unitCost,
    required String sourceType,
    required String referenceType,
    required String notes,
    required String idempotencyKey,
    required DateTime occurredAt,
    required Map<String, dynamic> metadata,
  }) {
    final now = DateTime.now().toUtc();

    return _customStatement(
      _db,
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
        reference_type,
        notes,
        idempotency_key,
        sync_status,
        local_status,
        version,
        occurred_at,
        metadata_json,
        created_at,
        updated_at
      )
      values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(id) do update set
        quantity_change = excluded.quantity_change,
        unit_cost = excluded.unit_cost,
        notes = excluded.notes,
        metadata_json = excluded.metadata_json,
        updated_at = excluded.updated_at
      ''',
      [
        id,
        businessId,
        branchId,
        productId,
        movementType,
        quantityChange,
        unitCost,
        sourceType,
        referenceType,
        notes,
        idempotencyKey,
        0,
        'dirty',
        1,
        occurredAt,
        jsonEncode(metadata),
        now,
        now,
      ],
    );
  }

  Future<void> markMovementSynced({
    required String id,
  }) {
    final now = DateTime.now().toUtc();

    return _customStatement(
      _db,
      '''
      update local_inventory_movements
      set
        sync_status = 1,
        local_status = 'synced',
        last_synced_at = ?,
        updated_at = ?
      where id = ?
      ''',
      [now, now, id],
    );
  }
}

Future<void> _customStatement(
  AppDatabase db,
  String sql, [
  List<Object?> parameters = const [],
]) {
  return db.customStatement(
    sql,
    normalizeSqliteParameters(parameters),
  );
}
