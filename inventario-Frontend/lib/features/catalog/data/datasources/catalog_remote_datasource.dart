import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/catalog_remote_models.dart';

class CatalogRemoteDataSource {
  CatalogRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<CatalogPullResponse> pullProductCatalogDelta(
    CatalogPullRequest request,
  ) async {
    try {
      final response = await _client.rpc(
        'pull_product_catalog_delta',
        params: request.toRpcParams(),
      );

      return CatalogPullResponse.fromRpc(response);
    } on PostgrestException catch (error) {
      if (error.code == '22023' &&
          error.message.toLowerCase().contains('catalog page token')) {
        throw CatalogPageTokenRejectedException(error.message);
      }

      rethrow;
    }
  }
}

class CatalogPageTokenRejectedException implements Exception {
  const CatalogPageTokenRejectedException(this.message);

  final String message;

  @override
  String toString() => 'CatalogPageTokenRejectedException: $message';
}
