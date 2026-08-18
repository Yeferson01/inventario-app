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
    required String businessId,
    required String branchId,
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
        and business_id = ?
        and branch_id = ?
        and deleted_at is null
      limit 1
      ''',
      variables: [
        Variable<String>(id),
        Variable<String>(businessId),
        Variable<String>(branchId),
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
    required String businessId,
    required String branchId,
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
      where business_id = ?
        and branch_id = ?
        and cash_register_id = ?
        and status = 'open'
        and deleted_at is null
      order by opened_at desc
      limit 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
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

    final created = await getCashRegisterById(
      id: id,
      businessId: businessId,
      branchId: branchId,
    );

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
      businessId: businessId,
      branchId: branchId,
      cashRegisterId: cashRegisterId,
    );

    if (created == null || created['id']?.toString() != id) {
      throw StateError('No se pudo crear cash_session local.');
    }

    return created;
  }

  Future<Map<String, dynamic>> getPosCashReadinessSummary({
    required String businessId,
    required String branchId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        (
          select count(*)
          from cash_registers cr
          where cr.business_id = ?
            and cr.branch_id = ?
            and cr.deleted_at is null
            and (
              cr.local_status = 'dirty'
              or cr.sync_status != 0
            )
        ) as dirty_cash_register_count,
        (
          select count(*)
          from cash_sessions cs
          where cs.business_id = ?
            and cs.branch_id = ?
            and cs.deleted_at is null
            and (
              cs.local_status = 'dirty'
              or cs.sync_status != 0
            )
        ) as dirty_cash_session_count,
        (
          select count(*)
          from sales s
          where s.business_id = ?
            and s.branch_id = ?
            and s.deleted_at is null
            and (
              s.local_status = 'dirty'
              or s.sync_status != 0
            )
            and (
              s.cash_register_id is null
              or trim(s.cash_register_id) = ''
              or s.cash_session_id is null
              or trim(s.cash_session_id) = ''
            )
        ) as pending_sales_without_cash_count,
        (
          select count(*)
          from sales s
          join cash_sessions cs
            on cs.id = s.cash_session_id
          where s.business_id = ?
            and s.branch_id = ?
            and s.deleted_at is null
            and (
              s.local_status = 'dirty'
              or s.sync_status != 0
            )
            and cs.deleted_at is null
            and (
              cs.local_status = 'dirty'
              or cs.sync_status != 0
            )
        ) as pending_sales_with_unsynced_cash_session_count,
        (
          select count(*)
          from sales s
          join cash_registers cr
            on cr.id = s.cash_register_id
          where s.business_id = ?
            and s.branch_id = ?
            and s.deleted_at is null
            and (
              s.local_status = 'dirty'
              or s.sync_status != 0
            )
            and cr.deleted_at is null
            and (
              cr.local_status = 'dirty'
              or cr.sync_status != 0
            )
        ) as pending_sales_with_unsynced_cash_register_count
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(businessId),
        Variable<String>(branchId),
      ],
      readsFrom: {
        _db.cashRegisters,
        _db.cashSessions,
        _db.sales,
      },
    ).get();

    final data = rows.isEmpty ? <String, dynamic>{} : rows.first.data;

    final dirtyRegisters =
        _cashDiagnosticInt(data['dirty_cash_register_count']);
    final dirtySessions = _cashDiagnosticInt(data['dirty_cash_session_count']);
    final salesWithoutCash =
        _cashDiagnosticInt(data['pending_sales_without_cash_count']);
    final salesWithUnsyncedSession = _cashDiagnosticInt(
      data['pending_sales_with_unsynced_cash_session_count'],
    );
    final salesWithUnsyncedRegister = _cashDiagnosticInt(
      data['pending_sales_with_unsynced_cash_register_count'],
    );

    return {
      'business_id': businessId,
      'branch_id': branchId,
      'dirty_cash_register_count': dirtyRegisters,
      'dirty_cash_session_count': dirtySessions,
      'pending_sales_without_cash_count': salesWithoutCash,
      'pending_sales_with_unsynced_cash_session_count':
          salesWithUnsyncedSession,
      'pending_sales_with_unsynced_cash_register_count':
          salesWithUnsyncedRegister,
      'cash_must_upload_before_pos': dirtyRegisters > 0 ||
          dirtySessions > 0 ||
          salesWithUnsyncedSession > 0 ||
          salesWithUnsyncedRegister > 0,
      'pos_upload_blocked_reason': _posUploadBlockedReason(
        dirtyCashRegisterCount: dirtyRegisters,
        dirtyCashSessionCount: dirtySessions,
        pendingSalesWithoutCashCount: salesWithoutCash,
        pendingSalesWithUnsyncedCashSessionCount: salesWithUnsyncedSession,
        pendingSalesWithUnsyncedCashRegisterCount: salesWithUnsyncedRegister,
      ),
    };
  }

  Future<List<Map<String, dynamic>>> getSalesCashAssociationPreview({
    required String businessId,
    required String branchId,
    int limit = 10,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        s.id as sale_id,
        s.business_id,
        s.branch_id,
        s.cash_register_id,
        s.cash_session_id,
        s.total,
        s.local_status as sale_local_status,
        s.sync_status as sale_sync_status,
        s.created_at as sale_created_at,
        cr.status as cash_register_status,
        cr.local_status as cash_register_local_status,
        cr.sync_status as cash_register_sync_status,
        cs.status as cash_session_status,
        cs.local_status as cash_session_local_status,
        cs.sync_status as cash_session_sync_status,
        cs.opened_at as cash_session_opened_at,
        cs.closed_at as cash_session_closed_at
      from sales s
      left join cash_registers cr
        on cr.id = s.cash_register_id
      left join cash_sessions cs
        on cs.id = s.cash_session_id
      where s.business_id = ?
        and s.branch_id = ?
        and s.deleted_at is null
      order by s.created_at desc
      limit ?
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<int>(limit),
      ],
      readsFrom: {
        _db.sales,
        _db.cashRegisters,
        _db.cashSessions,
      },
    ).get();

    return rows.map((row) => row.data).toList();
  }

  String? _posUploadBlockedReason({
    required int dirtyCashRegisterCount,
    required int dirtyCashSessionCount,
    required int pendingSalesWithoutCashCount,
    required int pendingSalesWithUnsyncedCashSessionCount,
    required int pendingSalesWithUnsyncedCashRegisterCount,
  }) {
    if (pendingSalesWithoutCashCount > 0) {
      return 'Hay ventas pendientes sin cash_register_id o cash_session_id.';
    }

    if (dirtyCashRegisterCount > 0 || dirtyCashSessionCount > 0) {
      return 'Hay cajas o sesiones de caja locales pendientes de sincronizar. Sube cash antes de POS.';
    }

    if (pendingSalesWithUnsyncedCashSessionCount > 0 ||
        pendingSalesWithUnsyncedCashRegisterCount > 0) {
      return 'Hay ventas pendientes asociadas a cash_register/cash_session aún no sincronizados.';
    }

    return null;
  }

  int _cashDiagnosticInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<Map<String, dynamic>> getLatestCashSessionSummaryForBranch({
    required String businessId,
    required String branchId,
  }) async {
    final sessionRows = await _db.customSelect(
      '''
      select
        cs.id,
        cs.business_id,
        cs.branch_id,
        cs.cash_register_id,
        cr.name as cash_register_name,
        cr.code as cash_register_code,
        cs.opened_by_profile_id,
        cs.closed_by_profile_id,
        cs.opened_at,
        cs.closed_at,
        cs.opening_cash_amount,
        cs.expected_cash_amount,
        cs.closing_cash_amount,
        cs.difference_amount,
        cs.status,
        cs.local_status,
        cs.sync_status,
        cs.version,
        cs.created_at,
        cs.updated_at,
        cs.last_synced_at
      from cash_sessions cs
      left join cash_registers cr
        on cr.id = cs.cash_register_id
      where cs.business_id = ?
        and cs.branch_id = ?
        and cs.deleted_at is null
      order by
        case when cs.status = 'open' then 0 else 1 end,
        cs.updated_at desc,
        cs.created_at desc
      limit 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
      ],
      readsFrom: {
        _db.cashSessions,
        _db.cashRegisters,
      },
    ).get();

    if (sessionRows.isEmpty) {
      throw StateError('No hay sesiones de caja locales para esta sucursal.');
    }

    final session = sessionRows.first.data;
    final cashSessionId = session['id'].toString();

    final salesRows = await _db.customSelect(
      '''
      select
        count(*) as sale_count,
        coalesce(sum(total), 0) as sales_total
      from sales
      where cash_session_id = ?
        and deleted_at is null
      ''',
      variables: [
        Variable<String>(cashSessionId),
      ],
      readsFrom: {_db.sales},
    ).get();

    final salesData =
        salesRows.isEmpty ? <String, dynamic>{} : salesRows.first.data;

    final paymentRows = await _db.customSelect(
      '''
      select
        lower(coalesce(sp.payment_method, 'unknown')) as payment_method,
        count(*) as payment_count,
        coalesce(sum(sp.amount), 0) as payment_total
      from sale_payments sp
      join sales s
        on s.id = sp.sale_id
      where s.cash_session_id = ?
        and s.deleted_at is null
        and sp.deleted_at is null
      group by lower(coalesce(sp.payment_method, 'unknown'))
      order by payment_method asc
      ''',
      variables: [
        Variable<String>(cashSessionId),
      ],
      readsFrom: {
        _db.salePayments,
        _db.sales,
      },
    ).get();

    final paymentsByMethod = <Map<String, dynamic>>[];
    var totalPayments = 0.0;
    var cashPayments = 0.0;

    for (final row in paymentRows) {
      final data = row.data;
      final method = data['payment_method']?.toString() ?? 'unknown';
      final total = _cashSummaryDouble(data['payment_total']);
      final count = _cashSummaryInt(data['payment_count']);

      totalPayments += total;

      if (method == 'cash' || method == 'efectivo') {
        cashPayments += total;
      }

      paymentsByMethod.add({
        'payment_method': method,
        'payment_count': count,
        'payment_total': total,
      });
    }

    final openingCashAmount = _cashSummaryDouble(
      session['opening_cash_amount'],
    );

    final calculatedExpectedCashAmount = openingCashAmount + cashPayments;

    final storedExpectedCashAmount = _cashSummaryNullableDouble(
      session['expected_cash_amount'],
    );

    final closingCashAmount = _cashSummaryNullableDouble(
      session['closing_cash_amount'],
    );

    final differenceAmount = _cashSummaryNullableDouble(
      session['difference_amount'],
    );

    return {
      'cash_session_id': cashSessionId,
      'business_id': session['business_id'],
      'branch_id': session['branch_id'],
      'cash_register_id': session['cash_register_id'],
      'cash_register_name': session['cash_register_name'],
      'cash_register_code': session['cash_register_code'],
      'status': session['status'],
      'opened_by_profile_id': session['opened_by_profile_id'],
      'closed_by_profile_id': session['closed_by_profile_id'],
      'opened_at': _cashSummaryString(session['opened_at']),
      'closed_at': _cashSummaryString(session['closed_at']),
      'opening_cash_amount': openingCashAmount,
      'sale_count': _cashSummaryInt(salesData['sale_count']),
      'sales_total': _cashSummaryDouble(salesData['sales_total']),
      'total_payments': totalPayments,
      'cash_payments': cashPayments,
      'payments_by_method': paymentsByMethod,
      'calculated_expected_cash_amount': calculatedExpectedCashAmount,
      'stored_expected_cash_amount': storedExpectedCashAmount,
      'closing_cash_amount': closingCashAmount,
      'difference_amount': differenceAmount,
      'calculated_difference_amount': closingCashAmount == null
          ? null
          : closingCashAmount - calculatedExpectedCashAmount,
      'local_status': session['local_status'],
      'sync_status': session['sync_status'],
      'version': session['version'],
      'created_at': _cashSummaryString(session['created_at']),
      'updated_at': _cashSummaryString(session['updated_at']),
      'last_synced_at': _cashSummaryString(session['last_synced_at']),
      'interpretation': {
        'is_open': session['status'] == 'open',
        'is_closed': session['status'] == 'closed',
        'is_synced': session['local_status'] == 'synced',
        'expected_matches_stored': storedExpectedCashAmount == null
            ? null
            : (storedExpectedCashAmount - calculatedExpectedCashAmount).abs() <
                0.01,
      },
    };
  }

  double _cashSummaryDouble(Object? value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _cashSummaryNullableDouble(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString());
  }

  int _cashSummaryInt(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String? _cashSummaryString(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }

  Future<double> calculateExpectedCashAmountForSession({
    required String cashSessionId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        coalesce(cs.opening_cash_amount, 0)
        + coalesce((
          select sum(sp.amount)
          from sale_payments sp
          join sales s
            on s.id = sp.sale_id
          where s.cash_session_id = cs.id
            and s.deleted_at is null
            and sp.deleted_at is null
            and lower(coalesce(sp.payment_method, '')) = 'cash'
            and lower(coalesce(sp.status, 'completed')) in (
              'completed',
              'paid',
              'approved',
              'synced'
            )
        ), 0) as expected_cash_amount
      from cash_sessions cs
      where cs.id = ?
        and cs.deleted_at is null
      limit 1
      ''',
      variables: [
        Variable<String>(cashSessionId),
      ],
      readsFrom: {
        _db.cashSessions,
        _db.sales,
        _db.salePayments,
      },
    ).get();

    if (rows.isEmpty) {
      throw StateError('No se encontró la sesión de caja local.');
    }

    final value = rows.first.data['expected_cash_amount'];

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<Map<String, dynamic>?> getCashSessionById({
    required String id,
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
      where id = ?
        and deleted_at is null
      limit 1
      ''',
      variables: [
        Variable<String>(id),
      ],
      readsFrom: {_db.cashSessions},
    ).get();

    if (rows.isEmpty) {
      return null;
    }

    return rows.first.data;
  }

  Future<void> closeCashSession({
    required String cashSessionId,
    required String closedByProfileId,
    required double expectedCashAmount,
    required double closingCashAmount,
    String? notes,
  }) async {
    final now = DateTime.now().toUtc();
    final differenceAmount = closingCashAmount - expectedCashAmount;

    final current = await getCashSessionById(id: cashSessionId);

    if (current == null) {
      throw StateError('No se encontró la sesión de caja local.');
    }

    final status = current['status']?.toString();

    if (status != 'open') {
      throw StateError(
        'La sesión de caja no está abierta. Estado actual: $status',
      );
    }

    await _customStatement(
      '''
      update cash_sessions
      set
        closed_by_profile_id = ?,
        closed_at = ?,
        expected_cash_amount = ?,
        closing_cash_amount = ?,
        difference_amount = ?,
        status = 'closed',
        local_status = 'dirty',
        sync_status = ?,
        version = coalesce(version, 1) + 1,
        metadata_json = json_patch(
          coalesce(metadata_json, '{}'),
          json_object(
            'closed_locally_at', ?,
            'closed_by_profile_id', ?,
            'close_source', 'cash_session_local_dao',
            'close_notes', ?
          )
        ),
        updated_at = ?
      where id = ?
        and deleted_at is null
      ''',
      [
        closedByProfileId,
        now,
        expectedCashAmount,
        closingCashAmount,
        differenceAmount,
        SyncStatus.pendingInsert.index,
        now.toIso8601String(),
        closedByProfileId,
        notes,
        now,
        cashSessionId,
      ],
    );
  }

  Future<int> deleteOrphanCashOutboxBatches({
    required String businessId,
    String? branchId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select b.id
      from local_sync_batches b
      where b.business_id = ?
        and b.domain = 'cash'
        and b.status in ('pending', 'partial', 'error', 'failed', 'uploading')
        and (
          ? is null
          or b.branch_id = ?
        )
        and not exists (
          select 1
          from local_sync_mutations m
          where m.local_sync_batch_id = b.id
        )
      order by b.created_at asc
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(branchId),
      ],
      readsFrom: {
        _db.localSyncBatches,
        _db.localSyncMutations,
      },
    ).get();

    for (final row in rows) {
      final batchId = row.data['id']?.toString();

      if (batchId == null || batchId.trim().isEmpty) {
        continue;
      }

      await _customStatement(
        '''
        delete from local_sync_batches
        where id = ?
          and domain = 'cash'
          and not exists (
            select 1
            from local_sync_mutations m
            where m.local_sync_batch_id = local_sync_batches.id
          )
        ''',
        [batchId],
      );
    }

    return rows.length;
  }

  Future<int> resetRetryableCashOutboxBatches({
    required String businessId,
    String? branchId,
  }) async {
    final now = DateTime.now().toUtc();

    final rows = await _db.customSelect(
      '''
      select id
      from local_sync_batches
      where business_id = ?
        and domain = 'cash'
        and status in ('partial', 'error', 'failed', 'uploading')
        and (
          ? is null
          or branch_id = ?
        )
      order by created_at asc
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(branchId),
      ],
      readsFrom: {_db.localSyncBatches},
    ).get();

    for (final row in rows) {
      final batchId = row.data['id']?.toString();

      if (batchId == null || batchId.trim().isEmpty) {
        continue;
      }

      await _customStatement(
        '''
        update local_sync_mutations
        set
          status = 'pending',
          error_code = null,
          updated_at = ?
        where local_sync_batch_id = ?
          and entity_table in ('cash_registers', 'cash_sessions')
          and status in ('error', 'failed', 'partial', 'uploading')
        ''',
        [
          now,
          batchId,
        ],
      );

      await _customStatement(
        '''
        update local_sync_batches
        set
          status = 'pending',
          updated_at = ?
        where id = ?
        ''',
        [
          now,
          batchId,
        ],
      );
    }

    return rows.length;
  }

  Future<List<Map<String, dynamic>>> getPendingDirtyCashRegisters({
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
      readsFrom: {_db.cashRegisters},
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Future<List<Map<String, dynamic>>> getPendingDirtyCashSessions({
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
      readsFrom: {_db.cashSessions},
    ).get();

    return rows.map((row) => row.data).toList();
  }

  Future<int> reconcileCompletedCashFromOutbox({
    required String businessId,
    String? branchId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select distinct
        sm.entity_table,
        sm.entity_id
      from local_sync_mutations sm
      join local_sync_batches sb
        on sb.id = sm.local_sync_batch_id
      where sm.business_id = ?
        and sm.entity_table in ('cash_registers', 'cash_sessions')
        and sb.status = 'completed'
        and (
          ? is null
          or sm.branch_id = ?
        )
      order by sm.entity_table, sm.entity_id
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
      final entityTable = row.data['entity_table']?.toString();
      final entityId = row.data['entity_id']?.toString();

      if (entityId == null || entityId.trim().isEmpty) {
        continue;
      }

      if (entityTable == 'cash_registers') {
        await markCashRegisterSyncedAfterUpload(id: entityId);
        reconciled++;
      } else if (entityTable == 'cash_sessions') {
        await markCashSessionSyncedAfterUpload(id: entityId);
        reconciled++;
      }
    }

    return reconciled;
  }

  Future<void> markCashRegisterSyncedAfterUpload({
    required String id,
  }) async {
    final now = DateTime.now().toUtc();

    await _customStatement(
      '''
      update cash_registers
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
        id,
      ],
    );
  }

  Future<void> markCashSessionSyncedAfterUpload({
    required String id,
  }) async {
    final now = DateTime.now().toUtc();

    await _customStatement(
      '''
      update cash_sessions
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
        id,
      ],
    );
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
