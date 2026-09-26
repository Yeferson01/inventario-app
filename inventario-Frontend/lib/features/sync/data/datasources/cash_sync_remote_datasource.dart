import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/app_uuid.dart';
import '../models/catalog_upload_models.dart';
import '../models/cash_movement_ack_models.dart';
import 'sync_registration_remote_datasource.dart';

class CashSyncRemoteDataSource {
  CashSyncRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<Map<String, CashMovementAck>> lookupMovementAcknowledgements({
    required String businessId,
    required String branchId,
    required String appDeviceId,
    required List<Map<String, dynamic>> mutations,
  }) async {
    if (mutations.isEmpty ||
        mutations.length > 100 ||
        mutations.any((m) => m['entity_table'] != 'cash_movements')) {
      throw ArgumentError('Invalid cash movement ACK batch.');
    }
    final candidates = mutations.map((mutation) {
      final payload = _decodeRequiredJson(mutation['payload_json']);
      if (payload is! Map) {
        throw const FormatException('Cash movement payload must be an object.');
      }
      return <String, Object?>{
        'id': mutation['entity_id'],
        'idempotency_key': mutation['idempotency_key'],
        'cash_register_id': payload['cash_register_id'],
        'cash_session_id': payload['cash_session_id'],
        'direction': payload['direction'],
        'category': payload['category'],
        'currency': payload['currency'],
        'amount': payload['amount'],
      };
    }).toList(growable: false);
    final raw = await _client.rpc(
      'lookup_cash_movement_acknowledgements',
      params: <String, Object?>{
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_app_device_id': appDeviceId,
        'p_candidates': candidates,
      },
    );
    if (raw is! List || raw.length != mutations.length) {
      throw const FormatException('Incomplete cash movement ACK response.');
    }
    final result = <String, CashMovementAck>{};
    for (final item in raw) {
      if (item is! Map) {
        throw const FormatException('Malformed cash movement ACK response.');
      }
      final ack = CashMovementAck.fromJson(Map<String, dynamic>.from(item));
      if (result.containsKey(ack.id) ||
          !mutations.any((m) => m['entity_id'] == ack.id)) {
        throw const FormatException('Cash movement ACK scope mismatch.');
      }
      result[ack.id] = ack;
    }
    return result;
  }

  Future<CatalogUploadBatchResult> uploadAndProcessCashBatch({
    required Map<String, dynamic> localBatch,
    required List<Map<String, dynamic>> localMutations,
  }) async {
    if (localMutations.isEmpty) {
      throw ArgumentError('No se puede subir un batch de cash sin mutaciones.');
    }

    var serverBatchId =
        _string(localBatch['server_sync_batch_id']) ?? AppUuid.v7();
    final localBatchId = _requiredString(localBatch, 'id');
    final businessId = _requiredString(localBatch, 'business_id');
    final clientBatchId = _requiredString(localBatch, 'client_batch_id');
    final now = DateTime.now().toUtc().toIso8601String();

    serverBatchId =
        await SyncRegistrationRemoteDataSource(_client).registerBatch(
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

    await SyncRegistrationRemoteDataSource(_client).registerMutations(
      serverMutations,
      expectedBatchId: serverBatchId,
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
