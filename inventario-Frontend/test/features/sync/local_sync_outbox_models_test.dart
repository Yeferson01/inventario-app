import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/data/models/local_sync_outbox_models.dart';

void main() {
  group('LocalSyncMutationDraft', () {
    test('parses mutation draft from json', () {
      final draft = LocalSyncMutationDraft.fromJson({
        'client_mutation_id': 'device-1:mutation:1',
        'client_sequence': 1,
        'entity_table': 'products',
        'entity_id': 'product-1',
        'operation': 'insert',
        'payload': {
          'id': 'product-1',
          'business_id': 'business-1',
          'name': 'Producto Test',
        },
        'changed_fields': ['id', 'business_id', 'name'],
        'idempotency_key': 'device-1:products:product-1:insert:1',
        'business_id': 'business-1',
      });

      expect(draft.clientMutationId, equals('device-1:mutation:1'));
      expect(draft.clientSequence, equals(1));
      expect(draft.entityTable, equals('products'));
      expect(draft.operation, equals('insert'));
      expect(draft.payload['name'], equals('Producto Test'));
      expect(draft.changedFields, contains('business_id'));
      expect(
        draft.idempotencyKey,
        equals('device-1:products:product-1:insert:1'),
      );
    });

    test('serializes payload and changed fields to json strings', () {
      const draft = LocalSyncMutationDraft(
        clientMutationId: 'device-1:mutation:1',
        clientSequence: 1,
        entityTable: 'products',
        entityId: 'product-1',
        operation: 'insert',
        payload: {
          'id': 'product-1',
          'name': 'Producto Test',
        },
        changedFields: ['id', 'name'],
        idempotencyKey: 'device-1:products:product-1:insert:1',
      );

      expect(draft.payloadJson, contains('Producto Test'));
      expect(draft.changedFieldsJson, contains('name'));
      expect(draft.toJson()['entity_table'], equals('products'));
    });

    test('throws when required field is missing', () {
      expect(
        () => LocalSyncMutationDraft.fromJson({
          'client_sequence': 1,
          'entity_table': 'products',
          'entity_id': 'product-1',
          'operation': 'insert',
          'payload': {'id': 'product-1'},
          'changed_fields': ['id'],
          'idempotency_key': 'key-1',
        }),
        throwsArgumentError,
      );
    });
  });

  group('LocalSyncEnqueueResult', () {
    test('serializes enqueue result', () {
      const result = LocalSyncEnqueueResult(
        localBatchId: 'batch-1',
        clientBatchId: 'device-1:batch:1',
        domain: 'catalog',
        mutationCount: 2,
      );

      final json = result.toJson();

      expect(json['local_batch_id'], equals('batch-1'));
      expect(json['domain'], equals('catalog'));
      expect(json['mutation_count'], equals(2));
    });
  });
}
