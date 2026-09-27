import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/sync/data/datasources/local_sync_outbox_dao.dart';

void main() {
  late AppDatabase db;
  late LocalSyncOutboxDao dao;

  setUp(() {
    db = AppDatabase.executor(NativeDatabase.memory());
    dao = LocalSyncOutboxDao(db);
  });
  tearDown(() => db.close());

  Future<void> batch(String id, List<String> mutations,
      {String domain = 'purchases', String branch = 'branch'}) async {
    await db.customStatement('''
      insert into local_sync_batches
        (id, client_batch_id, business_id, branch_id, domain, mutation_count)
      values (?, ?, 'business', ?, ?, ?)
    ''', [id, id, branch, domain, mutations.length]);
    for (var i = 0; i < mutations.length; i++) {
      final mutation = mutations[i];
      await db.customStatement('''
        insert into local_sync_mutations
          (id, local_sync_batch_id, client_batch_id, client_mutation_id,
           client_sequence, business_id, branch_id, entity_table, entity_id,
           operation, payload_json, idempotency_key)
        values (?, ?, ?, ?, ?, 'business', ?, 'purchases', ?, 'insert', '{}', ?)
      ''', [mutation, id, id, mutation, i, branch, mutation, mutation]);
    }
  }

  Future<List<String>> pending() async => (await dao.getPendingBatches(
        businessId: 'business',
        branchId: 'branch',
        limit: 20,
      ))
          .map((row) => row['id'] as String)
          .toList();

  test('cross-batch edges are idempotent, durable, and gate whole batches',
      () async {
    await batch('P', ['p1', 'p2']);
    await batch('X', ['x']);
    await dao.dependOnBatchCompletion(
      prerequisiteBatchId: 'P',
      dependentBatchId: 'X',
      relationType: 'payment',
    );
    await dao.dependOnBatchCompletion(
      prerequisiteBatchId: 'P',
      dependentBatchId: 'X',
      relationType: 'payment',
    );
    expect(await pending(), ['P']);
    expect(await dao.getBatchDependencyReadiness('X'),
        BatchDependencyReadiness.waiting);
    final waitingMutation = await db
        .customSelect(
            "select retry_count from local_sync_mutations where id = 'x'")
        .getSingle();
    expect(waitingMutation.read<int>('retry_count'), 0);
    final originalBatch = await db
        .customSelect(
            "select mutation_count from local_sync_batches where id = 'X'")
        .getSingle();
    expect(originalBatch.read<int>('mutation_count'), 1);
    await dao.markMutationApplied(localMutationId: 'p1');
    expect(await pending(), ['P']);
    await dao.markMutationApplied(localMutationId: 'p2');
    expect(await pending(), ['P', 'X']);
    expect(await dao.getBatchDependencyReadiness('X'),
        BatchDependencyReadiness.ready);
    final edges = await db
        .customSelect('select count(*) as n from local_sync_batch_dependencies')
        .getSingle();
    expect(edges.read<int>('n'), 2);
    expect(await dao.getMutationsForBatch('X'), hasLength(1));
    // A later mutation cannot silently expand the frozen completion contract.
    await db.customStatement('''
      insert into local_sync_mutations
        (id, local_sync_batch_id, client_batch_id, client_mutation_id,
         client_sequence, business_id, branch_id, entity_table, entity_id,
         operation, payload_json, idempotency_key)
      values ('p3', 'P', 'P', 'p3', 3, 'business', 'branch',
              'purchases', 'p3', 'insert', '{}', 'p3')
    ''');
    await dao.dependOnBatchCompletion(
      prerequisiteBatchId: 'P',
      dependentBatchId: 'X',
      relationType: 'payment',
    );
    await expectLater(
      dao.addBatchDependency(
          prerequisiteMutationId: 'p3',
          dependentBatchId: 'X',
          relationType: 'payment'),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', 'batch_completion_snapshot_is_frozen')),
    );
  });

  test('same-batch, cycles, and non-dedicated financial batches fail closed',
      () async {
    await batch('A', ['a']);
    await batch('B', ['b', 'b2']);
    await expectLater(
      dao.addBatchDependency(
          prerequisiteMutationId: 'a',
          dependentBatchId: 'A',
          relationType: 'test'),
      throwsA(isA<StateError>().having(
          (e) => e.message, 'message', 'intra_batch_dependency_not_supported')),
    );
    await dao.addBatchDependency(
        prerequisiteMutationId: 'a',
        dependentBatchId: 'B',
        relationType: 'test');
    await expectLater(
      dao.addBatchDependency(
          prerequisiteMutationId: 'b',
          dependentBatchId: 'A',
          relationType: 'test'),
      throwsA(isA<StateError>()
          .having((e) => e.message, 'message', 'dependency_cycle')),
    );
    await expectLater(
        dao.requireDedicatedDependentBatch('B'), throwsStateError);
    await dao.requireDedicatedDependentBatch('A');
  });

  test('blocked prerequisite propagates through P to X to CM', () async {
    await batch('P', ['p']);
    await batch('X', ['x']);
    await batch('CM', ['cm'], domain: 'cash');
    await dao.dependOnBatchCompletion(
        prerequisiteBatchId: 'P',
        dependentBatchId: 'X',
        relationType: 'payment');
    await dao.dependOnBatchCompletion(
        prerequisiteBatchId: 'X',
        dependentBatchId: 'CM',
        relationType: 'cash_effect');
    expect(await pending(), ['P']);
    await dao.markMutationConflict(localMutationId: 'p');
    expect(await dao.getBatchDependencyReadiness('CM'),
        BatchDependencyReadiness.blocked);
    expect(await pending(), ['P']);
    // Even inconsistent persisted intermediate state cannot bypass upstream.
    await dao.markMutationApplied(localMutationId: 'x');
    expect(await dao.getBatchDependencyReadiness('CM'),
        BatchDependencyReadiness.blocked);
    expect(await pending(), ['P']);
    await db.customStatement(
        "update local_sync_mutations set status = 'pending' where id = 'x'");
    await dao.markMutationApplied(localMutationId: 'p');
    expect(await pending(), ['P', 'X']);
    await dao.markMutationApplied(localMutationId: 'x');
    expect(await pending(), ['P', 'X', 'CM']);
  });

  test('scope and skipped status do not grant eligibility', () async {
    await batch('P', ['p']);
    await batch('X', ['x']);
    await dao.addBatchDependency(
        prerequisiteMutationId: 'p',
        dependentBatchId: 'X',
        relationType: 'test');
    await db.customStatement(
        "update local_sync_mutations set status = 'skipped' where id = 'p'");
    expect(await pending(), ['P']);
    expect(await dao.getBatchDependencyReadiness('X'),
        BatchDependencyReadiness.blocked);
    await db.customStatement('''
      update local_sync_mutations set status = 'applied' where id = 'p'
    ''');
    await db.customStatement('''
      update local_sync_batches set skipped_count = 1 where id = 'P'
    ''');
    expect(await pending(), ['P']);
    expect(await dao.getBatchDependencyReadiness('X'),
        BatchDependencyReadiness.blocked);
    await batch('OTHER', ['other'], branch: 'other-branch');
    expect(await pending(), ['P']);
    await expectLater(
      dao.addBatchDependency(
          prerequisiteMutationId: 'p',
          dependentBatchId: 'OTHER',
          relationType: 'test'),
      throwsA(isA<StateError>().having((e) => e.message, 'message',
          'cross_branch_dependency_not_supported')),
    );
  });

  test('dependency ordering and snapshot marker survive database restart',
      () async {
    await db.close();
    final directory = await Directory.systemTemp.createTemp('c4b1b-graph-');
    addTearDown(() async {
      await db.close();
      await directory.delete(recursive: true);
    });
    final file = File('${directory.path}/graph.sqlite');
    db = AppDatabase.executor(NativeDatabase(file));
    dao = LocalSyncOutboxDao(db);
    await batch('P', ['p']);
    await batch('X', ['x']);
    await dao.dependOnBatchCompletion(
      prerequisiteBatchId: 'P',
      dependentBatchId: 'X',
      relationType: 'payment',
    );
    final marker = await db.customSelect('''
      select completion_snapshot_id from local_sync_batch_dependencies
    ''').getSingle();
    expect(marker.readNullable<String>('completion_snapshot_id'), isNotNull);
    await db.close();

    db = AppDatabase.executor(NativeDatabase(file));
    dao = LocalSyncOutboxDao(db);
    expect(await pending(), ['P']);
    await dao.dependOnBatchCompletion(
      prerequisiteBatchId: 'P',
      dependentBatchId: 'X',
      relationType: 'payment',
    );
    await dao.markMutationApplied(localMutationId: 'p');
    expect(await pending(), ['P', 'X']);
  });
}
