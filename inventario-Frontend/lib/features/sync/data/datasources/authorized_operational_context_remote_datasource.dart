import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/authorized_operational_context_models.dart';
import '../models/operational_integration_failure.dart';

typedef AuthorizedOperationalContextsRpcInvoker = Future<Object?> Function();

class AuthorizedOperationalContextRemoteDataSource {
  AuthorizedOperationalContextRemoteDataSource(SupabaseClient client)
      : this.withInvoker(
          () => client.rpc('list_authorized_operational_contexts'),
        );

  AuthorizedOperationalContextRemoteDataSource.withInvoker(this._invoke);

  final AuthorizedOperationalContextsRpcInvoker _invoke;

  Future<AuthorizedOperationalContextsResponse> listAuthorizedContexts() async {
    try {
      return AuthorizedOperationalContextsResponse.fromRpc(await _invoke());
    } on OperationalIntegrationException {
      rethrow;
    } on TimeoutException catch (error) {
      throw OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.networkTransient,
        message: 'Authorized context discovery timed out.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.networkTransient,
        message: 'Authorized context discovery is unavailable.',
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
          diagnostic.contains('access');
      throw OperationalIntegrationException(
        kind: unauthorized
            ? OperationalIntegrationFailureKind.unauthorized
            : forbidden
                ? OperationalIntegrationFailureKind.forbidden
                : OperationalIntegrationFailureKind.remoteFailure,
        message: unauthorized || forbidden
            ? 'Authorized context discovery is not authorized.'
            : 'Authorized context discovery returned an error.',
        cause: error,
      );
    } catch (error) {
      throw OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.remoteFailure,
        message: 'Authorized context discovery failed.',
        cause: error,
      );
    }
  }
}
