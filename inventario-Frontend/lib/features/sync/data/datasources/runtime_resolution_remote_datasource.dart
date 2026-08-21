import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/operational_integration_failure.dart';
import '../models/runtime_resolution_models.dart';

typedef RuntimeResolutionRpcInvoker = Future<Object?> Function(
  Map<String, Object?> parameters,
);

class RuntimeResolutionRemoteDataSource {
  RuntimeResolutionRemoteDataSource(SupabaseClient client)
      : this.withInvoker(
          (parameters) => client.rpc(
            'resolve_business_runtime',
            params: parameters,
          ),
        );

  RuntimeResolutionRemoteDataSource.withInvoker(this._invoke);

  final RuntimeResolutionRpcInvoker _invoke;

  Future<ResolvedBusinessRuntime> resolve({
    required String businessId,
    required String branchId,
  }) async {
    if (businessId.trim().isEmpty || branchId.trim().isEmpty) {
      throw const OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.malformedResponse,
        message: 'Runtime resolution requires business and explicit branch.',
      );
    }
    try {
      final runtime = ResolvedBusinessRuntime.fromRpc(
        await _invoke({
          'p_business_id': businessId,
          'p_branch_id': branchId,
        }),
      );
      if (runtime.businessId != businessId || runtime.branchId != branchId) {
        throw const OperationalIntegrationException(
          kind: OperationalIntegrationFailureKind.scopeMismatch,
          message: 'Resolved runtime does not match the requested scope.',
        );
      }
      return runtime;
    } on OperationalIntegrationException {
      rethrow;
    } on TimeoutException catch (error) {
      throw OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.networkTransient,
        message: 'Runtime resolution timed out.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.networkTransient,
        message: 'Runtime resolution is unavailable.',
        cause: error,
      );
    } on PostgrestException catch (error) {
      final diagnostic =
          '${error.message} ${error.details} ${error.hint}'.toLowerCase();
      final unauthorized = error.code == 'PGRST301' ||
          diagnostic.contains('authentication required') ||
          diagnostic.contains('jwt');
      final forbidden = error.code == '42501' ||
          diagnostic.contains('membership') ||
          diagnostic.contains('access') ||
          diagnostic.contains('branch') ||
          diagnostic.contains('business');
      throw OperationalIntegrationException(
        kind: unauthorized
            ? OperationalIntegrationFailureKind.unauthorized
            : forbidden
                ? OperationalIntegrationFailureKind.forbidden
                : OperationalIntegrationFailureKind.remoteFailure,
        message: unauthorized || forbidden
            ? 'Runtime resolution is not authorized.'
            : 'Runtime resolution returned an error.',
        cause: error,
      );
    } catch (error) {
      throw OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.remoteFailure,
        message: 'Runtime resolution failed.',
        cause: error,
      );
    }
  }
}
