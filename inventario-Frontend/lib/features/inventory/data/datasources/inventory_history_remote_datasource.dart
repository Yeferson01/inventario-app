import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/inventory_history_models.dart';

typedef InventoryHistoryRpcInvoker = Future<Object?> Function(
  Map<String, Object?> parameters,
);

class InventoryHistoryRemoteDatasource {
  InventoryHistoryRemoteDatasource(SupabaseClient client)
      : this.withInvoker(
          (parameters) => client.rpc(
            'list_inventory_movement_history',
            params: parameters,
          ),
        );

  InventoryHistoryRemoteDatasource.withInvoker(this._invoke);

  final InventoryHistoryRpcInvoker _invoke;

  Future<InventoryHistoryRemotePage> loadBranchPage({
    required String businessId,
    required String branchId,
    InventoryHistoryCursor? cursor,
    int limit = 50,
  }) async {
    final normalizedLimit = limit.clamp(1, 200);
    final response = await _invoke({
      'p_business_id': businessId,
      'p_branch_id': branchId,
      'p_product_id': null,
      'p_source_type': null,
      'p_from': null,
      'p_to': null,
      'p_cursor_occurred_at': cursor?.occurredAt.toIso8601String(),
      'p_cursor_id': cursor?.id,
      'p_limit': normalizedLimit,
    });

    if (response is! List) {
      throw const FormatException(
        'Inventory history RPC response must be a row list.',
      );
    }

    final rows = <InventoryHistoryRemoteRow>[];
    for (final value in response) {
      if (value is! Map) {
        throw const FormatException('Inventory history row is malformed.');
      }
      final row = InventoryHistoryRemoteRow.fromJson(
        value.map((key, item) => MapEntry(key.toString(), item)),
      );
      if (row.businessId != businessId || row.branchId != branchId) {
        throw const FormatException(
          'Inventory history row is outside the requested scope.',
        );
      }
      rows.add(row);
    }

    for (var index = 1; index < rows.length; index += 1) {
      final previous = rows[index - 1];
      final current = rows[index];
      final timeOrder = previous.occurredAt.compareTo(current.occurredAt);
      if (timeOrder < 0 ||
          (timeOrder == 0 && previous.id.compareTo(current.id) <= 0)) {
        throw const FormatException(
          'Inventory history rows are not in descending keyset order.',
        );
      }
    }

    return InventoryHistoryRemotePage.fromRows(
      rows,
      requestedLimit: normalizedLimit,
    );
  }
}
