import 'package:supabase_flutter/supabase_flutter.dart';

/// Registers upload intent without assigning authoritative processing results.
class SyncRegistrationRemoteDataSource {
  const SyncRegistrationRemoteDataSource(this._client) : _invoker = null;

  const SyncRegistrationRemoteDataSource.withInvoker(this._invoker)
      : _client = null;

  final SupabaseClient? _client;
  final Future<dynamic> Function(String, Map<String, dynamic>)? _invoker;

  Future<dynamic> _rpc(String name, Map<String, dynamic> params) =>
      _invoker?.call(name, params) ?? _client!.rpc(name, params: params);

  Future<String> registerBatch(Map<String, dynamic> batch) async {
    final response = await _rpc(
      'register_pending_sync_batch',
      {'p_batch': batch},
    );
    if (response is! Map || response['id'] is! String) {
      throw const FormatException('Invalid sync batch registration response');
    }
    return response['id'] as String;
  }

  Future<void> registerMutations(
    List<Map<String, dynamic>> mutations, {
    required String expectedBatchId,
  }) async {
    if (mutations.isEmpty) {
      throw ArgumentError.value(mutations, 'mutations', 'Must not be empty');
    }
    final response = await _rpc(
      'register_pending_sync_mutations',
      {'p_mutations': mutations},
    );
    if (response is! List || response.length != mutations.length) {
      throw const FormatException(
          'Invalid sync mutation registration response');
    }
    for (final entry in response) {
      if (entry is! Map ||
          entry['id'] is! String ||
          entry['sync_batch_id'] != expectedBatchId) {
        throw const FormatException('Invalid sync mutation registration scope');
      }
    }
  }
}
