import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/utils/app_uuid.dart';
import '../models/local_sync_outbox_models.dart';

class LocalSyncOutboxDao {
  LocalSyncOutboxDao(this._db);

  final AppDatabase _db;

  Future<LocalSyncEnqueueResult> enqueueUploadBatch({
    required String businessId,
    required String domain,
    required String clientBatchId,
    required List<LocalSyncMutationDraft> mutations,
    String? branchId,
    String? appDeviceId,
    String? profileId,
    Map<String, dynamic>? metadata,
  }) async {
    if (mutations.isEmpty) {
      throw ArgumentError('No se puede crear un batch sin mutaciones.');
    }

    final localBatchId = AppUuid.v7();
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      await _db.customStatement(
        '''
        insert into local_sync_batches (
          id,
          client_batch_id,
          business_id,
          branch_id,
          app_device_id,
          profile_id,
          domain,
          direction,
          status,
          mutation_count,
          applied_count,
          skipped_count,
          conflict_count,
          error_count,
          metadata_json,
          created_at,
          updated_at
        )
        values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        on conflict(id) do update set
          status = excluded.status,
          mutation_count = excluded.mutation_count,
          metadata_json = excluded.metadata_json,
          updated_at = excluded.updated_at
        ''',
        [
          localBatchId,
          clientBatchId,
          businessId,
          branchId,
          appDeviceId,
          profileId,
          domain,
          'upload',
          'pending',
          mutations.length,
          0,
          0,
          0,
          0,
          metadata == null ? null : jsonEncode(metadata),
          now,
          now,
        ],
      );

      for (final mutation in mutations) {
        await _insertMutation(
          localBatchId: localBatchId,
          clientBatchId: clientBatchId,
          fallbackBusinessId: businessId,
          fallbackBranchId: branchId,
          fallbackAppDeviceId: appDeviceId,
          fallbackProfileId: profileId,
          mutation: mutation,
          now: now,
        );
      }
    });

    return LocalSyncEnqueueResult(
      localBatchId: localBatchId,
      clientBatchId: clientBatchId,
      domain: domain,
      mutationCount: mutations.length,
    );
  }

  Future<void> _insertMutation({
    required String localBatchId,
    required String clientBatchId,
    required String fallbackBusinessId,
    required String? fallbackBranchId,
    required String? fallbackAppDeviceId,
    required String? fallbackProfileId,
    required LocalSyncMutationDraft mutation,
    required DateTime now,
  }) async {
    await _db.customStatement(
      '''
      insert into local_sync_mutations (
        id,
        local_sync_batch_id,
        client_batch_id,
        client_mutation_id,
        client_sequence,
        business_id,
        branch_id,
        app_device_id,
        profile_id,
        entity_table,
        entity_id,
        operation,
        payload_json,
        before_payload_json,
        changed_fields_json,
        base_version,
        base_updated_at,
        idempotency_key,
        status,
        retry_count,
        metadata_json,
        created_at,
        updated_at
      )
      values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(idempotency_key) do update set
        local_sync_batch_id = excluded.local_sync_batch_id,
        client_batch_id = excluded.client_batch_id,
        status = excluded.status,
        retry_count = local_sync_mutations.retry_count,
        updated_at = excluded.updated_at
      ''',
      [
        AppUuid.v7(),
        localBatchId,
        clientBatchId,
        mutation.clientMutationId,
        mutation.clientSequence,
        mutation.businessId ?? fallbackBusinessId,
        mutation.branchId ?? fallbackBranchId,
        mutation.appDeviceId ?? fallbackAppDeviceId,
        mutation.profileId ?? fallbackProfileId,
        mutation.entityTable,
        mutation.entityId,
        mutation.operation,
        mutation.payloadJson,
        mutation.beforePayloadJson,
        mutation.changedFieldsJson,
        mutation.baseVersion,
        mutation.baseUpdatedAt,
        mutation.idempotencyKey,
        'pending',
        0,
        mutation.metadataJson,
        now,
        now,
      ],
    );
  }

  Future<List<Map<String, dynamic>>> getPendingBatches({
    required String businessId,
    String? domain,
    int limit = 20,
  }) async {
    final whereDomain = domain == null ? '' : 'and domain = ?';

    final variables = <Variable>[
      Variable<String>(businessId),
      if (domain != null) Variable<String>(domain),
      Variable<int>(limit),
    ];

    final rows = await _db.customSelect(
      '''
          select *
          from local_sync_batches
          where business_id = ?
            and status in ('pending', 'error')
            $whereDomain
          order by created_at asc
          limit ?
          ''',
      variables: variables,
    ).get();

    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  Future<List<Map<String, dynamic>>> getMutationsForBatch(
    String localBatchId,
  ) async {
    final rows = await _db.customSelect(
      '''
          select *
          from local_sync_mutations
          where local_sync_batch_id = ?
          order by client_sequence asc, created_at asc
          ''',
      variables: [Variable<String>(localBatchId)],
    ).get();

    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  Future<int> countPendingMutations({
    required String businessId,
    String? domain,
  }) async {
    final domainJoin = domain == null ? '' : 'and b.domain = ?';

    final variables = <Variable>[
      Variable<String>(businessId),
      if (domain != null) Variable<String>(domain),
    ];

    final row = await _db.customSelect(
      '''
          select count(*) as total
          from local_sync_mutations m
          join local_sync_batches b
            on b.id = m.local_sync_batch_id
          where m.business_id = ?
            and m.status in ('pending', 'error')
            $domainJoin
          ''',
      variables: variables,
    ).getSingle();

    return (row.data['total'] as int?) ?? 0;
  }

  Future<void> markBatchUploading(String localBatchId) async {
    await _updateBatchStatus(localBatchId, 'uploading');
  }

  Future<void> markBatchCompleted({
    required String localBatchId,
    String? serverSyncBatchId,
    int? appliedCount,
    int? skippedCount,
    int? conflictCount,
    int? errorCount,
  }) async {
    final now = DateTime.now().toUtc();

    await _db.customStatement(
      '''
      update local_sync_batches
      set
        status = 'completed',
        server_sync_batch_id = coalesce(?, server_sync_batch_id),
        applied_count = coalesce(?, applied_count),
        skipped_count = coalesce(?, skipped_count),
        conflict_count = coalesce(?, conflict_count),
        error_count = coalesce(?, error_count),
        uploaded_at = ?,
        updated_at = ?
      where id = ?
      ''',
      [
        serverSyncBatchId,
        appliedCount,
        skippedCount,
        conflictCount,
        errorCount,
        now,
        now,
        localBatchId,
      ],
    );
  }

  Future<void> markBatchPartial({
    required String localBatchId,
    String? serverSyncBatchId,
    int? appliedCount,
    int? skippedCount,
    int? conflictCount,
    int? errorCount,
  }) async {
    final now = DateTime.now().toUtc();

    await _db.customStatement(
      '''
      update local_sync_batches
      set
        status = 'partial',
        server_sync_batch_id = coalesce(?, server_sync_batch_id),
        applied_count = coalesce(?, applied_count),
        skipped_count = coalesce(?, skipped_count),
        conflict_count = coalesce(?, conflict_count),
        error_count = coalesce(?, error_count),
        uploaded_at = ?,
        updated_at = ?
      where id = ?
      ''',
      [
        serverSyncBatchId,
        appliedCount,
        skippedCount,
        conflictCount,
        errorCount,
        now,
        now,
        localBatchId,
      ],
    );
  }

  Future<void> markBatchError({
    required String localBatchId,
    required Object error,
  }) async {
    final now = DateTime.now().toUtc();

    await _db.customStatement(
      '''
      update local_sync_batches
      set
        status = 'error',
        last_error = ?,
        updated_at = ?
      where id = ?
      ''',
      [
        error.toString(),
        now,
        localBatchId,
      ],
    );
  }

  Future<void> markMutationApplied({
    required String localMutationId,
    String? serverSyncMutationId,
  }) async {
    final now = DateTime.now().toUtc();

    await _db.customStatement(
      '''
      update local_sync_mutations
      set
        status = 'applied',
        server_sync_mutation_id = coalesce(?, server_sync_mutation_id),
        uploaded_at = ?,
        updated_at = ?,
        last_error = null,
        error_code = null
      where id = ?
      ''',
      [
        serverSyncMutationId,
        now,
        now,
        localMutationId,
      ],
    );
  }

  Future<void> markMutationConflict({
    required String localMutationId,
    String? errorCode,
    String? errorMessage,
  }) async {
    await _markMutationTerminalStatus(
      localMutationId: localMutationId,
      status: 'conflict',
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }

  Future<void> markMutationError({
    required String localMutationId,
    String? errorCode,
    required Object error,
  }) async {
    final now = DateTime.now().toUtc();

    await _db.customStatement(
      '''
      update local_sync_mutations
      set
        status = 'error',
        retry_count = retry_count + 1,
        error_code = ?,
        last_error = ?,
        updated_at = ?
      where id = ?
      ''',
      [
        errorCode,
        error.toString(),
        now,
        localMutationId,
      ],
    );
  }

  Future<void> _markMutationTerminalStatus({
    required String localMutationId,
    required String status,
    String? errorCode,
    String? errorMessage,
  }) async {
    final now = DateTime.now().toUtc();

    await _db.customStatement(
      '''
      update local_sync_mutations
      set
        status = ?,
        error_code = ?,
        last_error = ?,
        updated_at = ?
      where id = ?
      ''',
      [
        status,
        errorCode,
        errorMessage,
        now,
        localMutationId,
      ],
    );
  }

  Future<void> _updateBatchStatus(String localBatchId, String status) async {
    final now = DateTime.now().toUtc();

    await _db.customStatement(
      '''
      update local_sync_batches
      set
        status = ?,
        updated_at = ?
      where id = ?
      ''',
      [
        status,
        now,
        localBatchId,
      ],
    );
  }
}
