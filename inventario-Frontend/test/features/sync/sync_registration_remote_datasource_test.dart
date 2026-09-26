import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/data/datasources/sync_registration_remote_datasource.dart';

void main() {
  test('batch registration calls the pending-only RPC and uses canonical id',
      () async {
    final calls = <String>[];
    final source =
        SyncRegistrationRemoteDataSource.withInvoker((name, params) async {
      calls.add(name);
      expect(params['p_batch'], {'id': 'proposed', 'status': 'pending'});
      return {'id': 'canonical', 'status': 'completed', 'inserted': false};
    });

    final id =
        await source.registerBatch({'id': 'proposed', 'status': 'pending'});

    expect(id, 'canonical');
    expect(calls, ['register_pending_sync_batch']);
  });

  test('bulk mutation registration preserves order and canonical batch scope',
      () async {
    final calls = <String>[];
    final source =
        SyncRegistrationRemoteDataSource.withInvoker((name, params) async {
      calls.add(name);
      expect(params['p_mutations'], [
        {'id': 'one'},
        {'id': 'two'}
      ]);
      return [
        {'id': 'remote-one', 'sync_batch_id': 'batch'},
        {'id': 'remote-two', 'sync_batch_id': 'batch'},
      ];
    });

    await source.registerMutations(
      [
        {'id': 'one'},
        {'id': 'two'}
      ],
      expectedBatchId: 'batch',
    );

    expect(calls, ['register_pending_sync_mutations']);
  });

  test('malformed or cross-batch registration response fails closed', () async {
    final source = SyncRegistrationRemoteDataSource.withInvoker(
      (name, params) async => [
        {'id': 'remote', 'sync_batch_id': 'other'}
      ],
    );

    await expectLater(
      source.registerMutations([
        {'id': 'one'}
      ], expectedBatchId: 'batch'),
      throwsA(isA<FormatException>()),
    );
  });
}
