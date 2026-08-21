import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/operational_integration_failure.dart';
import '../models/runtime_setup_models.dart';

typedef RuntimeSetupRpcInvoker = Future<Object?> Function(
  String functionName,
  Map<String, Object?> parameters,
);

class RuntimeSetupRemoteDataSource {
  RuntimeSetupRemoteDataSource(SupabaseClient client)
      : this.withInvoker(
          (functionName, parameters) => client.rpc(
            functionName,
            params: parameters,
          ),
        );

  RuntimeSetupRemoteDataSource.withInvoker(this._invoke);

  final RuntimeSetupRpcInvoker _invoke;

  Future<RegisteredAppDeviceResult> registerOrUpdateAppDevice(
    RegisterAppDeviceInput input,
  ) async {
    try {
      final result = RegisteredAppDeviceResult.fromRpc(
        await _invoke('register_or_update_app_device', input.toRpcParams()),
        fallbackBusinessId: input.businessId,
        fallbackInstallationId: input.installationId,
      );
      if (result.businessId != input.businessId ||
          result.branchId != input.branchId ||
          result.installationId != input.installationId) {
        throw const OperationalIntegrationException(
          kind: OperationalIntegrationFailureKind.scopeMismatch,
          message: 'Registered device does not match the requested scope.',
        );
      }
      if (result.status == 'blocked') {
        throw const OperationalIntegrationException(
          kind: OperationalIntegrationFailureKind.deviceBlocked,
          message: 'The app device is blocked.',
        );
      }
      if (result.status != 'active') {
        throw const OperationalIntegrationException(
          kind: OperationalIntegrationFailureKind.forbidden,
          message: 'The app device is not active.',
        );
      }
      return result;
    } catch (error) {
      throw _classify(error, operation: 'Device registration');
    }
  }

  Future<BusinessRuntimeSetupResult> ensureBusinessRuntimeSetup(
    EnsureBusinessRuntimeSetupInput input,
  ) async {
    try {
      final result = BusinessRuntimeSetupResult.fromRpc(
        await _invoke('ensure_business_runtime_setup', input.toRpcParams()),
        fallbackBusinessId: input.businessId,
      );
      if (result.businessId != input.businessId ||
          result.branchId != input.branchId) {
        throw const OperationalIntegrationException(
          kind: OperationalIntegrationFailureKind.scopeMismatch,
          message: 'Runtime setup response does not match the requested scope.',
        );
      }
      return result;
    } catch (error) {
      throw _classify(error, operation: 'Administrative runtime setup');
    }
  }

  OperationalIntegrationException _classify(
    Object error, {
    required String operation,
  }) {
    if (error is OperationalIntegrationException) return error;
    if (error is TimeoutException || error is SocketException) {
      return OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.networkTransient,
        message: '$operation is unavailable.',
        cause: error,
      );
    }
    if (error is PostgrestException) {
      final diagnostic =
          '${error.message} ${error.details} ${error.hint}'.toLowerCase();
      if (diagnostic.contains('blocked') && diagnostic.contains('device')) {
        return OperationalIntegrationException(
          kind: OperationalIntegrationFailureKind.deviceBlocked,
          message: 'The app device is blocked.',
          cause: error,
        );
      }
      final unauthorized = error.code == 'PGRST301' ||
          diagnostic.contains('authentication required') ||
          diagnostic.contains('jwt');
      final forbidden = error.code == '42501' ||
          diagnostic.contains('membership') ||
          diagnostic.contains('permission') ||
          diagnostic.contains('access') ||
          diagnostic.contains('branch') ||
          diagnostic.contains('business');
      return OperationalIntegrationException(
        kind: unauthorized
            ? OperationalIntegrationFailureKind.unauthorized
            : forbidden
                ? OperationalIntegrationFailureKind.forbidden
                : OperationalIntegrationFailureKind.remoteFailure,
        message: unauthorized || forbidden
            ? '$operation is not authorized.'
            : '$operation returned an error.',
        cause: error,
      );
    }
    return OperationalIntegrationException(
      kind: OperationalIntegrationFailureKind.remoteFailure,
      message: '$operation failed.',
      cause: error,
    );
  }
}
