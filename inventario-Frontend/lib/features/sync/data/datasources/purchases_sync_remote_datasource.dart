import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/app_uuid.dart';
import '../models/catalog_upload_models.dart';

class PurchasesSyncRemoteDataSource {
  PurchasesSyncRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<CatalogUploadBatchResult> uploadAndProcessPurchasesBatch({
    required Map<String, dynamic> localBatch,
    required List<Map<String, dynamic>> localMutations,
  }) async {
    if (localMutations.isEmpty) {
      throw ArgumentError(
          'No se puede subir un batch de compras sin mutaciones.');
    }

    final serverBatchId = AppUuid.v7();
    final localBatchId = _requiredString(localBatch, 'id');
    final businessId = _requiredString(localBatch, 'business_id');
    final clientBatchId = _requiredString(localBatch, 'client_batch_id');
    final now = DateTime.now().toUtc().toIso8601String();

    final uploadableMutations =
        await _filterAlreadyExistingPurchaseEntityInserts(
      businessId: businessId,
      localMutations: localMutations,
    );

    if (uploadableMutations.isEmpty) {
      throw StateError(
        'No quedan mutaciones de compras por subir después de filtrar duplicados existentes.',
      );
    }

    final existingMutationIds =
        await _existingServerMutationIdsByIdempotencyKey(
      businessId: businessId,
      localMutations: uploadableMutations,
    );

    await _client.from('sync_batches').upsert(
      {
        'id': serverBatchId,
        'business_id': businessId,
        'app_device_id': _string(localBatch['app_device_id']),
        'profile_id': _string(localBatch['profile_id']),
        'branch_id': _string(localBatch['branch_id']),
        'client_batch_id': clientBatchId,
        'direction': 'upload',
        'status': 'pending',
        'mutation_count': uploadableMutations.length,
        'metadata': _decodeNullableJson(localBatch['metadata_json']) ??
            {
              'source': 'flutter_purchases_upload',
              'domain': 'purchases',
            },
        'created_at': now,
        'updated_at': now,
      },
      onConflict: 'business_id,app_device_id,client_batch_id',
    );

    final serverMutations = uploadableMutations.map((mutation) {
      return {
        'id':
            existingMutationIds[_requiredString(mutation, 'idempotency_key')] ??
                AppUuid.v7(),
        'sync_batch_id': serverBatchId,
        'business_id': _requiredString(mutation, 'business_id'),
        'app_device_id': _string(mutation['app_device_id']),
        'profile_id': _string(mutation['profile_id']),
        'branch_id': _string(mutation['branch_id']),
        'client_mutation_id': _requiredString(mutation, 'client_mutation_id'),
        'client_sequence': _int(mutation['client_sequence']) ?? 1,
        'entity_table': _requiredString(mutation, 'entity_table'),
        'entity_id': _requiredString(mutation, 'entity_id'),
        'operation': _requiredString(mutation, 'operation'),
        'payload': _decodeRequiredJson(mutation['payload_json']),
        'before_payload': _decodeNullableJson(mutation['before_payload_json']),
        'changed_fields': _decodeNullableJson(mutation['changed_fields_json']),
        'base_version': _int(mutation['base_version']),
        'base_updated_at': _string(mutation['base_updated_at']),
        'status': 'pending',
        'idempotency_key': _requiredString(mutation, 'idempotency_key'),
        'metadata': _decodeNullableJson(mutation['metadata_json']) ??
            {
              'source': 'flutter_purchases_sync_mutation',
              'domain': 'purchases',
            },
        'created_at': now,
        'updated_at': now,
      };
    }).toList();

    await _client.from('sync_mutations').upsert(
          serverMutations,
          onConflict: 'business_id,idempotency_key',
        );

    final processResult = await _client.rpc(
      'process_sync_batch',
      params: {
        'p_sync_batch_id': serverBatchId,
        'p_mode': 'apply_purchases',
      },
    );

    // Purchase inventory is applied by the backend trigger when the purchases
    // sync batch transitions to completed. Flutter must not call the inventory
    // RPC here.
    return CatalogUploadBatchResult.fromProcessResult(
      localBatchId: localBatchId,
      serverBatchId: serverBatchId,
      fallbackMutationCount: uploadableMutations.length,
      value: processResult,
    );
  }

  Future<bool> allPurchaseMutationEntitiesAlreadyExist({
    required List<Map<String, dynamic>> localMutations,
  }) {
    return _allPurchaseMutationEntitiesExist(localMutations);
  }

  Future<bool> duplicatePurchasesConflictsAreIdempotent({
    required String serverBatchId,
    required List<Map<String, dynamic>> localMutations,
  }) async {
    final conflicts = await _client
        .from('sync_conflicts')
        .select('conflict_type, entity_table, entity_id, operation')
        .eq('sync_batch_id', serverBatchId);

    if (conflicts.isEmpty) {
      return false;
    }

    for (final conflict in conflicts) {
      final conflictType = _string(conflict['conflict_type']);
      final entityTable = _string(conflict['entity_table']);
      final entityId = _string(conflict['entity_id']);
      final operation = _string(conflict['operation']);

      if (conflictType != 'duplicate_key' ||
          operation != 'insert' ||
          entityId == null ||
          entityTable == null) {
        return false;
      }

      if (entityTable != 'purchases' && entityTable != 'purchase_items') {
        return false;
      }

      final exists = await _serverEntityExists(
        tableName: entityTable,
        entityId: entityId,
      );

      if (!exists) {
        return false;
      }
    }

    return _allPurchaseMutationEntitiesExist(localMutations);
  }

  Future<bool> _allPurchaseMutationEntitiesExist(
    List<Map<String, dynamic>> localMutations,
  ) async {
    for (final mutation in localMutations) {
      final entityTable = _requiredString(mutation, 'entity_table');
      final entityId = _requiredString(mutation, 'entity_id');

      if (entityTable != 'purchases' && entityTable != 'purchase_items') {
        continue;
      }

      final exists = await _serverEntityExists(
        tableName: entityTable,
        entityId: entityId,
      );

      if (!exists) {
        return false;
      }
    }

    return true;
  }

  Future<bool> _serverEntityExists({
    required String tableName,
    required String entityId,
  }) async {
    final rows =
        await _client.from(tableName).select('id').eq('id', entityId).limit(1);

    return rows.isNotEmpty;
  }

  Object _decodeRequiredJson(Object? value) {
    final decoded = _decodeNullableJson(value);

    if (decoded == null) {
      throw ArgumentError('JSON requerido ausente o inválido.');
    }

    return decoded;
  }

  Object? _decodeNullableJson(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is Map || value is List) {
      return value;
    }

    if (value is String && value.trim().isNotEmpty) {
      return jsonDecode(value);
    }

    return null;
  }

  String _requiredString(Map<String, dynamic> source, String key) {
    final value = _string(source[key]);

    if (value == null) {
      throw ArgumentError('Campo requerido ausente: $key');
    }

    return value;
  }

  String? _string(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }

  int? _int(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString());
  }

  Future<Map<String, String>> _existingServerMutationIdsByIdempotencyKey({
    required String businessId,
    required List<Map<String, dynamic>> localMutations,
  }) async {
    final keys = localMutations
        .map((mutation) => mutation['idempotency_key']?.toString().trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    if (keys.isEmpty) {
      return const <String, String>{};
    }

    final rows = await _client
        .from('sync_mutations')
        .select('id, idempotency_key')
        .eq('business_id', businessId)
        .inFilter('idempotency_key', keys);

    final result = <String, String>{};

    for (final row in rows) {
      final data = Map<String, dynamic>.from(row as Map);
      final key = data['idempotency_key']?.toString().trim();
      final id = data['id']?.toString().trim();

      if (key != null && key.isNotEmpty && id != null && id.isNotEmpty) {
        result[key] = id;
      }
    }

    return result;
  }

  Future<List<Map<String, dynamic>>>
      _filterAlreadyExistingPurchaseEntityInserts({
    required String businessId,
    required List<Map<String, dynamic>> localMutations,
  }) async {
    if (localMutations.isEmpty) {
      return localMutations;
    }

    final purchaseInsertIds = localMutations
        .where((mutation) {
          return mutation['entity_table']?.toString() == 'purchases' &&
              mutation['operation']?.toString() == 'insert';
        })
        .map((mutation) => mutation['entity_id']?.toString().trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    final purchaseItemInsertIds = localMutations
        .where((mutation) {
          return mutation['entity_table']?.toString() == 'purchase_items' &&
              mutation['operation']?.toString() == 'insert';
        })
        .map((mutation) => mutation['entity_id']?.toString().trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();

    final existingPurchaseIds = <String>{};
    final existingPurchaseItemIds = <String>{};

    if (purchaseInsertIds.isNotEmpty) {
      final rows = await _client
          .from('purchases')
          .select('id')
          .eq('business_id', businessId)
          .inFilter('id', purchaseInsertIds);

      for (final row in rows) {
        final data = Map<String, dynamic>.from(row as Map);
        final id = data['id']?.toString().trim();

        if (id != null && id.isNotEmpty) {
          existingPurchaseIds.add(id);
        }
      }
    }

    if (purchaseItemInsertIds.isNotEmpty) {
      final rows = await _client
          .from('purchase_items')
          .select('id')
          .eq('business_id', businessId)
          .inFilter('id', purchaseItemInsertIds);

      for (final row in rows) {
        final data = Map<String, dynamic>.from(row as Map);
        final id = data['id']?.toString().trim();

        if (id != null && id.isNotEmpty) {
          existingPurchaseItemIds.add(id);
        }
      }
    }

    if (existingPurchaseIds.isEmpty && existingPurchaseItemIds.isEmpty) {
      return localMutations;
    }

    return localMutations.where((mutation) {
      final entityTable = mutation['entity_table']?.toString();
      final operation = mutation['operation']?.toString();
      final entityId = mutation['entity_id']?.toString().trim();

      if (operation != 'insert' || entityId == null || entityId.isEmpty) {
        return true;
      }

      if (entityTable == 'purchases' &&
          existingPurchaseIds.contains(entityId)) {
        return false;
      }

      if (entityTable == 'purchase_items' &&
          existingPurchaseItemIds.contains(entityId)) {
        return false;
      }

      return true;
    }).toList();
  }
}
