import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/app_uuid.dart';
import '../models/catalog_upload_models.dart';

class CashSyncRemoteDataSource {
  CashSyncRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<CatalogUploadBatchResult> uploadAndProcessCashBatch({
    required Map<String, dynamic> localBatch,
    required List<Map<String, dynamic>> localMutations,
  }) async {
    if (localMutations.isEmpty) {
      throw ArgumentError('No se puede subir un batch de cash sin mutaciones.');
    }

    final serverBatchId =
        _string(localBatch['server_sync_batch_id']) ?? AppUuid.v7();
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
              'source': 'flutter_cash_upload',
              'domain': 'cash',
            },
        'created_at': now,
        'updated_at': now,
      },
      onConflict: 'business_id,app_device_id,client_batch_id',
    );

    final serverMutations = localMutations.map((mutation) {
      return {
        'id': AppUuid.v7(),
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
              'source': 'flutter_cash_sync_mutation',
              'domain': 'cash',
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
        'p_mode': 'apply_cash',
      },
    );

    return CatalogUploadBatchResult.fromProcessResult(
      localBatchId: localBatchId,
      serverBatchId: serverBatchId,
      fallbackMutationCount: localMutations.length,
      value: processResult,
    );
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
