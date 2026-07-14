import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/product_stock_balance_models.dart';

class ProductStockBalanceRemoteDataSource {
  ProductStockBalanceRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<List<RemoteProductStockBalance>> pullBranchBalances({
    required String businessId,
    required String branchId,
    int limit = 1000,
  }) async {
    final rows = await _client
        .from('product_stock_balances')
        .select(
          '''
          business_id,
          branch_id,
          product_id,
          quantity_on_hand,
          quantity_reserved,
          quantity_available,
          average_cost,
          last_movement_at,
          updated_at
          ''',
        )
        .eq('business_id', businessId)
        .eq('branch_id', branchId)
        .order('updated_at', ascending: false)
        .limit(limit);

    return rows
        .map(
          (row) => RemoteProductStockBalance.fromJson(
            Map<String, dynamic>.from(row),
          ),
        )
        .toList();
  }
}
