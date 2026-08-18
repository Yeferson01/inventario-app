import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../models/catalog_entity_reconciliation_models.dart';

class CatalogEntitySyncStateResolver {
  CatalogEntitySyncStateResolver(this._db);

  final AppDatabase _db;

  Future<CatalogEntityReconciliationClassification> classify({
    required String businessId,
    required String entityTable,
    required String entityId,
    required Object? syncStatus,
    Object? localStatus,
    Object? localUpdatedAt,
  }) async {
    final hasDirtyFlag = _hasDirtyFlag(
      entityTable: entityTable,
      syncStatus: syncStatus,
      localStatus: localStatus,
    );
    final evidence = await _db.customSelect(
      '''
      select
        m.status as mutation_status,
        m.uploaded_at as mutation_uploaded_at,
        b.status as batch_status,
        b.uploaded_at as batch_uploaded_at
      from local_sync_mutations m
      left join local_sync_batches b on b.id = m.local_sync_batch_id
      where m.business_id = ?
        and m.entity_table = ?
        and m.entity_id = ?
        and (b.id is null or (b.business_id = ? and b.domain = 'catalog'))
      order by m.created_at desc
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(entityTable),
        Variable<String>(entityId),
        Variable<String>(businessId),
      ],
      readsFrom: {
        _db.localSyncMutations,
        _db.localSyncBatches,
      },
    ).get();

    if (evidence.isEmpty) {
      return CatalogEntityReconciliationClassification(
        state: hasDirtyFlag
            ? CatalogEntityReconciliationState.dirtyWithoutOutbox
            : CatalogEntityReconciliationState.cleanRemoteSynced,
        hasDirtyFlag: hasDirtyFlag,
        recognizedAt: null,
      );
    }

    var allRemotelyApplied = true;
    var allClearlyPending = true;
    DateTime? recognizedAt;
    for (final row in evidence) {
      final mutationStatus = row.readNullable<String>('mutation_status');
      final batchStatus = row.readNullable<String>('batch_status');
      final remotelyApplied =
          mutationStatus == 'applied' && batchStatus == 'completed';
      if (!remotelyApplied) {
        allRemotelyApplied = false;
      } else {
        final timestamp = _dateTime(
          row.data['mutation_uploaded_at'] ?? row.data['batch_uploaded_at'],
        );
        if (timestamp != null &&
            (recognizedAt == null || timestamp.isAfter(recognizedAt))) {
          recognizedAt = timestamp;
        }
      }
      if (mutationStatus != 'pending' || batchStatus != 'pending') {
        allClearlyPending = false;
      }
    }

    if (allRemotelyApplied) {
      final entityUpdatedAt = _dateTime(localUpdatedAt);
      if (hasDirtyFlag &&
          recognizedAt != null &&
          entityUpdatedAt != null &&
          entityUpdatedAt.isAfter(recognizedAt)) {
        return CatalogEntityReconciliationClassification(
          state: CatalogEntityReconciliationState.dirtyWithoutOutbox,
          hasDirtyFlag: true,
          recognizedAt: recognizedAt,
        );
      }
      return CatalogEntityReconciliationClassification(
        state: CatalogEntityReconciliationState.remotelyApplied,
        hasDirtyFlag: hasDirtyFlag,
        recognizedAt: recognizedAt,
      );
    }
    return CatalogEntityReconciliationClassification(
      state: allClearlyPending
          ? CatalogEntityReconciliationState.pendingLocal
          : CatalogEntityReconciliationState.transportAmbiguous,
      hasDirtyFlag: hasDirtyFlag,
      recognizedAt: recognizedAt,
    );
  }

  bool _hasDirtyFlag({
    required String entityTable,
    required Object? syncStatus,
    required Object? localStatus,
  }) {
    if (entityTable == 'product_barcodes') {
      final sync = syncStatus?.toString().trim().toLowerCase();
      final local = localStatus?.toString().trim().toLowerCase();
      return sync != 'synced' || (local != null && local != 'clean');
    }
    return syncStatus is! int || syncStatus != SyncStatus.synced.index;
  }

  DateTime? _dateTime(Object? value) {
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is int) {
      final milliseconds = value.abs() < 100000000000 ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }
}
