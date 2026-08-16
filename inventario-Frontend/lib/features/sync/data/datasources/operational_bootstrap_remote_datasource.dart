import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/operational_bootstrap_models.dart';

typedef OperationalBootstrapRpcInvoker = Future<Object?> Function(
  Map<String, Object?> parameters,
);

class OperationalBootstrapRemoteDataSource {
  OperationalBootstrapRemoteDataSource(SupabaseClient client)
      : this.withInvoker(
          (parameters) async => client.rpc(
            'pull_operational_bootstrap_snapshot',
            params: parameters,
          ),
        );

  OperationalBootstrapRemoteDataSource.withInvoker(this._invoke);

  final OperationalBootstrapRpcInvoker _invoke;

  Future<OperationalBootstrapSnapshotPage> pullPage(
    OperationalBootstrapRemoteRequest request,
  ) async {
    if (request.limit < 1 || request.limit > 1000) {
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.malformedResponse,
        message: 'Bootstrap page limit must be between 1 and 1000.',
      );
    }
    if (request.pageToken != null && request.dataset == null) {
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.malformedResponse,
        message: 'A continuation token requires an explicit dataset.',
      );
    }

    try {
      final raw = await _invoke(request.toRpcParams());
      final response = OperationalBootstrapSnapshotPage.fromRpc(raw);
      _validateResponseScope(request, response);
      return response;
    } on OperationalBootstrapException {
      rethrow;
    } on TimeoutException catch (error) {
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.networkTransient,
        message: 'Operational bootstrap request timed out.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.networkTransient,
        message: 'Operational bootstrap network request failed.',
        cause: error,
      );
    } on PostgrestException catch (error) {
      throw _classifyPostgrest(error);
    } catch (error) {
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.remoteFailure,
        message: 'Operational bootstrap RPC failed.',
        cause: error,
      );
    }
  }

  void _validateResponseScope(
    OperationalBootstrapRemoteRequest request,
    OperationalBootstrapSnapshotPage response,
  ) {
    final mismatches = <String>[];
    if (response.businessId != request.businessId) {
      mismatches.add('business');
    }
    if (response.branchId != request.branchId) {
      mismatches.add('branch');
    }
    if (response.appDeviceId != request.appDeviceId) {
      mismatches.add('appDevice');
    }
    if (response.bundle != request.bundle) {
      mismatches.add('bundle');
    }
    if (response.datasetRequested != request.dataset) {
      mismatches.add('dataset');
    }
    if (request.dataset != null &&
        (response.datasets.length != 1 ||
            !response.datasets.containsKey(request.dataset))) {
      mismatches.add('dataset payload');
    }

    if (mismatches.isNotEmpty) {
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.scopeMismatch,
        message: 'Bootstrap response scope mismatch: ${mismatches.join(', ')}.',
      );
    }
  }

  OperationalBootstrapException _classifyPostgrest(
    PostgrestException error,
  ) {
    final code = error.code?.toUpperCase() ?? '';
    final diagnostic = [
      error.message,
      error.details,
      error.hint,
    ].whereType<Object>().join(' ').toLowerCase();

    if (code == 'PGRST301' ||
        diagnostic.contains('authentication required') ||
        diagnostic.contains('jwt')) {
      return OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.unauthorized,
        message: 'Operational bootstrap authentication failed.',
        cause: error,
      );
    }
    if (diagnostic.contains('page token') &&
        (diagnostic.contains('invalid') ||
            diagnostic.contains('mismatch') ||
            diagnostic.contains('not verifiable') ||
            diagnostic.contains('expired'))) {
      return OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.invalidToken,
        message: 'Operational bootstrap page token cannot be resumed.',
        cause: error,
      );
    }
    if (code == '42501' ||
        diagnostic.contains('membership') ||
        diagnostic.contains('does not authorize') ||
        diagnostic.contains('access denied') ||
        diagnostic.contains('insufficient permission') ||
        diagnostic.contains('business does not exist') ||
        diagnostic.contains('branch does not') ||
        diagnostic.contains('branch is inactive') ||
        diagnostic.contains('active branch access') ||
        diagnostic.contains('app_device')) {
      return OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.forbidden,
        message: 'Operational bootstrap context is not authorized.',
        cause: error,
      );
    }

    return OperationalBootstrapException(
      kind: OperationalBootstrapFailureKind.remoteFailure,
      message: 'Operational bootstrap RPC returned an error.',
      cause: error,
    );
  }
}
