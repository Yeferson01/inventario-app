import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/utils/app_uuid.dart';
import '../models/local_sync_outbox_models.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';

enum BatchDependencyReadiness { ready, waiting, blocked }

class LocalSyncOutboxDao {
  LocalSyncOutboxDao(this._db);

  final AppDatabase _db;

  /// Only an authoritative upload result may set a mutation to `applied`.
  /// `skipped` is deliberately not proof that its business effect exists.
  static const satisfiedPrerequisiteStatus = 'applied';

  Future<void> addBatchDependency({
    required String prerequisiteMutationId,
    required String dependentBatchId,
    required String relationType,
  }) async {
    await _db.transaction(() async {
      final prerequisite = await _db.customSelect('''
        select m.local_sync_batch_id as batch_id, m.business_id,
               b.branch_id as batch_branch_id
        from local_sync_mutations m
        join local_sync_batches b on b.id = m.local_sync_batch_id
        where m.id = ?
      ''', variables: [
        Variable<String>(prerequisiteMutationId)
      ]).getSingleOrNull();
      final dependent = await _db.customSelect('''
        select business_id, branch_id from local_sync_batches where id = ?
      ''', variables: [Variable<String>(dependentBatchId)]).getSingleOrNull();
      if (prerequisite == null || dependent == null) {
        throw StateError('dependency_endpoint_missing');
      }
      final sourceBatch = prerequisite.read<String>('batch_id');
      if (sourceBatch == dependentBatchId) {
        throw StateError('intra_batch_dependency_not_supported');
      }
      if (prerequisite.read<String>('business_id') !=
          dependent.read<String>('business_id')) {
        throw StateError('cross_business_dependency_not_supported');
      }
      final sourceBranch = prerequisite.readNullable<String>('batch_branch_id');
      final targetBranch = dependent.readNullable<String>('branch_id');
      if (sourceBranch != null &&
          targetBranch != null &&
          sourceBranch != targetBranch) {
        throw StateError('cross_branch_dependency_not_supported');
      }
      final prior = await _db.customSelect('''
        select relation_type from local_sync_batch_dependencies
        where prerequisite_mutation_id = ? and dependent_batch_id = ?
      ''', variables: [
        Variable<String>(prerequisiteMutationId),
        Variable<String>(dependentBatchId),
      ]).getSingleOrNull();
      if (prior != null) {
        if (prior.read<String>('relation_type') != relationType) {
          throw StateError('dependency_relation_mismatch');
        }
        return;
      }
      final frozen = await _db.customSelect('''
        select 1 from local_sync_batch_dependencies d
        join local_sync_mutations m on m.id = d.prerequisite_mutation_id
        where m.local_sync_batch_id = ? and d.dependent_batch_id = ?
          and d.completion_snapshot_id is not null
        limit 1
      ''', variables: [
        Variable<String>(sourceBatch),
        Variable<String>(dependentBatchId),
      ]).getSingleOrNull();
      if (frozen != null) {
        throw StateError('batch_completion_snapshot_is_frozen');
      }
      // Each existing edge is source mutation's batch -> dependent batch.
      final cycle = await _db.customSelect('''
        with recursive reachable(batch_id) as (
          select ?
          union
          select d.dependent_batch_id
          from reachable r
          join local_sync_mutations m on m.local_sync_batch_id = r.batch_id
          join local_sync_batch_dependencies d
            on d.prerequisite_mutation_id = m.id
        )
        select 1 from reachable where batch_id = ? limit 1
      ''', variables: [
        Variable<String>(dependentBatchId),
        Variable<String>(sourceBatch),
      ]).getSingleOrNull();
      if (cycle != null) throw StateError('dependency_cycle');
      await _db.customStatement('''
        insert into local_sync_batch_dependencies
          (prerequisite_mutation_id, dependent_batch_id, relation_type)
        values (?, ?, ?)
      ''', [prerequisiteMutationId, dependentBatchId, relationType]);
    });
  }

  /// Freezes the prerequisite mutation set on the first call. Repeating this
  /// operation never picks up later changes to the prerequisite batch.
  Future<void> dependOnBatchCompletion({
    required String prerequisiteBatchId,
    required String dependentBatchId,
    required String relationType,
  }) async {
    await _db.transaction(() async {
      if (prerequisiteBatchId == dependentBatchId) {
        throw StateError('intra_batch_dependency_not_supported');
      }
      final existing = await _db.customSelect('''
        select d.completion_snapshot_id, d.relation_type
        from local_sync_batch_dependencies d
        join local_sync_mutations m on m.id = d.prerequisite_mutation_id
        where m.local_sync_batch_id = ? and d.dependent_batch_id = ?
        limit 1
      ''', variables: [
        Variable<String>(prerequisiteBatchId),
        Variable<String>(dependentBatchId),
      ]).getSingleOrNull();
      if (existing != null) {
        if (existing.readNullable<String>('completion_snapshot_id') == null ||
            existing.read<String>('relation_type') != relationType) {
          throw StateError('batch_completion_contract_conflict');
        }
        return;
      }
      final mutations = await _db.customSelect('''
        select id from local_sync_mutations
        where local_sync_batch_id = ? order by client_sequence, id
      ''', variables: [Variable<String>(prerequisiteBatchId)]).get();
      if (mutations.isEmpty) throw StateError('prerequisite_batch_empty');
      final snapshotId = AppUuid.v7();
      for (final mutation in mutations) {
        final mutationId = mutation.read<String>('id');
        await addBatchDependency(
          prerequisiteMutationId: mutationId,
          dependentBatchId: dependentBatchId,
          relationType: relationType,
        );
      }
      await _db.customStatement('''
        update local_sync_batch_dependencies
        set completion_snapshot_id = ?
        where dependent_batch_id = ? and prerequisite_mutation_id in (
          select id from local_sync_mutations where local_sync_batch_id = ?
        )
      ''', [snapshotId, dependentBatchId, prerequisiteBatchId]);
    });
  }

  Future<void> requireDedicatedDependentBatch(String batchId) async {
    final row = await _db.customSelect('''
      select count(*) as mutation_count from local_sync_mutations
      where local_sync_batch_id = ?
    ''', variables: [Variable<String>(batchId)]).getSingle();
    if (row.read<int>('mutation_count') != 1) {
      throw StateError('dedicated_dependent_batch_required');
    }
  }

  Future<BatchDependencyReadiness> getBatchDependencyReadiness(
    String dependentBatchId,
  ) async {
    final rows = await _db.customSelect('''
      select d.dependent_batch_id, p.local_sync_batch_id as source_batch_id,
             p.status, p.error_code, source.skipped_count
      from local_sync_batch_dependencies d
      join local_sync_mutations p on p.id = d.prerequisite_mutation_id
      join local_sync_batches source on source.id = p.local_sync_batch_id
    ''').get();
    final byDependent = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final data = Map<String, dynamic>.from(row.data);
      byDependent
          .putIfAbsent(data['dependent_batch_id'] as String, () => [])
          .add(data);
    }
    final visiting = <String>{};
    BatchDependencyReadiness visit(String batchId) {
      if (!visiting.add(batchId)) return BatchDependencyReadiness.blocked;
      var state = BatchDependencyReadiness.ready;
      for (final edge in byDependent[batchId] ?? const []) {
        final status = edge['status'] as String;
        final skipped = edge['skipped_count'] as int;
        final upstream = visit(edge['source_batch_id'] as String);
        if (upstream == BatchDependencyReadiness.blocked ||
            status == 'conflict' ||
            status == 'rejected' ||
            status == 'skipped' ||
            edge['error_code'] == 'cash_movement_ack_ambiguous' ||
            skipped > 0) {
          state = BatchDependencyReadiness.blocked;
          break;
        }
        if (upstream == BatchDependencyReadiness.waiting ||
            status != 'applied') {
          state = BatchDependencyReadiness.waiting;
        }
      }
      visiting.remove(batchId);
      return state;
    }

    return visit(dependentBatchId);
  }

  /// Stable scheduler evidence: no retry count, transient timestamp, or runner
  /// return value participates in progress detection.
  Future<(int applied, int eligibleDependents)> getDependencyProgress({
    required String businessId,
    required String branchId,
  }) async {
    final row = await _db.customSelect('''
      select
        (select count(*) from local_sync_mutations m
         join local_sync_batches source on source.id = m.local_sync_batch_id
         where m.business_id = ?
           and (m.branch_id = ? or m.branch_id is null)
           and m.status = 'applied'
           and source.skipped_count = 0
           and exists (select 1 from local_sync_batch_dependencies d
                       where d.prerequisite_mutation_id = m.id)) as applied,
        (select count(*) from local_sync_batches b
         where b.business_id = ? and (b.branch_id = ? or b.branch_id is null)
           and b.status in ('pending', 'error')
           and exists (select 1 from local_sync_batch_dependencies d
                       where d.dependent_batch_id = b.id)
           and not exists (
             select 1 from local_sync_batch_dependencies d
             join local_sync_mutations p on p.id = d.prerequisite_mutation_id
             join local_sync_batches source on source.id = p.local_sync_batch_id
             where d.dependent_batch_id = b.id
               and (p.status <> 'applied' or source.skipped_count > 0)
           )) as eligible_dependents
    ''', variables: [
      Variable<String>(businessId),
      Variable<String>(branchId),
      Variable<String>(businessId),
      Variable<String>(branchId),
    ]).getSingle();
    return (row.read<int>('applied'), row.read<int>('eligible_dependents'));
  }

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
    await _ensureOutboxUniqueIndexes();

    if (mutations.isEmpty) {
      throw ArgumentError('No se puede crear un batch sin mutaciones.');
    }

    final localBatchId = AppUuid.v7();
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      await _customStatement(
        _db,
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

  /// Reuse only a complete, scoped POS batch. The sale mutation is the durable
  /// anchor; an older orphan batch without it cannot claim this sale.
  Future<LocalSyncEnqueueResult?> findExistingPosSaleBatch({
    required String businessId,
    required String branchId,
    required String profileId,
    required String saleId,
    required List<LocalSyncMutationDraft> mutations,
    required int itemCount,
    required int paymentCount,
  }) =>
      _findExistingEntityBatch(
        businessId: businessId,
        branchId: branchId,
        profileId: profileId,
        domain: 'pos',
        rootTable: 'sales',
        rootId: saleId,
        rootMetadataKey: 'sale_id',
        mutations: mutations,
        itemCount: itemCount,
        paymentCount: paymentCount,
      );

  Future<LocalSyncEnqueueResult?> findExistingPurchaseBatch({
    required String businessId,
    required String branchId,
    required String profileId,
    required String purchaseId,
    required List<LocalSyncMutationDraft> mutations,
    required int itemCount,
  }) =>
      _findExistingEntityBatch(
        businessId: businessId,
        branchId: branchId,
        profileId: profileId,
        domain: 'purchases',
        rootTable: 'purchases',
        rootId: purchaseId,
        rootMetadataKey: 'purchase_id',
        mutations: mutations,
        itemCount: itemCount,
      );

  /// A root mutation anchors one batch. Reuse only when all expected children
  /// still belong to that batch; a superseded batch is retried as a new one.
  Future<LocalSyncEnqueueResult?> _findExistingEntityBatch({
    required String businessId,
    required String branchId,
    required String profileId,
    required String domain,
    required String rootTable,
    required String rootId,
    required String rootMetadataKey,
    required List<LocalSyncMutationDraft> mutations,
    required int itemCount,
    int? paymentCount,
  }) async {
    final rootMutation = mutations.singleWhere(
      (mutation) =>
          mutation.entityTable == rootTable && mutation.entityId == rootId,
    );
    final match = await _db.customSelect('''
      select b.id, b.client_batch_id, b.business_id, b.branch_id,
             b.profile_id, b.domain, b.direction, b.status,
             b.mutation_count, b.metadata_json
      from local_sync_mutations m
      join local_sync_batches b on b.id = m.local_sync_batch_id
      where m.idempotency_key = ?
      limit 1
    ''', variables: [
      Variable<String>(rootMutation.idempotencyKey)
    ]).getSingleOrNull();
    if (match == null) return null;

    final batch = match.data;
    final batchId = batch['id'] as String;
    final clientBatchId = batch['client_batch_id'] as String;
    if (batch['status'] == 'superseded') return null;
    final conflict = '${domain}_batch_structure_conflict';
    Map<String, dynamic> metadata;
    try {
      metadata = Map<String, dynamic>.from(
        jsonDecode(batch['metadata_json'] as String) as Map,
      );
    } catch (_) {
      throw StateError(conflict);
    }
    if (batch['business_id'] != businessId ||
        batch['branch_id'] != branchId ||
        batch['profile_id'] != profileId ||
        batch['domain'] != domain ||
        batch['direction'] != 'upload' ||
        !const {
          'pending',
          'uploading',
          'error',
          'partial',
          'conflict',
          'completed'
        }.contains(batch['status']) ||
        batch['mutation_count'] != mutations.length ||
        metadata[rootMetadataKey] != rootId ||
        metadata['item_count'] != itemCount ||
        (paymentCount != null && metadata['payment_count'] != paymentCount)) {
      throw StateError(conflict);
    }

    final existingRows = await _db.customSelect('''
      select idempotency_key, entity_table, entity_id, operation,
             client_batch_id, business_id, branch_id
      from local_sync_mutations where local_sync_batch_id = ?
    ''', variables: [Variable<String>(batchId)]).get();
    final expected = {
      for (final mutation in mutations) mutation.idempotencyKey: mutation
    };
    if (expected.length != mutations.length ||
        existingRows.length != mutations.length ||
        existingRows.any((row) {
          final data = row.data;
          final mutation = expected[data['idempotency_key']];
          return mutation == null ||
              data['entity_table'] != mutation.entityTable ||
              data['entity_id'] != mutation.entityId ||
              data['operation'] != mutation.operation ||
              data['client_batch_id'] != clientBatchId ||
              data['business_id'] != businessId ||
              data['branch_id'] != branchId;
        })) {
      throw StateError(conflict);
    }
    return LocalSyncEnqueueResult(
      localBatchId: batchId,
      clientBatchId: clientBatchId,
      domain: domain,
      mutationCount: mutations.length,
    );
  }

  Future<void> _ensureOutboxUniqueIndexes() async {
    await _customStatement(
      _db,
      '''
      create unique index if not exists ux_local_sync_batches_client_batch_id
      on local_sync_batches(client_batch_id)
      ''',
    );

    await _customStatement(
      _db,
      '''
      create unique index if not exists ux_local_sync_mutations_idempotency_key
      on local_sync_mutations(idempotency_key)
      ''',
    );

    await _customStatement(
      _db,
      '''
      create unique index if not exists ux_local_sync_mutations_client_mutation_id
      on local_sync_mutations(client_mutation_id)
      ''',
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
    final pinned = await _db.customSelect('''
      select m.local_sync_batch_id from local_sync_mutations m
      where m.idempotency_key = ?
        and exists (select 1 from local_sync_batch_dependencies d
                    where d.prerequisite_mutation_id = m.id)
      limit 1
    ''', variables: [
      Variable<String>(mutation.idempotencyKey)
    ]).getSingleOrNull();
    if (pinned != null &&
        pinned.read<String>('local_sync_batch_id') != localBatchId) {
      throw StateError('prerequisite_mutation_batch_is_pinned');
    }
    final existing = await _db.customSelect('''
      select m.local_sync_batch_id, m.status, m.business_id, m.branch_id,
             m.entity_table, m.entity_id, m.operation,
             b.status as batch_status
      from local_sync_mutations m
      join local_sync_batches b on b.id = m.local_sync_batch_id
      where m.idempotency_key = ? limit 1
    ''', variables: [
      Variable<String>(mutation.idempotencyKey)
    ]).getSingleOrNull();
    if (existing != null) {
      if (existing.read<String>('local_sync_batch_id') == localBatchId) {
        // A retry of this batch must preserve its mutation status and payload.
        return;
      }
      final old = existing.data;
      final explicitlySuperseded = old['batch_status'] == 'superseded' &&
          old['status'] == 'superseded' &&
          old['business_id'] == (mutation.businessId ?? fallbackBusinessId) &&
          old['branch_id'] == (mutation.branchId ?? fallbackBranchId) &&
          old['entity_table'] == mutation.entityTable &&
          old['entity_id'] == mutation.entityId &&
          old['operation'] == mutation.operation;
      if (!explicitlySuperseded) {
        throw StateError('mutation_batch_identity_conflict');
      }
    }
    await _customStatement(
      _db,
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
        client_sequence = excluded.client_sequence,
        business_id = excluded.business_id,
        branch_id = excluded.branch_id,
        app_device_id = excluded.app_device_id,
        profile_id = excluded.profile_id,
        entity_table = excluded.entity_table,
        entity_id = excluded.entity_id,
        operation = excluded.operation,
        payload_json = excluded.payload_json,
        before_payload_json = excluded.before_payload_json,
        changed_fields_json = excluded.changed_fields_json,
        base_version = excluded.base_version,
        base_updated_at = excluded.base_updated_at,
        status = excluded.status,
        retry_count = local_sync_mutations.retry_count,
        metadata_json = excluded.metadata_json,
        last_error = null,
        error_code = null,
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
    String? branchId,
    int limit = 20,
  }) async {
    final whereDomain = domain == null ? '' : 'and domain = ?';
    final whereBranch = branchId == null ? '' : 'and branch_id = ?';

    final variables = <Variable>[
      Variable<String>(businessId),
      if (domain != null) Variable<String>(domain),
      if (branchId != null) Variable<String>(branchId),
      Variable<int>(limit),
    ];

    final rows = await _db.customSelect(
      '''
          select *
          from local_sync_batches
          where business_id = ?
            and status in ('pending', 'error')
            $whereDomain
            $whereBranch
            and not exists (
              with recursive prerequisites(mutation_id) as (
                select d.prerequisite_mutation_id
                from local_sync_batch_dependencies d
                where d.dependent_batch_id = local_sync_batches.id
                union
                select d.prerequisite_mutation_id
                from prerequisites prior
                join local_sync_mutations p on p.id = prior.mutation_id
                join local_sync_batch_dependencies d
                  on d.dependent_batch_id = p.local_sync_batch_id
              )
              select 1 from prerequisites required
              join local_sync_mutations p on p.id = required.mutation_id
              join local_sync_batches source on source.id = p.local_sync_batch_id
              where p.status <> 'applied' or source.skipped_count > 0
            )
          order by
            case when ? = 'cash' then
              case
                when exists (select 1 from local_sync_mutations m
                  where m.local_sync_batch_id = local_sync_batches.id
                    and (m.entity_table = 'cash_registers'
                      or (m.entity_table = 'cash_sessions'
                        and not (m.operation = 'update'
                          and json_extract(m.payload_json, '\$.status') = 'closed'))))
                  then 1
                when exists (select 1 from local_sync_mutations m
                  where m.local_sync_batch_id = local_sync_batches.id
                    and m.entity_table = 'cash_movements') then 2
                when exists (select 1 from local_sync_mutations m
                  where m.local_sync_batch_id = local_sync_batches.id
                    and m.entity_table = 'cash_sessions') then 3
                else 4
              end
            else 0 end,
            created_at asc
          limit ?
          ''',
      variables: [
        ...variables.sublist(0, variables.length - 1),
        Variable<String>(domain ?? ''),
        variables.last
      ],
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

  Future<bool> hasMutationForEntity({
    required String businessId,
    required String domain,
    required String entityTable,
    required String entityId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select m.id
      from local_sync_mutations m
      join local_sync_batches b on b.id = m.local_sync_batch_id
      where b.business_id = ?
        and b.domain = ?
        and m.entity_table = ?
        and m.entity_id = ?
        and (
          (
            b.status in ('pending', 'uploading')
            and m.status in ('pending', 'error')
          )
          or (
            b.status = 'completed'
            and m.status = 'applied'
          )
          or (
            b.status = 'partial'
            and m.status = 'applied'
          )
        )
      limit 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(domain),
        Variable<String>(entityTable),
        Variable<String>(entityId),
      ],
    ).get();

    return rows.isNotEmpty;
  }

  Future<int> countPendingMutations({
    required String businessId,
    String? domain,
    String? branchId,
  }) async {
    final domainJoin = domain == null ? '' : 'and b.domain = ?';
    final branchJoin = branchId == null ? '' : 'and b.branch_id = ?';

    final variables = <Variable>[
      Variable<String>(businessId),
      if (domain != null) Variable<String>(domain),
      if (branchId != null) Variable<String>(branchId),
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
            $branchJoin
          ''',
      variables: variables,
    ).getSingle();

    return (row.data['total'] as int?) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getProductiveStatusRows({
    required String businessId,
    required String branchId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        b.id as batch_id,
        b.domain,
        b.status as batch_status,
        m.entity_table,
        m.entity_id,
        m.status as mutation_status
      from local_sync_batches b
      join local_sync_mutations m
        on m.local_sync_batch_id = b.id
      where b.business_id = ?
        and (
          b.branch_id = ?
          or (b.domain = 'catalog' and b.branch_id is null)
        )
        and (
          b.status in ('pending', 'uploading', 'error', 'partial', 'conflict')
          or m.status in (
            'pending',
            'error',
            'conflict',
            'rejected'
          )
        )
      order by b.created_at, m.client_sequence, m.created_at
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(branchId),
      ],
      readsFrom: {
        _db.localSyncBatches,
        _db.localSyncMutations,
      },
    ).get();

    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  Future<void> markBatchUploading(String localBatchId) async {
    await _updateBatchStatus(localBatchId, 'uploading');
  }

  /// Retire only a legacy WEIGHT POS batch whose mutations were all moved by
  /// the old cross-batch upsert. Never infer recovery from a partial payload.
  Future<bool> supersedeLegacyEmptyWeightedPosBatch({
    required String localBatchId,
    required String businessId,
    String? branchId,
  }) =>
      _db.transaction(() async {
        final row = await _db.customSelect('''
          select business_id, branch_id, domain, direction, status,
                 metadata_json
          from local_sync_batches where id = ?
        ''', variables: [Variable<String>(localBatchId)]).getSingleOrNull();
        if (row == null) return false;
        final batch = row.data;
        Map<String, dynamic> metadata;
        try {
          metadata = Map<String, dynamic>.from(
            jsonDecode(batch['metadata_json'] as String) as Map,
          );
        } catch (_) {
          return false;
        }
        if (batch['business_id'] != businessId ||
            (branchId != null && batch['branch_id'] != branchId) ||
            batch['domain'] != 'pos' ||
            batch['direction'] != 'upload' ||
            !const {'pending', 'error'}.contains(batch['status']) ||
            metadata['monetary_contract_version'] != 'exact_weight_sale_v1' ||
            metadata['sale_id'] is! String ||
            (metadata['sale_id'] as String).trim().isEmpty) {
          return false;
        }
        final count = await _db.customSelect('''
          select count(*) as total from local_sync_mutations
          where local_sync_batch_id = ?
        ''', variables: [Variable<String>(localBatchId)]).getSingle();
        if (count.read<int>('total') != 0) return false;
        final now = DateTime.now().toUtc();
        await _customStatement(_db, '''
          update local_sync_batches
          set status = 'superseded',
              last_error = 'legacy_empty_pos_batch_orphan',
              updated_at = ?
          where id = ? and status in ('pending', 'error')
        ''', [now, localBatchId]);
        return true;
      });

  Future<void> markBatchCompleted({
    required String localBatchId,
    String? serverSyncBatchId,
    int? appliedCount,
    int? skippedCount,
    int? conflictCount,
    int? errorCount,
  }) async {
    final now = DateTime.now().toUtc();

    await _customStatement(
      _db,
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

    await _customStatement(
      _db,
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

    await _customStatement(
      _db,
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

    await _customStatement(
      _db,
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

    await _customStatement(
      _db,
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

    await _customStatement(
      _db,
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

    await _customStatement(
      _db,
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
