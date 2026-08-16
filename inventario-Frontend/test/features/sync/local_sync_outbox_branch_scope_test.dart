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
}
