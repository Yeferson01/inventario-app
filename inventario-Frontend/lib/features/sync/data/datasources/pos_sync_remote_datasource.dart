import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/app_uuid.dart';
import '../models/catalog_upload_models.dart';

class PosSyncRemoteDataSource {
  PosSyncRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<CatalogUploadBatchResult> uploadAndProcessPosBatch({
    required Map<String, dynamic> localBatch,
    required List<Map<String, dynamic>> localMutations,
  }) async {
    if (localMutations.isEmpty) {
      throw ArgumentError('No se puede subir un batch POS sin mutaciones.');
    }

    final serverBatchId = AppUuid.v7();
    final localBatchId = _requiredString(localBatch, 'id');
    final businessId = _requiredString(localBatch, 'business_id');
    final clientBatchId = _requiredString(localBatch, 'client_batch_id');
    final now = DateTime.now().toUtc().toIso8601String();

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
        'mutation_count': localMutations.length,
        'metadata': _decodeNullableJson(localBatch['metadata_json']) ??
            {
              'source': 'flutter_pos_upload',
              'domain': 'pos',
            },
        'created_at': now,
        'updated_at': now,
      },
      onConflict: 'business_id,app_device_id,client_batch_id',
    );

    final serverMutations = <Map<String, dynamic>>[];

    for (final mutation in localMutations) {
      final mutationBusinessId = _requiredString(mutation, 'business_id');
      final idempotencyKey = _requiredString(mutation, 'idempotency_key');

      final existingMutationId = await _findExistingServerMutationId(
        businessId: mutationBusinessId,
        idempotencyKey: idempotencyKey,
      );

      serverMutations.add({
        // Muy importante:
        // Si la mutación ya existe en remoto, reutilizamos su id.
        // No hacerlo rompe sync_conflicts_sync_mutation_id_fkey cuando
        // esa mutación ya tiene conflictos asociados.
        'id': existingMutationId ?? AppUuid.v7(),
        'sync_batch_id': serverBatchId,
        'business_id': mutationBusinessId,
        'app_device_id': _string(mutation['app_device_id']),
        'profile_id': _string(mutation['profile_id']),
        'branch_id': _string(mutation['branch_id']),
        'client_mutation_id': _requiredString(mutation, 'client_mutation_id'),
        'client_sequence': _int(mutation['client_sequence']) ?? 1,
        'entity_table': _requiredString(mutation, 'entity_table'),
        'entity_id': _requiredString(mutation, 'entity_id'),
        'operation': _requiredString(mutation, 'operation'),
        'payload': _normalizedPosPayload(mutation),
        'before_payload': _decodeNullableJson(mutation['before_payload_json']),
        'changed_fields': _decodeNullableJson(mutation['changed_fields_json']),
        'base_version': _int(mutation['base_version']),
        'base_updated_at': _string(mutation['base_updated_at']),
        'status': 'pending',
        'idempotency_key': idempotencyKey,
        'metadata': _decodeNullableJson(mutation['metadata_json']) ??
            {
              'source': 'flutter_pos_sync_mutation',
              'domain': 'pos',
            },
        'created_at': now,
        'updated_at': now,
      });
    }

    await _client.from('sync_mutations').upsert(
          serverMutations,
          onConflict: 'business_id,idempotency_key',
        );

    final processResult = await _client.rpc(
      'process_sync_batch',
      params: {
        'p_sync_batch_id': serverBatchId,
        'p_mode': 'apply_pos',
      },
    );

    // POS inventory is applied by the backend trigger when the POS sync batch
    // transitions to completed. Flutter must not call the inventory RPC here.
    // This keeps backend as the single source of truth for remote stock effects.

    return CatalogUploadBatchResult.fromProcessResult(
      localBatchId: localBatchId,
      serverBatchId: serverBatchId,
      fallbackMutationCount: localMutations.length,
      value: processResult,
    );
  }

  Future<bool> allPosMutationEntitiesAlreadyExist({
    required List<Map<String, dynamic>> localMutations,
  }) async {
    if (localMutations.isEmpty) {
      return false;
    }

    for (final mutation in localMutations) {
      final entityTable = _requiredString(mutation, 'entity_table');
      final entityId = _requiredString(mutation, 'entity_id');

      if (entityTable != 'sales' &&
          entityTable != 'sale_items' &&
          entityTable != 'sale_payments') {
        return false;
      }

      final exists = await _posEntityExists(
        table: entityTable,
        entityId: entityId,
      );

      if (!exists) {
        return false;
      }
    }

    return true;
  }

  Future<bool> _posEntityExists({
    required String table,
    required String entityId,
  }) async {
    final rows =
        await _client.from(table).select('id').eq('id', entityId).limit(1);

    return rows.isNotEmpty;
  }

  Future<String?> _findExistingServerMutationId({
    required String businessId,
    required String idempotencyKey,
  }) async {
    final rows = await _client
        .from('sync_mutations')
        .select('id')
        .eq('business_id', businessId)
        .eq('idempotency_key', idempotencyKey)
        .limit(1);

    if (rows.isEmpty) {
      return null;
    }

    final first = Map<String, dynamic>.from(rows.first as Map);

    return _string(first['id']);
  }

  Future<List<Map<String, dynamic>>> getServerBatchMutationStatuses({
    required String serverBatchId,
  }) async {
    final rows = await _client
        .from('sync_mutations')
        .select(
          'client_mutation_id, entity_table, entity_id, status, error_code, error_message',
        )
        .eq('sync_batch_id', serverBatchId)
        .order('client_sequence');

    return rows.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  Object _normalizedPosPayload(Map<String, dynamic> mutation) {
    final payload = _decodeRequiredJson(mutation['payload_json']);
    final entityTable = _string(mutation['entity_table']);

    if (payload is! Map) {
      return payload;
    }

    final normalized = Map<String, dynamic>.from(payload);

    if (entityTable == 'sale_payments' || entityTable == 'sales') {
      if (_string(normalized['payment_method']) == 'transfer') {
        normalized['payment_method'] = 'bank_transfer';
      }
    }

    return normalized;
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
}
