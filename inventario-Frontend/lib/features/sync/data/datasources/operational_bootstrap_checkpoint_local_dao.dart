import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../../../../core/utils/app_uuid.dart';
import '../models/local_recovery_models.dart';

class OperationalBootstrapCheckpointLocalDao {
  OperationalBootstrapCheckpointLocalDao(this._db);

  final AppDatabase _db;

  Future<void> beginOrRestart({
    required OperationalBootstrapScope scope,
    required String snapshotId,
    required DateTime snapshotAt,
    required DateTime authorizationValidatedAt,
    String? nextPageToken,
    bool requiredForOffline = true,
    String convergenceStatus = 'pending',
  }) async {
    final now = DateTime.now().toUtc();

    await _statement(
      '''
      insert into local_operational_bootstrap_checkpoints (
        id, profile_id, business_id, branch_id, app_device_id, bundle, dataset,
        snapshot_id, snapshot_at, next_page_token, status, rows_received,
        pages_applied, authorization_validated_at, started_at, updated_at,
        completed_at, last_success_at, last_error, retry_count,
        required_for_offline, convergence_status
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'started', 0, 0, ?, ?, ?, null,
        null, null, 0, ?, ?)
      on conflict(profile_id, business_id, branch_id, app_device_id, bundle, dataset)
      do update set
        snapshot_id = excluded.snapshot_id,
        snapshot_at = excluded.snapshot_at,
        next_page_token = excluded.next_page_token,
        status = 'started',
        rows_received = 0,
        pages_applied = 0,
        authorization_validated_at = excluded.authorization_validated_at,
        started_at = excluded.started_at,
        updated_at = excluded.updated_at,
        completed_at = null,
        last_success_at = null,
        last_error = null,
        retry_count = 0,
        required_for_offline = excluded.required_for_offline,
        convergence_status = excluded.convergence_status
      ''',
      [
        AppUuid.v7(),
        scope.profileId,
        scope.businessId,
        scope.branchId,
        scope.appDeviceId,
        scope.bundle,
        scope.dataset,
        snapshotId,
        snapshotAt,
        nextPageToken,
        authorizationValidatedAt,
        now,
        now,
        requiredForOffline,
        convergenceStatus,
      ],
    );
  }

  Future<Map<String, dynamic>?> get(OperationalBootstrapScope scope) async {
    final rows = await _db
        .customSelect(
          '''
      select *
      from local_operational_bootstrap_checkpoints
      where profile_id = ? and business_id = ? and branch_id = ?
        and app_device_id = ? and bundle = ? and dataset = ?
      limit 1
      ''',
          variables: _scopeVariables(scope),
          readsFrom: {_db.localOperationalBootstrapCheckpoints},
        )
        .get();

    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first.data);
  }

  Future<OperationalBootstrapCheckpointRecord?> getRecord(
    OperationalBootstrapScope scope,
  ) async {
    final row = await get(scope);
    return row == null
        ? null
        : OperationalBootstrapCheckpointRecord.fromRow(row);
  }

  Future<List<OperationalBootstrapCheckpointRecord>> listForBundle({
    required String profileId,
    required String businessId,
    required String branchId,
    required String appDeviceId,
    required String bundle,
  }) async {
    final rows = await _db.customSelect(
      '''
      select *
      from local_operational_bootstrap_checkpoints
      where profile_id = ? and business_id = ? and branch_id = ?
        and app_device_id = ? and bundle = ?
      order by dataset
      ''',
      variables: [
        Variable<String>(profileId),
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(appDeviceId),
        Variable<String>(bundle),
      ],
      readsFrom: {_db.localOperationalBootstrapCheckpoints},
    ).get();

    return rows
        .map(
          (row) => OperationalBootstrapCheckpointRecord.fromRow(
            Map<String, dynamic>.from(row.data),
          ),
        )
        .toList(growable: false);
  }

  Future<void> markApplying(
    OperationalBootstrapScope scope, {
    String? convergenceStatus,
  }) {
    return _updateStatus(
      scope,
      status: 'applying',
      convergenceStatus: convergenceStatus,
    );
  }

  Future<void> commitPageProgress({
    required OperationalBootstrapScope scope,
    required String? nextPageToken,
    required int rowsReceived,
    DateTime? authorizationValidatedAt,
  }) async {
    final now = DateTime.now().toUtc();
    await _statement(
      '''
      update local_operational_bootstrap_checkpoints
      set next_page_token = ?,
          rows_received = rows_received + ?,
          pages_applied = pages_applied + 1,
          authorization_validated_at = coalesce(?, authorization_validated_at),
          status = 'applying',
          last_success_at = ?,
          last_error = null,
          updated_at = ?
      where profile_id = ? and business_id = ? and branch_id = ?
        and app_device_id = ? and bundle = ? and dataset = ?
      ''',
      [
        nextPageToken,
        rowsReceived,
        authorizationValidatedAt,
        now,
        now,
        ..._scopeValues(scope),
      ],
    );
  }

  Future<void> markComplete(
    OperationalBootstrapScope scope, {
    String convergenceStatus = 'complete',
  }) async {
    final now = DateTime.now().toUtc();
    await _statement(
      '''
      update local_operational_bootstrap_checkpoints
      set status = 'complete', next_page_token = null, completed_at = ?,
          last_success_at = ?, last_error = null, updated_at = ?,
          convergence_status = ?
      where profile_id = ? and business_id = ? and branch_id = ?
        and app_device_id = ? and bundle = ? and dataset = ?
      ''',
      [now, now, now, convergenceStatus, ..._scopeValues(scope)],
    );
  }

  Future<void> markFailed(
    OperationalBootstrapScope scope, {
    required Object error,
    String convergenceStatus = 'pending',
  }) async {
    final now = DateTime.now().toUtc();
    await _statement(
      '''
      update local_operational_bootstrap_checkpoints
      set status = 'failed', last_error = ?, retry_count = retry_count + 1,
          updated_at = ?, convergence_status = ?
      where profile_id = ? and business_id = ? and branch_id = ?
        and app_device_id = ? and bundle = ? and dataset = ?
      ''',
      [error.toString(), now, convergenceStatus, ..._scopeValues(scope)],
    );
  }

  Future<void> markRestartRequired(
    OperationalBootstrapScope scope, {
    required String reason,
  }) {
    return _updateStatus(
      scope,
      status: 'restart_required',
      lastError: reason,
      convergenceStatus: 'restart_required',
    );
  }

  Future<void> markConvergence(
    OperationalBootstrapScope scope, {
    required String status,
    String? error,
  }) async {
    final now = DateTime.now().toUtc();
    await _statement(
      '''
      update local_operational_bootstrap_checkpoints
      set convergence_status = ?, last_error = ?, updated_at = ?
      where profile_id = ? and business_id = ? and branch_id = ?
        and app_device_id = ? and bundle = ? and dataset = ?
      ''',
      [status, error, now, ..._scopeValues(scope)],
    );
  }

  Future<void> _updateStatus(
    OperationalBootstrapScope scope, {
    required String status,
    String? lastError,
    String? convergenceStatus,
  }) async {
    final now = DateTime.now().toUtc();
    await _statement(
      '''
      update local_operational_bootstrap_checkpoints
      set status = ?, last_error = ?, updated_at = ?,
          convergence_status = coalesce(?, convergence_status)
      where profile_id = ? and business_id = ? and branch_id = ?
        and app_device_id = ? and bundle = ? and dataset = ?
      ''',
      [status, lastError, now, convergenceStatus, ..._scopeValues(scope)],
    );
  }

  List<Variable<String>> _scopeVariables(OperationalBootstrapScope scope) =>
      _scopeValues(scope).map(Variable<String>.new).toList(growable: false);

  List<String> _scopeValues(OperationalBootstrapScope scope) => [
        scope.profileId,
        scope.businessId,
        scope.branchId,
        scope.appDeviceId,
        scope.bundle,
        scope.dataset,
      ];

  Future<void> _statement(String sql, List<Object?> parameters) {
    return _db.customStatement(sql, normalizeSqliteParameters(parameters));
  }
}
