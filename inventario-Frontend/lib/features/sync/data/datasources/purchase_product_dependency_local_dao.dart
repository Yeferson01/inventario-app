import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';

class PurchaseProductDependencyLocalDao {
  PurchaseProductDependencyLocalDao(this._db);

  final AppDatabase _db;

  Future<List<Map<String, dynamic>>> getProducts({
    required String businessId,
    required Set<String> productIds,
  }) async {
    if (productIds.isEmpty) {
      return const [];
    }

    final ids = productIds.toList(growable: false);
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _db.customSelect(
      '''
      select id, business_id, sync_status, deleted_at
      from products
      where business_id = ?
        and id in ($placeholders)
      ''',
      variables: [
        Variable<String>(businessId),
        ...ids.map(Variable<String>.new),
      ],
      readsFrom: {_db.products},
    ).get();

    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getCatalogProductMutationEvidence({
    required String businessId,
    required Set<String> productIds,
  }) async {
    if (productIds.isEmpty) {
      return const [];
    }

    final ids = productIds.toList(growable: false);
    final placeholders = List.filled(ids.length, '?').join(', ');
    final rows = await _db.customSelect(
      '''
      select
        m.entity_id as product_id,
        m.operation as mutation_operation,
        m.status as mutation_status,
        m.server_sync_mutation_id,
        m.uploaded_at as mutation_uploaded_at,
        m.error_code,
        m.last_error,
        b.status as batch_status,
        b.server_sync_batch_id,
        b.uploaded_at as batch_uploaded_at
      from local_sync_mutations m
      join local_sync_batches b
        on b.id = m.local_sync_batch_id
       and b.business_id = ?
       and b.domain = 'catalog'
      where m.business_id = ?
        and m.entity_table = 'products'
        and m.entity_id in ($placeholders)
      order by m.created_at desc
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(businessId),
        ...ids.map(Variable<String>.new),
      ],
      readsFrom: {
        _db.localSyncMutations,
        _db.localSyncBatches,
      },
    ).get();

    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }
}
