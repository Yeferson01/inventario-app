import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/runtime_setup_models.dart';

class RuntimeSetupRemoteDataSource {
  RuntimeSetupRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<RegisteredAppDeviceResult> registerOrUpdateAppDevice(
    RegisterAppDeviceInput input,
  ) async {
    final result = await _rpcWithFallbacks(
      functionName: 'register_or_update_app_device',
      paramSets: [
        input.toRpcParamsWithPrefix(includeProfileId: true),
        input.toRpcParamsWithPrefix(includeProfileId: false),
        input.toRpcParamsWithoutPrefix(includeProfileId: true),
        input.toRpcParamsWithoutPrefix(includeProfileId: false),
      ],
    );

    return RegisteredAppDeviceResult.fromRpc(
      result,
      fallbackBusinessId: input.businessId,
      fallbackInstallationId: input.installationId,
    );
  }

  Future<BusinessRuntimeSetupResult> ensureBusinessRuntimeSetup(
    EnsureBusinessRuntimeSetupInput input,
  ) async {
    final result = await _rpcWithFallbacks(
      functionName: 'ensure_business_runtime_setup',
      paramSets: [
        input.toRpcParamsWithPrefix(includeProfileId: true),
        input.toRpcParamsWithPrefix(includeProfileId: false),
        input.toRpcParamsWithoutPrefix(includeProfileId: true),
        input.toRpcParamsWithoutPrefix(includeProfileId: false),
        {
          'p_business_id': input.businessId,
        },
        {
          'business_id': input.businessId,
        },
      ],
    );

    return BusinessRuntimeSetupResult.fromRpc(
      result,
      fallbackBusinessId: input.businessId,
      fallbackBranchId: input.branchId,
    );
  }

  Future<dynamic> _rpcWithFallbacks({
    required String functionName,
    required List<Map<String, dynamic>> paramSets,
  }) async {
    Object? lastError;

    for (final params in paramSets) {
      try {
        final cleaned = _withoutNulls(params);

        return await _client.rpc(
          functionName,
          params: cleaned,
        );
      } catch (error) {
        lastError = error;

        if (!_looksLikeParameterMismatch(error)) {
          rethrow;
        }
      }
    }

    throw StateError(
      'No se pudo ejecutar $functionName con las firmas conocidas. '
      'Último error: $lastError',
    );
  }

  Map<String, dynamic> _withoutNulls(Map<String, dynamic> params) {
    final result = <String, dynamic>{};

    for (final entry in params.entries) {
      if (entry.value != null) {
        result[entry.key] = entry.value;
      }
    }

    return result;
  }

  bool _looksLikeParameterMismatch(Object error) {
    final text = error.toString().toLowerCase();

    return text.contains('could not find the function') ||
        text.contains('schema cache') ||
        text.contains('parameter') ||
        text.contains('argument') ||
        text.contains('pgrst202') ||
        text.contains('42883');
  }
}
