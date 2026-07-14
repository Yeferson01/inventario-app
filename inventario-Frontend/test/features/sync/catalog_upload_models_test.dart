import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/data/models/catalog_upload_models.dart';

void main() {
  group('CatalogUploadBatchResult', () {
    test('parses completed process result', () {
      final result = CatalogUploadBatchResult.fromProcessResult(
        localBatchId: 'local-batch-1',
        serverBatchId: 'server-batch-1',
        fallbackMutationCount: 2,
        value: {
          'status': 'completed',
          'mutation_count': 2,
          'applied_count': 2,
          'skipped_count': 0,
          'conflict_count': 0,
          'error_count': 0,
        },
      );

      expect(result.completed, isTrue);
      expect(result.partial, isFalse);
      expect(result.appliedCount, equals(2));
      expect(result.errorCount, equals(0));
    });

    test('parses partial process result', () {
      final result = CatalogUploadBatchResult.fromProcessResult(
        localBatchId: 'local-batch-1',
        serverBatchId: 'server-batch-1',
        fallbackMutationCount: 2,
        value: {
          'status': 'partial',
          'mutation_count': 2,
          'applied_count': 1,
          'skipped_count': 0,
          'conflict_count': 1,
          'error_count': 0,
        },
      );

      expect(result.completed, isFalse);
      expect(result.partial, isTrue);
      expect(result.conflictCount, equals(1));
    });
  });

  group('CatalogUploadRunResult', () {
    test('serializes run result', () {
      const result = CatalogUploadRunResult(
        batchesChecked: 2,
        batchesUploaded: 2,
        batchesCompleted: 1,
        batchesPartial: 1,
        batchesFailed: 0,
        mutationsUploaded: 4,
      );

      final json = result.toJson();

      expect(json['batches_checked'], equals(2));
      expect(json['batches_completed'], equals(1));
      expect(json['mutations_uploaded'], equals(4));
    });
  });
}
