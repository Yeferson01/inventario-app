import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../../../../core/utils/app_uuid.dart';
import '../models/cash_flow_report_models.dart';
import '../models/profitability_report_models.dart';
import '../models/sales_report_models.dart';

class ReportSnapshotLocalDao {
  ReportSnapshotLocalDao(this._db);

  final AppDatabase _db;

  Future<bool> hasPendingCashMovements(SalesReportScope scope) async {
    final rows = await _db.customSelect('''
      select 1 from local_cash_movements
      where business_id = ? and branch_id = ?
        and occurred_at >= ? and occurred_at < ?
        and local_status in ('dirty', 'error', 'conflict')
      limit 1
    ''', variables: [
      Variable<String>(scope.businessId),
      Variable<String>(scope.branchId),
      Variable<DateTime>(scope.period.from),
      Variable<DateTime>(scope.period.to),
    ], readsFrom: {
      _db.localCashMovements
    }).get();
    return rows.isNotEmpty;
  }

  Future<bool> hasPendingCashSales(SalesReportScope scope) async {
    // Local sale_payments has no paid_at column. The payment's created_at is
    // the recorded local economic time; the remote RPC uses paid_at after sync.
    final rows = await _db.customSelect('''
      select 1 from sale_payments payment
      join sales sale on sale.id = payment.sale_id
      where sale.business_id = ? and sale.branch_id = ?
        and payment.business_id = sale.business_id
        and (payment.branch_id is null or payment.branch_id = sale.branch_id)
        and sale.deleted_at is null and payment.deleted_at is null
        and sale.status = 'completed' and payment.status = 'completed'
        and lower(payment.payment_method) = 'cash'
        and payment.amount > 0
        and payment.created_at >= ? and payment.created_at < ?
        and (sale.local_status != 'synced' or sale.sync_status != 0
          or payment.local_status != 'synced' or payment.sync_status != 0)
      limit 1
    ''', variables: [
      Variable<String>(scope.businessId),
      Variable<String>(scope.branchId),
      Variable<DateTime>(scope.period.from),
      Variable<DateTime>(scope.period.to),
    ], readsFrom: {
      _db.sales,
      _db.salePayments,
    }).get();
    return rows.isNotEmpty;
  }

  Future<CashFlowReportSnapshot?> readCashFlow(SalesReportScope scope) async {
    final row = await _db.customSelect('''
      select * from local_report_snapshots
      where profile_id = ? and business_id = ? and branch_id = ?
        and report_type = ? and filter_key = ? limit 1
    ''', variables: [
      Variable<String>(scope.profileId),
      Variable<String>(scope.businessId),
      Variable<String>(scope.branchId),
      const Variable<String>(cashFlowReportType),
      Variable<String>(scope.period.filterKey),
    ], readsFrom: {
      _db.localReportSnapshots
    }).getSingleOrNull();
    if (row == null) return null;
    if (!_bool(
            row.data['includes_sensitive_data'], 'includes_sensitive_data') ||
        _bool(row.data['includes_costs'], 'includes_costs')) {
      throw const FormatException('Cached cash report sensitivity is invalid.');
    }
    final payload = jsonDecode(row.read<String>('payload_json'));
    if (payload is! Map) {
      throw const FormatException('Cached cash report payload is malformed.');
    }
    final summary = CashFlowReportSummary.fromJson(
      payload.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value)),
    );
    if (summary.businessId != scope.businessId ||
        summary.branchId != scope.branchId ||
        summary.periodFrom.microsecondsSinceEpoch !=
            scope.period.from.microsecondsSinceEpoch ||
        summary.periodTo.microsecondsSinceEpoch !=
            scope.period.to.microsecondsSinceEpoch) {
      throw const FormatException('Cached cash report scope is malformed.');
    }
    return CashFlowReportSnapshot(
      summary: summary,
      fetchedAt: _dateTime(row.data['fetched_at'], 'fetched_at'),
      authorizationValidatedAt: _dateTime(
          row.data['authorization_validated_at'], 'authorization_validated_at'),
      hasPendingLocalSync: await hasPendingCashMovements(scope),
      hasPendingLocalCashSales: await hasPendingCashSales(scope),
    );
  }

  Future<void> replaceCashFlow({
    required String profileId,
    required CashFlowReportSummary summary,
    required DateTime fetchedAt,
    required DateTime authorizationValidatedAt,
    required String capabilityFingerprint,
  }) async {
    final period =
        SalesReportPeriod(from: summary.periodFrom, to: summary.periodTo);
    final now = DateTime.now().toUtc();
    await _db.customUpdate(
        '''
      insert into local_report_snapshots (
        id, profile_id, business_id, branch_id, report_type, filter_key,
        payload_json, fetched_at, authoritative_as_of,
        authorization_validated_at, capability_fingerprint,
        includes_sensitive_data, includes_costs, created_at, updated_at
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(profile_id, business_id, branch_id, report_type, filter_key)
      do update set payload_json = excluded.payload_json,
        fetched_at = excluded.fetched_at,
        authoritative_as_of = excluded.authoritative_as_of,
        authorization_validated_at = excluded.authorization_validated_at,
        capability_fingerprint = excluded.capability_fingerprint,
        includes_sensitive_data = excluded.includes_sensitive_data,
        includes_costs = excluded.includes_costs,
        updated_at = excluded.updated_at
    ''',
        variables: normalizeSqliteParameters([
          AppUuid.v7(),
          profileId,
          summary.businessId,
          summary.branchId,
          cashFlowReportType,
          period.filterKey,
          jsonEncode(summary.toJson()),
          fetchedAt,
          summary.authoritativeAsOf,
          authorizationValidatedAt,
          capabilityFingerprint,
          true,
          false,
          now,
          now,
        ]).map<Variable<Object>>((value) => Variable<Object>(value)).toList(),
        updates: {_db.localReportSnapshots});
  }

  Future<void> invalidateCashFlowScope({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async {
    await _db.customUpdate('''
      delete from local_report_snapshots
      where profile_id = ? and business_id = ? and branch_id = ?
        and report_type = ?
    ''', variables: [
      Variable<String>(profileId),
      Variable<String>(businessId),
      Variable<String>(branchId),
      const Variable<String>(cashFlowReportType),
    ], updates: {
      _db.localReportSnapshots
    });
  }

  Future<SalesReportSnapshot?> readSalesSummary(SalesReportScope scope) async {
    final row = await _db.customSelect(
      '''
      select *
      from local_report_snapshots
      where profile_id = ?
        and business_id = ?
        and branch_id = ?
        and report_type = ?
        and filter_key = ?
      limit 1
      ''',
      variables: [
        Variable<String>(scope.profileId),
        Variable<String>(scope.businessId),
        Variable<String>(scope.branchId),
        const Variable<String>(salesSummaryReportType),
        Variable<String>(scope.period.filterKey),
      ],
      readsFrom: {_db.localReportSnapshots},
    ).getSingleOrNull();
    if (row == null) return null;

    final payload = jsonDecode(row.read<String>('payload_json'));
    if (payload is! Map) {
      throw const FormatException('Cached sales report payload is malformed.');
    }
    final summary = SalesReportSummary.fromCacheJson(
      payload.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
    if (summary.businessId != scope.businessId ||
        summary.branchId != scope.branchId ||
        summary.periodFrom.microsecondsSinceEpoch !=
            scope.period.from.microsecondsSinceEpoch ||
        summary.periodTo.microsecondsSinceEpoch !=
            scope.period.to.microsecondsSinceEpoch) {
      throw const FormatException('Cached sales report scope is malformed.');
    }

    return SalesReportSnapshot(
      summary: summary,
      fetchedAt: _dateTime(row.data['fetched_at'], 'fetched_at'),
      authorizationValidatedAt: _dateTime(
        row.data['authorization_validated_at'],
        'authorization_validated_at',
      ),
      capabilityFingerprint: row.read<String>('capability_fingerprint'),
      includesSensitiveData: _bool(
        row.data['includes_sensitive_data'],
        'includes_sensitive_data',
      ),
      includesCosts: _bool(row.data['includes_costs'], 'includes_costs'),
    );
  }

  Future<void> replaceSalesSummary({
    required String profileId,
    required SalesReportSummary summary,
    required DateTime fetchedAt,
    required DateTime authorizationValidatedAt,
    required String capabilityFingerprint,
  }) async {
    final period = SalesReportPeriod(
      from: summary.periodFrom,
      to: summary.periodTo,
    );
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db.customUpdate(
        '''
        insert into local_report_snapshots (
          id, profile_id, business_id, branch_id, report_type, filter_key,
          payload_json, fetched_at, authoritative_as_of,
          authorization_validated_at, capability_fingerprint,
          includes_sensitive_data, includes_costs, created_at, updated_at
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        on conflict(profile_id, business_id, branch_id, report_type, filter_key)
        do update set
          payload_json = excluded.payload_json,
          fetched_at = excluded.fetched_at,
          authoritative_as_of = excluded.authoritative_as_of,
          authorization_validated_at = excluded.authorization_validated_at,
          capability_fingerprint = excluded.capability_fingerprint,
          includes_sensitive_data = excluded.includes_sensitive_data,
          includes_costs = excluded.includes_costs,
          updated_at = excluded.updated_at
        ''',
        variables: normalizeSqliteParameters([
          AppUuid.v7(),
          profileId,
          summary.businessId,
          summary.branchId,
          salesSummaryReportType,
          period.filterKey,
          jsonEncode(summary.toJson()),
          fetchedAt,
          summary.authoritativeAsOf,
          authorizationValidatedAt,
          capabilityFingerprint,
          true,
          false,
          now,
          now,
        ]).map<Variable<Object>>((value) => Variable<Object>(value)).toList(),
        updates: {_db.localReportSnapshots},
      );
    });
  }

  Future<ProfitabilityReportSnapshot?> readProfitability(
    SalesReportScope scope,
  ) async {
    final row = await _db.customSelect(
      '''
      select * from local_report_snapshots
      where profile_id = ? and business_id = ? and branch_id = ?
        and report_type = ? and filter_key = ?
      limit 1
      ''',
      variables: [
        Variable<String>(scope.profileId),
        Variable<String>(scope.businessId),
        Variable<String>(scope.branchId),
        const Variable<String>(profitabilityReportType),
        Variable<String>(scope.period.filterKey),
      ],
      readsFrom: {_db.localReportSnapshots},
    ).getSingleOrNull();
    if (row == null) return null;
    if (!_bool(
            row.data['includes_sensitive_data'], 'includes_sensitive_data') ||
        !_bool(row.data['includes_costs'], 'includes_costs')) {
      throw const FormatException(
          'Cached profitability sensitivity is invalid.');
    }
    final payload = jsonDecode(row.read<String>('payload_json'));
    if (payload is! Map) {
      throw const FormatException('Cached profitability payload is malformed.');
    }
    final summary = ProfitabilityReportSummary.fromCacheJson(
      payload.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      ),
    );
    if (summary.businessId != scope.businessId ||
        summary.branchId != scope.branchId ||
        summary.periodFrom.microsecondsSinceEpoch !=
            scope.period.from.microsecondsSinceEpoch ||
        summary.periodTo.microsecondsSinceEpoch !=
            scope.period.to.microsecondsSinceEpoch) {
      throw const FormatException('Cached profitability scope is malformed.');
    }
    return ProfitabilityReportSnapshot(
      summary: summary,
      fetchedAt: _dateTime(row.data['fetched_at'], 'fetched_at'),
      authorizationValidatedAt: _dateTime(
          row.data['authorization_validated_at'], 'authorization_validated_at'),
      capabilityFingerprint: row.read<String>('capability_fingerprint'),
      includesSensitiveData: true,
      includesCosts: true,
    );
  }

  Future<void> replaceProfitability({
    required String profileId,
    required ProfitabilityReportSummary summary,
    required DateTime fetchedAt,
    required DateTime authorizationValidatedAt,
    required String capabilityFingerprint,
  }) async {
    final period = SalesReportPeriod(
      from: summary.periodFrom,
      to: summary.periodTo,
    );
    final now = DateTime.now().toUtc();
    await _db.transaction(() async {
      await _db.customUpdate(
        '''
        insert into local_report_snapshots (
          id, profile_id, business_id, branch_id, report_type, filter_key,
          payload_json, fetched_at, authoritative_as_of,
          authorization_validated_at, capability_fingerprint,
          includes_sensitive_data, includes_costs, created_at, updated_at
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        on conflict(profile_id, business_id, branch_id, report_type, filter_key)
        do update set
          payload_json = excluded.payload_json,
          fetched_at = excluded.fetched_at,
          authoritative_as_of = excluded.authoritative_as_of,
          authorization_validated_at = excluded.authorization_validated_at,
          capability_fingerprint = excluded.capability_fingerprint,
          includes_sensitive_data = excluded.includes_sensitive_data,
          includes_costs = excluded.includes_costs,
          updated_at = excluded.updated_at
        ''',
        variables: normalizeSqliteParameters([
          AppUuid.v7(),
          profileId,
          summary.businessId,
          summary.branchId,
          profitabilityReportType,
          period.filterKey,
          jsonEncode(summary.toCacheJson()),
          fetchedAt,
          summary.authoritativeAsOf,
          authorizationValidatedAt,
          capabilityFingerprint,
          true,
          true,
          now,
          now,
        ]).map<Variable<Object>>((value) => Variable<Object>(value)).toList(),
        updates: {_db.localReportSnapshots},
      );
    });
  }

  Future<void> invalidateProfitabilityScope({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async {
    await _db.customUpdate(
      '''
      delete from local_report_snapshots
      where profile_id = ? and business_id = ? and branch_id = ?
        and report_type = ?
      ''',
      variables: [
        Variable<String>(profileId),
        Variable<String>(businessId),
        Variable<String>(branchId),
        const Variable<String>(profitabilityReportType),
      ],
      updates: {_db.localReportSnapshots},
    );
  }

  Future<void> invalidateScope({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async {
    await _db.customUpdate(
      '''
      delete from local_report_snapshots
      where profile_id = ? and business_id = ? and branch_id = ?
      ''',
      variables: [
        Variable<String>(profileId),
        Variable<String>(businessId),
        Variable<String>(branchId),
      ],
      updates: {_db.localReportSnapshots},
    );
  }

  DateTime _dateTime(Object? value, String field) {
    if (value is DateTime) return value.toUtc();
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    throw FormatException('Invalid $field in cached sales report.');
  }

  bool _bool(Object? value, String field) {
    if (value is bool) return value;
    if (value is int && (value == 0 || value == 1)) return value == 1;
    throw FormatException('Invalid $field in cached sales report.');
  }
}
