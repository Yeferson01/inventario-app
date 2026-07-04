import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../../../../core/utils/app_uuid.dart';

class CashSessionLocalDao {
  CashSessionLocalDao(this._db);

  final AppDatabase _db;

  Future<Map<String, dynamic>?> getCashRegisterById({
    required String id,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        business_id,
        branch_id,
        name,
        code,
        status,
        idempotency_key,
        local_status,
        sync_status,
        version,
        metadata_json,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at
      from cash_registers
      where id = ?
        and deleted_at is null
      limit 1
      ''',
      variables: [
        Variable<String>(id),
      ],
      readsFrom: {_db.cashRegisters},
    ).get();

    if (rows.isEmpty) {
      return null;
    }

    return rows.first.data;
  }

  Future<Map<String, dynamic>?> getActiveCashRegisterByCode({
    required String businessId,
    required String branchId,
    required String code,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        business_id,
        branch_id,
        name,
        code,
        status,
        idempotency_key,
        local_status,
        sync_status,
        version,
        metadata_json,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at
      from cash_registers
      where business_id = ?
        and branch_id = ?
        and code = ?
        and status = 'active'
        and deleted_at is null
      order by created_at asc
      limit 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(code),
      ],
      readsFrom: {_db.cashRegisters},
    ).get();

    if (rows.isEmpty) {
      return null;
    }

    return rows.first.data;
  }

  Future<Map<String, dynamic>?> getOpenCashSessionForRegister({
    required String cashRegisterId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        business_id,
        branch_id,
        cash_register_id,
        opened_by_profile_id,
        closed_by_profile_id,
        opened_at,
        closed_at,
        opening_cash_amount,
        closing_cash_amount,
        expected_cash_amount,
        difference_amount,
        status,
        idempotency_key,
        local_status,
        sync_status,
        version,
        metadata_json,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at
      from cash_sessions
      where cash_register_id = ?
        and status = 'open'
        and deleted_at is null
      order by opened_at desc
      limit 1
      ''',
      variables: [
        Variable<String>(cashRegisterId),
      ],
      readsFrom: {_db.cashSessions},
    ).get();

    if (rows.isEmpty) {
      return null;
    }

    return rows.first.data;
  }

  Future<Map<String, dynamic>?> getOpenCashSessionForBranch({
    required String businessId,
    required String branchId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        id,
        business_id,
        branch_id,
        cash_register_id,
        opened_by_profile_id,
        closed_by_profile_id,
        opened_at,
        closed_at,
        opening_cash_amount,
        closing_cash_amount,
        expected_cash_amount,
        difference_amount,
        status,
        idempotency_key,
        local_status,
        sync_status,
        version,
        metadata_json,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at
      from cash_sessions
      where business_id = ?
        and branch_id = ?
        and status = 'open'
        and deleted_at is null
      order by opened_at desc
      limit 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
      ],
      readsFrom: {_db.cashSessions},
    ).get();

    if (rows.isEmpty) {
      return null;
    }

    return rows.first.data;
  }

  Future<Map<String, dynamic>> createCashRegister({
    required String businessId,
    required String branchId,
    required String name,
    required String code,
    required String profileId,
    String? appDeviceId,
    String? deviceInstallationId,
    Map<String, dynamic> metadata = const {},
  }) async {
    final now = DateTime.now().toUtc();
    final id = AppUuid.v7();
    final idempotencyKey =
        '${deviceInstallationId ?? profileId}:cash_registers:$businessId:$branchId:$code';

    await _customStatement(
      '''
      insert into cash_registers (
        id,
        business_id,
        branch_id,
        name,
        code,
        status,
        idempotency_key,
        local_status,
        sync_status,
        version,
        metadata_json,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        businessId,
        branchId,
        name,
        code,
        'active',
        idempotencyKey,
        'dirty',
        SyncStatus.pendingInsert.index,
        1,
        jsonEncode({
          ...metadata,
          'source': 'cash_session_local_dao',
          'app_device_id': appDeviceId,
          'device_installation_id': deviceInstallationId,
        }),
        now,
        now,
        null,
        null,
      ],
    );

    final created = await getCashRegisterById(id: id);

    if (created == null) {
      throw StateError('No se pudo crear cash_register local.');
    }

    return created;
  }

  Future<Map<String, dynamic>> createCashSession({
    required String businessId,
    required String branchId,
    required String cashRegisterId,
    required String profileId,
    required double openingCashAmount,
    String? appDeviceId,
    String? deviceInstallationId,
    Map<String, dynamic> metadata = const {},
  }) async {
    final now = DateTime.now().toUtc();
    final id = AppUuid.v7();
    final idempotencyKey =
        '${deviceInstallationId ?? profileId}:cash_sessions:$cashRegisterId:${now.toIso8601String()}';

    await _customStatement(
      '''
      insert into cash_sessions (
        id,
        business_id,
        branch_id,
        cash_register_id,
        opened_by_profile_id,
        closed_by_profile_id,
        opened_at,
        closed_at,
        opening_cash_amount,
        closing_cash_amount,
        expected_cash_amount,
        difference_amount,
        status,
        idempotency_key,
        local_status,
        sync_status,
        version,
        metadata_json,
        created_at,
        updated_at,
        deleted_at,
        last_synced_at
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        id,
        businessId,
        branchId,
        cashRegisterId,
        profileId,
        null,
        now,
        null,
        openingCashAmount,
        null,
        null,
        null,
        'open',
        idempotencyKey,
        'dirty',
        SyncStatus.pendingInsert.index,
        1,
        jsonEncode({
          ...metadata,
          'source': 'cash_session_local_dao',
          'app_device_id': appDeviceId,
          'device_installation_id': deviceInstallationId,
        }),
        now,
        now,
        null,
        null,
      ],
    );

    final created = await getOpenCashSessionForRegister(
      cashRegisterId: cashRegisterId,
    );

    if (created == null || created['id']?.toString() != id) {
      throw StateError('No se pudo crear cash_session local.');
    }

    return created;
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
