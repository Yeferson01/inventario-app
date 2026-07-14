import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catalog_remote_models.dart';

class CatalogRemoteDataSource {
  CatalogRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<CatalogPullResponse> pullProductCatalogDelta(
    CatalogPullRequest request,
  ) async {
    final response = await _client.rpc(
      'pull_product_catalog_delta',
      params: request.toRpcParams(),
    );

    return CatalogPullResponse.fromRpc(response);
  }
}
