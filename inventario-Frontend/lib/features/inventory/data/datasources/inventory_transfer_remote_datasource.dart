import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryTransferRemoteDataSource {
  InventoryTransferRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<Object?> createAndComplete(
    Map<String, Object?> params,
  ) async {
    return _client.rpc(
      'create_and_complete_inventory_transfer',
      params: params,
    );
  }
}
