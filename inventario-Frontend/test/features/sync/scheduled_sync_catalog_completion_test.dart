import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/catalog/application/catalog_sync_service.dart';
import 'package:inventario_frontend/features/catalog/data/models/catalog_remote_models.dart';
import 'package:inventario_frontend/features/sync/application/catalog_sync_upload_service.dart';
import 'package:inventario_frontend/features/sync/application/scheduled_sync_policy.dart';
import 'package:inventario_frontend/features/sync/application/scheduled_sync_service.dart';
import 'package:inventario_frontend/features/sync/application/scheduled_sync_state_store.dart';
import 'package:inventario_frontend/features/sync/data/models/catalog_upload_models.dart';

void main() {
  test('scheduled sync does not complete its slot for a resumable catalog',
      () async {
    final stateStore = _MemoryScheduledSyncStateStore();
    final service = ScheduledSyncService(
      catalogUploadService: _NoopCatalogUploadService(),
      catalogPullService: _IncompleteCatalogSyncService(),
      policy: const ScheduledSyncPolicy(),
      stateStore: stateStore,
    );

    final result = await service.runIfDue(
      businessId: 'business-1',
      now: DateTime(2026, 8, 25, 11),
    );

    expect(result.didRun, isTrue);
    expect(result.reason, contains('incompleto'));
    expect(stateStore.completedSlots, isEmpty);
    expect(result.catalogPullResult?['status'], 'incomplete');
  });
}

class _NoopCatalogUploadService implements CatalogSyncUploadService {
  @override
  Future<CatalogUploadRunResult> uploadPendingCatalogBatches({
    required String businessId,
    int batchLimit = 10,
  }) async {
    return const CatalogUploadRunResult(
      batchesChecked: 0,
      batchesUploaded: 0,
      batchesCompleted: 0,
      batchesPartial: 0,
      batchesFailed: 0,
      mutationsUploaded: 0,
    );
  }
}

class _IncompleteCatalogSyncService implements CatalogSyncService {
  @override
  Future<CatalogSyncRunResult> pullCatalogDelta({
    required String businessId,
    int pageLimit = 500,
    int maxPages = 20,
  }) async {
    return const CatalogSyncRunResult(
      pagesPulled: 20,
      recordsReceived: 10000,
      recordsApplied: 10000,
      masterProductsUpserted: 10000,
      productBarcodesUpserted: 0,
      ignoredRecords: 0,
      status: CatalogSyncRunStatus.incomplete,
      resumed: false,
      committedCursorAdvanced: false,
      nextPageTokenPresent: true,
    );
  }
}

class _MemoryScheduledSyncStateStore implements ScheduledSyncStateStore {
  final Set<String> completedSlots = {};
  Map<String, dynamic>? lastResult;

  @override
  Future<Set<String>> getCompletedSlotKeys() async => completedSlots;

  @override
  Future<Map<String, dynamic>?> getLastResult() async => lastResult;

  @override
  Future<void> markSlotCompleted(String slotKey) async {
    completedSlots.add(slotKey);
  }

  @override
  Future<void> saveLastResult(Map<String, dynamic> result) async {
    lastResult = result;
  }
}
