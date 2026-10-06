import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/sync/data/datasources/local_sync_outbox_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_sync_outbox_models.dart';

void main() {
  late AppDatabase database;
  late LocalSyncOutboxDao dao;

  setUp(() {
    database = AppDatabase.executor(NativeDatabase.memory());
    dao = LocalSyncOutboxDao(database);
  });

  tearDown(() => database.close());

  test(
      'idempotency key cannot move an active or applied mutation to a new batch',
      () async {
    const draft = LocalSyncMutationDraft(
      clientMutationId: 'mutation-1',
      clientSequence: 1,
      entityTable: 'products',
      entityId: 'product-1',
      operation: 'insert',
      payload: {},
      changedFields: [],
      idempotencyKey: 'product-1:insert',
    );
    final original = await dao.enqueueUploadBatch(
      businessId: 'business-a',
      domain: 'catalog',
      clientBatchId: 'batch-a',
      mutations: const [draft],
    );

    Future<void> rejectNewBatch(String clientBatchId) async {
      await expectLater(
        dao.enqueueUploadBatch(
          businessId: 'business-a',
          domain: 'catalog',
          clientBatchId: clientBatchId,
          mutations: const [draft],
        ),
        throwsA(isA<StateError>().having(
          (error) => error.message,
          'message',
          'mutation_batch_identity_conflict',
        )),
      );
      final row = await database.customSelect('''
        select m.local_sync_batch_id, m.client_batch_id, m.status,
               (select count(*) from local_sync_batches) as batch_count
        from local_sync_mutations m where m.idempotency_key = ?
      ''', variables: [Variable<String>(draft.idempotencyKey)]).getSingle();
      expect(row.read<String>('local_sync_batch_id'), original.localBatchId);
      expect(row.read<String>('client_batch_id'), original.clientBatchId);
      expect(row.read<int>('batch_count'), 1);
    }

    await rejectNewBatch('batch-b');
    await dao.markMutationApplied(
        localMutationId: (await database
                .customSelect('select id from local_sync_mutations')
                .getSingle())
            .read<String>('id'));
    await rejectNewBatch('batch-c');
    expect(
        (await database.customSelect(
          'select status from local_sync_mutations where idempotency_key = ?',
          variables: [Variable<String>(draft.idempotencyKey)],
        ).getSingle())
            .read<String>('status'),
        'applied');
  });

  test('explicitly superseded mutation may move for a clean retry', () async {
    const draft = LocalSyncMutationDraft(
      clientMutationId: 'purchase-mutation',
      clientSequence: 1,
      entityTable: 'purchases',
      entityId: 'purchase-1',
      operation: 'insert',
      payload: {},
      changedFields: [],
      idempotencyKey: 'purchase-1:insert',
    );
    final first = await dao.enqueueUploadBatch(
      businessId: 'business-a',
      branchId: 'branch-a',
      domain: 'purchases',
      clientBatchId: 'purchase-batch-a',
      mutations: const [draft],
    );
    await database.customStatement(
      "update local_sync_batches set status = 'superseded' where id = ?",
      [first.localBatchId],
    );
    await database.customStatement('''
      update local_sync_mutations set status = 'superseded'
      where local_sync_batch_id = ?
    ''', [first.localBatchId]);

    final retry = await dao.enqueueUploadBatch(
      businessId: 'business-a',
      branchId: 'branch-a',
      domain: 'purchases',
      clientBatchId: 'purchase-batch-b',
      mutations: const [draft],
    );
    final mutation = await database.customSelect('''
      select local_sync_batch_id, client_batch_id, status
      from local_sync_mutations where idempotency_key = ?
    ''', variables: [Variable<String>(draft.idempotencyKey)]).getSingle();
    expect(mutation.read<String>('local_sync_batch_id'), retry.localBatchId);
    expect(mutation.read<String>('client_batch_id'), retry.clientBatchId);
    expect(mutation.read<String>('status'), 'pending');
  });

  test('operational pending batches and mutation counts isolate branches',
      () async {
    for (final branchId in const ['branch-x', 'branch-y']) {
      for (final domain in const ['cash', 'pos']) {
        await dao.enqueueUploadBatch(
          businessId: 'business-a',
          branchId: branchId,
          domain: domain,
          clientBatchId: '$branchId-$domain-batch',
          mutations: [
            LocalSyncMutationDraft(
              clientMutationId: '$branchId-$domain-mutation',
              clientSequence: 1,
              entityTable: '${domain}_entity',
              entityId: '$branchId-$domain-entity',
              operation: 'upsert',
              payload: const {},
              changedFields: const [],
              idempotencyKey: '$branchId-$domain-key',
            ),
          ],
        );
      }
    }

    final x = await dao.getPendingBatches(
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    final y = await dao.getPendingBatches(
      businessId: 'business-a',
      branchId: 'branch-y',
    );
    final all = await dao.getPendingBatches(businessId: 'business-a');

    expect(x, hasLength(2));
    expect(x.every((batch) => batch['branch_id'] == 'branch-x'), isTrue);
    expect(y, hasLength(2));
    expect(y.every((batch) => batch['branch_id'] == 'branch-y'), isTrue);
    expect(all, hasLength(4));

    expect(
      await dao.countPendingMutations(
        businessId: 'business-a',
        branchId: 'branch-x',
        domain: 'cash',
      ),
      1,
    );
    expect(
      await dao.countPendingMutations(
        businessId: 'business-a',
        branchId: 'branch-y',
        domain: 'pos',
      ),
      1,
    );
    expect(await dao.countPendingMutations(businessId: 'business-a'), 4);
  });

  test(
      'productive status includes business catalog and isolates operational branches',
      () async {
    Future<void> enqueue({
      required String businessId,
      required String domain,
      required String batchId,
      required String entityTable,
      String? branchId,
    }) {
      return dao.enqueueUploadBatch(
        businessId: businessId,
        branchId: branchId,
        domain: domain,
        clientBatchId: batchId,
        mutations: [
          LocalSyncMutationDraft(
            clientMutationId: '$batchId-mutation',
            clientSequence: 1,
            entityTable: entityTable,
            entityId: '$batchId-entity',
            operation: 'upsert',
            payload: const {},
            changedFields: const [],
            idempotencyKey: '$batchId-key',
          ),
        ],
      ).then((_) {});
    }

    await enqueue(
      businessId: 'business-a',
      domain: 'catalog',
      batchId: 'catalog-a',
      entityTable: 'products',
    );
    await enqueue(
      businessId: 'business-a',
      branchId: 'branch-x',
      domain: 'inventory',
      batchId: 'inventory-x',
      entityTable: 'inventory_movements',
    );
    await enqueue(
      businessId: 'business-a',
      branchId: 'branch-y',
      domain: 'inventory',
      batchId: 'inventory-y',
      entityTable: 'inventory_movements',
    );
    await enqueue(
      businessId: 'business-b',
      domain: 'catalog',
      batchId: 'catalog-b',
      entityTable: 'products',
    );

    final rows = await dao.getProductiveStatusRows(
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    final entityIds = rows.map((row) => row['entity_id']).toSet();

    expect(entityIds, hasLength(2));
    expect(
      entityIds,
      containsAll(['catalog-a-entity', 'inventory-x-entity']),
    );
    expect(entityIds, isNot(contains('inventory-y-entity')));
    expect(entityIds, isNot(contains('catalog-b-entity')));
  });
}
