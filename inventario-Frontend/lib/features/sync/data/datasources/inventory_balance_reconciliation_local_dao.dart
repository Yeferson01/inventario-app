import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../models/inventory_movement_acknowledgement_models.dart';

class InventoryBalanceReconciliationLocalDao {
  InventoryBalanceReconciliationLocalDao(this._db);

  final AppDatabase _db;

  Future<List<LocalInventoryMovementForReconciliation>> getMovements({
    required String businessId,
    required String branchId,
  }) async {
    final movementRows = await _db.customSelect(
      '''
      select * from local_inventory_movements
      where business_id = ? and branch_id = ? and deleted_at is null
      order by occurred_at, id
      ''',
      variables: [Variable<String>(businessId), Variable<String>(branchId)],
      readsFrom: {_db.localInventoryMovements},
    ).get();
    final mutationRows = await _db.customSelect(
      '''
      select m.entity_table, m.entity_id, m.status as mutation_status,
             b.status as batch_status
      from local_sync_mutations m
      left join local_sync_batches b on b.id = m.local_sync_batch_id
      where m.business_id = ? and m.branch_id = ?
      order by m.client_sequence, m.id
      ''',
      variables: [Variable<String>(businessId), Variable<String>(branchId)],
      readsFrom: {_db.localSyncMutations, _db.localSyncBatches},
    ).get();

    final evidence = <String, List<_TransportEvidence>>{};
    for (final row in mutationRows) {
      final data = row.data;
      final key = '${data['entity_table']}:${data['entity_id']}';
      evidence.putIfAbsent(key, () => []).add(
            _TransportEvidence(
              mutationStatus: data['mutation_status'].toString(),
              batchStatus: data['batch_status']?.toString(),
            ),
          );
    }

    final movements = movementRows.map((row) {
      final data = row.data;
      final metadata = _metadata(data['metadata_json']);
      final sourceType = data['source_type']?.toString() ?? '';
      final sourceItemId = switch (sourceType) {
        'sale' => _nonEmpty(metadata['sale_item_id']),
        'purchase' => _nonEmpty(metadata['purchase_item_id']),
        _ => null,
      };
      final evidenceKey = switch (sourceType) {
        'sale' => sourceItemId == null ? null : 'sale_items:$sourceItemId',
        'purchase' =>
          sourceItemId == null ? null : 'purchase_items:$sourceItemId',
        'manual_adjustment' => 'inventory_movements:${data['id']}',
        _ => null,
      };
      final matches = evidenceKey == null
          ? const <_TransportEvidence>[]
          : evidence[evidenceKey] ?? const <_TransportEvidence>[];
      final transportState = _transportState(
        matches,
        localStatus: data['local_status']?.toString(),
      );
      return LocalInventoryMovementForReconciliation(
        id: data['id'].toString(),
        businessId: data['business_id'].toString(),
        branchId: data['branch_id'].toString(),
        productId: data['product_id'].toString(),
        sourceType: sourceType,
        sourceId: _nonEmpty(data['source_id']),
        sourceItemId: sourceItemId,
        idempotencyKey: data['idempotency_key'].toString(),
        quantityChange: (data['quantity_change'] as num).toInt(),
        unitCost: (data['unit_cost'] as num?)?.toDouble(),
        occurredAt: _date(data['occurred_at']),
        clientSequence: _int(metadata['client_sequence']),
        transportState: transportState,
        transportEvidence: matches
            .map((item) => '${item.mutationStatus}/${item.batchStatus ?? '-'}')
            .toList(growable: false),
      );
    }).toList();
    movements.sort((left, right) {
      final byTime = left.occurredAt.compareTo(right.occurredAt);
      if (byTime != 0) return byTime;
      final bySequence =
          (left.clientSequence ?? 0).compareTo(right.clientSequence ?? 0);
      return bySequence != 0 ? bySequence : left.id.compareTo(right.id);
    });
    return List.unmodifiable(movements);
  }

  InventoryMovementTransportState _transportState(
    List<_TransportEvidence> evidence, {
    required String? localStatus,
  }) {
    if (evidence.any(
      (item) => const {'conflict', 'skipped'}.contains(item.mutationStatus),
    )) {
      return InventoryMovementTransportState.terminalIncompatible;
    }
    if (evidence.any((item) => item.mutationStatus == 'applied')) {
      return InventoryMovementTransportState.terminalApplied;
    }
    if (evidence.isEmpty &&
        const {'synced', 'clean', 'completed'}.contains(localStatus)) {
      return InventoryMovementTransportState.terminalApplied;
    }
    return InventoryMovementTransportState.pending;
  }

  Map<String, dynamic> _metadata(Object? value) {
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.map((key, item) => MapEntry(key.toString(), item));
        }
      } on FormatException {
        return const {};
      }
    }
    return const {};
  }

  String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return value == null ? null : int.tryParse(value.toString());
  }

  DateTime _date(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is int) {
      final milliseconds = value.abs() < 100000000000 ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed.toUtc();
    }
    throw StateError('Invalid local inventory movement occurred_at.');
  }
}

class _TransportEvidence {
  const _TransportEvidence({
    required this.mutationStatus,
    required this.batchStatus,
  });

  final String mutationStatus;
  final String? batchStatus;
}
