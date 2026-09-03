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

  Future<UnmaterializedSaleRemoteEvidence> verifyUnmaterializedSale({
    required String businessId,
    required String branchId,
    required String saleId,
  }) async {
    final value = await _client.rpc(
      'verify_unmaterialized_sale_discard',
      params: {
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_sale_id': saleId,
      },
    );
    if (value is! Map) {
      throw const FormatException(
        'verify_unmaterialized_sale_discard returned an invalid payload.',
      );
    }
    final payload = Map<String, dynamic>.from(value);
    final returnedBusinessId = _requiredString(payload, 'business_id');
    final returnedBranchId = _requiredString(payload, 'branch_id');
    final returnedSaleId = _requiredString(payload, 'sale_id');
    final saleExists = _requiredBool(payload, 'sale_exists');
    final itemsExist = _requiredBool(payload, 'items_exist');
    final paymentsExist = _requiredBool(payload, 'payments_exist');
    final movementsExist = _requiredBool(payload, 'movements_exist');
    final expectedConflictExists =
        _requiredBool(payload, 'expected_conflict_exists');
    final safeToDiscard = _requiredBool(payload, 'safe_to_discard');
    final expectedSafeToDiscard = !saleExists &&
        !itemsExist &&
        !paymentsExist &&
        !movementsExist &&
        expectedConflictExists;
    if (safeToDiscard != expectedSafeToDiscard) {
      throw const FormatException(
        'verify_unmaterialized_sale_discard returned inconsistent evidence.',
      );
    }
    final conflictReasons = switch (payload['conflict_reasons']) {
      final List reasons => reasons.map(_string).whereType<String>().toSet(),
      null => const <String>{},
      _ => throw const FormatException(
          'verify_unmaterialized_sale_discard returned invalid reasons.',
        ),
    };

    return UnmaterializedSaleRemoteEvidence(
      businessId: returnedBusinessId,
      branchId: returnedBranchId,
      saleId: returnedSaleId,
      saleRows: saleExists ? 1 : 0,
      saleItemRows: itemsExist ? 1 : 0,
      salePaymentRows: paymentsExist ? 1 : 0,
      inventoryMovementRows: movementsExist ? 1 : 0,
      expectedConflictFound: expectedConflictExists,
      conflictReasons: conflictReasons,
    );
  }

  Future<SaleDidNotOccurRemoteResult> resolveUnmaterializedSaleDidNotOccur({
    required String businessId,
    required String branchId,
    required String appDeviceId,
    required String saleId,
    required String syncConflictId,
    required String idempotencyKey,
    required String reason,
  }) async {
    final value = await _client.rpc(
      'resolve_unmaterialized_sale_did_not_occur',
      params: {
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_app_device_id': appDeviceId,
        'p_sale_id': saleId,
        'p_sync_conflict_id': syncConflictId,
        'p_idempotency_key': idempotencyKey,
        'p_reason': reason,
      },
    );
    if (value is! Map) {
      throw const FormatException(
        'resolve_unmaterialized_sale_did_not_occur returned an invalid payload.',
      );
    }
    final result = SaleDidNotOccurRemoteResult.fromJson(
      Map<String, dynamic>.from(value),
    );
    if (result.businessId != businessId ||
        result.branchId != branchId ||
        result.saleId != saleId ||
        result.syncConflictId != syncConflictId ||
        result.idempotencyKey != idempotencyKey ||
        result.status != 'resolved' ||
        result.resolutionStrategy != 'sale_did_not_occur') {
      throw const FormatException(
        'Sale did-not-occur response does not match the request.',
      );
    }
    return result;
  }

  Future<IntentionalStaleSaleRemoteResult>
      reconcileRejectedSaleToOpenCashSession({
    required String businessId,
    required String branchId,
    required String appDeviceId,
    required String saleId,
    required String syncConflictId,
    required String destinationCashSessionId,
    required String reconciliationId,
    required String idempotencyKey,
    required String reason,
    required String cashTreatment,
  }) async {
    final value = await _client.rpc(
      'reconcile_rejected_sale_to_open_cash_session',
      params: {
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_app_device_id': appDeviceId,
        'p_sale_id': saleId,
        'p_sync_conflict_id': syncConflictId,
        'p_destination_cash_session_id': destinationCashSessionId,
        'p_reconciliation_id': reconciliationId,
        'p_idempotency_key': idempotencyKey,
        'p_reason': reason,
        'p_cash_treatment': cashTreatment,
      },
    );
    if (value is! Map) {
      throw const FormatException(
        'reconcile_rejected_sale_to_open_cash_session returned an invalid payload.',
      );
    }
    final payload = Map<String, dynamic>.from(value);
    final result = IntentionalStaleSaleRemoteResult.fromJson(payload);
    if (result.businessId != businessId ||
        result.branchId != branchId ||
        result.saleId != saleId ||
        result.reconciliationId != reconciliationId ||
        result.syncConflictId != syncConflictId ||
        result.destinationCashSessionId != destinationCashSessionId ||
        result.cashTreatment != cashTreatment ||
        result.status != 'completed') {
      throw const FormatException(
        'Stale Sale reconciliation response does not match the request.',
      );
    }
    return result;
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

  Future<List<PosInventoryApplyFailure>> getInventoryApplyFailures({
    required String serverBatchId,
  }) async {
    final rows = await _client
        .from('sync_batches')
        .select('metadata')
        .eq('id', serverBatchId)
        .limit(1);
    if (rows.isEmpty) return const [];

    final row = Map<String, dynamic>.from(rows.first as Map);
    final metadata = row['metadata'];
    if (metadata is! Map) return const [];
    final autoApply = metadata['pos_inventory_auto_apply'];
    if (autoApply is! Map) return const [];
    final result = autoApply['result'];
    if (result is! Map) return const [];
    final errors = result['errors'];
    if (errors is! List) return const [];

    return errors.whereType<Map>().map((error) {
      return PosInventoryApplyFailure(
        serverBatchId: serverBatchId,
        saleId: _requiredString(
          error.map((key, value) => MapEntry(key.toString(), value)),
          'sale_id',
        ),
        message: _string(error['error_message']) ??
            'Remote inventory application failed.',
      );
    }).toList(growable: false);
  }

  Future<List<PosCashSessionApplyFailure>> getCashSessionApplyFailures({
    required String serverBatchId,
  }) async {
    final mutationRows = await _client
        .from('sync_mutations')
        .select('id')
        .eq('sync_batch_id', serverBatchId)
        .eq('entity_table', 'sales');
    final mutationIds = mutationRows
        .map((row) => _string((row as Map)['id']))
        .whereType<String>()
        .toList(growable: false);
    if (mutationIds.isEmpty) return const [];

    final conflictRows = await _client
        .from('sync_conflicts')
        .select(
          'id, sync_batch_id, sync_mutation_id, entity_id, error_message, metadata',
        )
        .inFilter('sync_mutation_id', mutationIds);

    return conflictRows.whereType<Map>().where((row) {
      final metadata = row['metadata'];
      return metadata is Map &&
          _string(metadata['rule']) == 'sale_cash_session_invalid';
    }).map((row) {
      final metadata = Map<String, dynamic>.from(row['metadata'] as Map);
      return PosCashSessionApplyFailure(
        syncConflictId: _requiredString(
          row.map((key, value) => MapEntry(key.toString(), value)),
          'id',
        ),
        serverBatchId: _string(row['sync_batch_id']) ?? serverBatchId,
        serverMutationId: _requiredString(
          row.map((key, value) => MapEntry(key.toString(), value)),
          'sync_mutation_id',
        ),
        saleId: _requiredString(
          row.map((key, value) => MapEntry(key.toString(), value)),
          'entity_id',
        ),
        cashSessionId: _string(metadata['cash_session_id']),
        cashRegisterId: _string(metadata['cash_register_id']),
        branchId: _string(metadata['branch_id']),
        reason: _string(metadata['reason']) ?? 'missing',
        message: _string(row['error_message']) ??
            'Remote sale cash session validation failed.',
      );
    }).toList(growable: false);
  }

  Future<String?> findOpenClosedCashSessionSaleConflictId({
    required String businessId,
    required String branchId,
    required String appDeviceId,
    required String saleId,
  }) async {
    final value = await _client.rpc(
      'lookup_open_closed_cash_session_sale_conflict',
      params: {
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_app_device_id': appDeviceId,
        'p_sale_id': saleId,
      },
    );
    if (value is! Map) {
      throw const FormatException(
        'Conflict lookup returned an invalid payload.',
      );
    }
    final result = OpenClosedCashSessionSaleConflictLookup.fromJson(
      Map<String, dynamic>.from(value),
    );
    if (result.businessId != businessId ||
        result.branchId != branchId ||
        result.saleId != saleId) {
      throw const FormatException(
        'Conflict lookup returned a mismatched scope.',
      );
    }
    return switch (result.status) {
      OpenClosedCashSessionSaleConflictLookupStatus.found => result.conflictId,
      OpenClosedCashSessionSaleConflictLookupStatus.notFound => null,
      OpenClosedCashSessionSaleConflictLookupStatus.ambiguous =>
        throw StateError(
          'Multiple open closed-session conflicts exist for the Sale.',
        ),
    };
  }

  Future<List<PosInventoryApplyFailure>> getInventoryApplyFailuresForMutations({
    required List<Map<String, dynamic>> localMutations,
  }) async {
    final serverBatchIds = <String>{};
    for (final mutation in localMutations) {
      if (_string(mutation['entity_table']) != 'sales') continue;
      final rows = await _client
          .from('sync_mutations')
          .select('sync_batch_id')
          .eq('business_id', _requiredString(mutation, 'business_id'))
          .eq('idempotency_key', _requiredString(mutation, 'idempotency_key'))
          .limit(1);
      if (rows.isEmpty) continue;
      final batchId = _string((rows.first as Map)['sync_batch_id']);
      if (batchId != null) serverBatchIds.add(batchId);
    }

    final failures = <PosInventoryApplyFailure>[];
    for (final batchId in serverBatchIds) {
      failures.addAll(
        await getInventoryApplyFailures(serverBatchId: batchId),
      );
    }
    return List.unmodifiable(failures);
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

  bool _requiredBool(Map<String, dynamic> source, String key) {
    final value = source[key];
    if (value is bool) {
      return value;
    }
    throw FormatException('Boolean field required: $key');
  }
}

enum OpenClosedCashSessionSaleConflictLookupStatus {
  found,
  notFound,
  ambiguous,
}

class OpenClosedCashSessionSaleConflictLookup {
  const OpenClosedCashSessionSaleConflictLookup({
    required this.businessId,
    required this.branchId,
    required this.saleId,
    required this.status,
    required this.conflictCount,
    required this.conflictId,
  });

  factory OpenClosedCashSessionSaleConflictLookup.fromJson(
    Map<String, dynamic> json,
  ) {
    String requiredString(String key) {
      final value = json[key]?.toString().trim();
      if (value == null || value.isEmpty) {
        throw FormatException('Conflict lookup is missing $key.');
      }
      return value;
    }

    final status = switch (requiredString('status')) {
      'found' => OpenClosedCashSessionSaleConflictLookupStatus.found,
      'not_found' => OpenClosedCashSessionSaleConflictLookupStatus.notFound,
      'ambiguous' => OpenClosedCashSessionSaleConflictLookupStatus.ambiguous,
      _ => throw const FormatException(
          'Conflict lookup returned an invalid status.',
        ),
    };
    final count = json['conflict_count'];
    if (count is! num || count.toInt() < 0) {
      throw const FormatException(
        'Conflict lookup returned an invalid conflict_count.',
      );
    }
    final conflictId = _nullableString(json['conflict_id']);
    if ((status == OpenClosedCashSessionSaleConflictLookupStatus.found &&
            (count.toInt() != 1 || conflictId == null)) ||
        (status == OpenClosedCashSessionSaleConflictLookupStatus.notFound &&
            (count.toInt() != 0 || conflictId != null)) ||
        (status == OpenClosedCashSessionSaleConflictLookupStatus.ambiguous &&
            (count.toInt() < 2 || conflictId != null))) {
      throw const FormatException(
        'Conflict lookup returned inconsistent evidence.',
      );
    }
    return OpenClosedCashSessionSaleConflictLookup(
      businessId: requiredString('business_id'),
      branchId: requiredString('branch_id'),
      saleId: requiredString('sale_id'),
      status: status,
      conflictCount: count.toInt(),
      conflictId: conflictId,
    );
  }

  final String businessId;
  final String branchId;
  final String saleId;
  final OpenClosedCashSessionSaleConflictLookupStatus status;
  final int conflictCount;
  final String? conflictId;

  static String? _nullableString(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}

class PosInventoryApplyFailure {
  const PosInventoryApplyFailure({
    required this.serverBatchId,
    required this.saleId,
    required this.message,
  });

  final String serverBatchId;
  final String saleId;
  final String message;
}

class PosCashSessionApplyFailure {
  const PosCashSessionApplyFailure({
    required this.syncConflictId,
    required this.serverBatchId,
    required this.serverMutationId,
    required this.saleId,
    required this.cashSessionId,
    required this.cashRegisterId,
    required this.branchId,
    required this.reason,
    required this.message,
  });

  final String syncConflictId;
  final String serverBatchId;
  final String serverMutationId;
  final String saleId;
  final String? cashSessionId;
  final String? cashRegisterId;
  final String? branchId;
  final String reason;
  final String message;
}

class UnmaterializedSaleRemoteEvidence {
  const UnmaterializedSaleRemoteEvidence({
    required this.businessId,
    required this.branchId,
    required this.saleId,
    required this.saleRows,
    required this.saleItemRows,
    required this.salePaymentRows,
    required this.inventoryMovementRows,
    required this.expectedConflictFound,
    this.conflictReasons = const {},
  });

  final String businessId;
  final String branchId;
  final String saleId;
  final int saleRows;
  final int saleItemRows;
  final int salePaymentRows;
  final int inventoryMovementRows;
  final bool expectedConflictFound;
  final Set<String> conflictReasons;

  bool get hasRemoteMaterialization =>
      saleRows > 0 ||
      saleItemRows > 0 ||
      salePaymentRows > 0 ||
      inventoryMovementRows > 0;

  Map<String, dynamic> toJson() => {
        'business_id': businessId,
        'branch_id': branchId,
        'sale_id': saleId,
        'sale_rows': saleRows,
        'sale_item_rows': saleItemRows,
        'sale_payment_rows': salePaymentRows,
        'inventory_movement_rows': inventoryMovementRows,
        'expected_conflict_found': expectedConflictFound,
        'conflict_reasons': conflictReasons.toList(growable: false),
      };
}

class SaleDidNotOccurRemoteResult {
  const SaleDidNotOccurRemoteResult({
    required this.businessId,
    required this.branchId,
    required this.saleId,
    required this.syncConflictId,
    required this.status,
    required this.resolutionStrategy,
    required this.idempotencyKey,
    required this.mutationsTerminalized,
    required this.idempotent,
  });

  factory SaleDidNotOccurRemoteResult.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key]?.toString().trim();
      if (value == null || value.isEmpty) {
        throw FormatException('Sale did-not-occur response is missing $key.');
      }
      return value;
    }

    int requiredInt(String key) {
      final value = json[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed == null) {
        throw FormatException('Sale did-not-occur response has invalid $key.');
      }
      return parsed;
    }

    final idempotent = json['idempotent'];
    if (idempotent is! bool) {
      throw const FormatException(
        'Sale did-not-occur response has invalid idempotent.',
      );
    }
    return SaleDidNotOccurRemoteResult(
      businessId: requiredString('business_id'),
      branchId: requiredString('branch_id'),
      saleId: requiredString('sale_id'),
      syncConflictId: requiredString('sync_conflict_id'),
      status: requiredString('status'),
      resolutionStrategy: requiredString('resolution_strategy'),
      idempotencyKey: requiredString('idempotency_key'),
      mutationsTerminalized: requiredInt('mutations_terminalized'),
      idempotent: idempotent,
    );
  }

  final String businessId;
  final String branchId;
  final String saleId;
  final String syncConflictId;
  final String status;
  final String resolutionStrategy;
  final String idempotencyKey;
  final int mutationsTerminalized;
  final bool idempotent;

  Map<String, dynamic> toJson() => {
        'business_id': businessId,
        'branch_id': branchId,
        'sale_id': saleId,
        'sync_conflict_id': syncConflictId,
        'status': status,
        'resolution_strategy': resolutionStrategy,
        'idempotency_key': idempotencyKey,
        'mutations_terminalized': mutationsTerminalized,
        'idempotent': idempotent,
      };
}

class IntentionalStaleSaleRemoteResult {
  const IntentionalStaleSaleRemoteResult({
    required this.reconciliationId,
    required this.businessId,
    required this.branchId,
    required this.saleId,
    required this.cashRegisterId,
    required this.originalCashSessionId,
    required this.destinationCashSessionId,
    required this.syncConflictId,
    required this.cashTreatment,
    required this.cashReconciledTotal,
    required this.cashAdjustmentTotal,
    required this.cashAdjustmentAmount,
    required this.projectedExpectedCash,
    required this.status,
    required this.idempotent,
  });

  factory IntentionalStaleSaleRemoteResult.fromJson(
    Map<String, dynamic> json,
  ) {
    String requiredString(String key) {
      final value = json[key]?.toString().trim();
      if (value == null || value.isEmpty) {
        throw FormatException('Stale Sale response is missing $key.');
      }
      return value;
    }

    double requiredDouble(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed == null) {
        throw FormatException('Stale Sale response has invalid $key.');
      }
      return parsed;
    }

    final idempotent = json['idempotent'];
    if (idempotent is! bool) {
      throw const FormatException(
        'Stale Sale response has invalid idempotent.',
      );
    }
    return IntentionalStaleSaleRemoteResult(
      reconciliationId: requiredString('reconciliation_id'),
      businessId: requiredString('business_id'),
      branchId: requiredString('branch_id'),
      saleId: requiredString('sale_id'),
      cashRegisterId: requiredString('cash_register_id'),
      originalCashSessionId: requiredString('original_cash_session_id'),
      destinationCashSessionId: requiredString('destination_cash_session_id'),
      syncConflictId: requiredString('sync_conflict_id'),
      cashTreatment: requiredString('cash_treatment'),
      cashReconciledTotal: requiredDouble('cash_reconciled_total'),
      cashAdjustmentTotal: requiredDouble('cash_adjustment_total'),
      cashAdjustmentAmount: requiredDouble('cash_adjustment_amount'),
      projectedExpectedCash: requiredDouble('projected_expected_cash'),
      status: requiredString('status'),
      idempotent: idempotent,
    );
  }

  final String reconciliationId;
  final String businessId;
  final String branchId;
  final String saleId;
  final String cashRegisterId;
  final String originalCashSessionId;
  final String destinationCashSessionId;
  final String syncConflictId;
  final String cashTreatment;
  final double cashReconciledTotal;
  final double cashAdjustmentTotal;
  final double cashAdjustmentAmount;
  final double projectedExpectedCash;
  final String status;
  final bool idempotent;

  Map<String, dynamic> toJson() => {
        'reconciliation_id': reconciliationId,
        'business_id': businessId,
        'branch_id': branchId,
        'sale_id': saleId,
        'cash_register_id': cashRegisterId,
        'original_cash_session_id': originalCashSessionId,
        'destination_cash_session_id': destinationCashSessionId,
        'sync_conflict_id': syncConflictId,
        'cash_treatment': cashTreatment,
        'cash_reconciled_total': cashReconciledTotal,
        'cash_adjustment_total': cashAdjustmentTotal,
        'cash_adjustment_amount': cashAdjustmentAmount,
        'projected_expected_cash': projectedExpectedCash,
        'status': status,
        'idempotent': idempotent,
      };
}
