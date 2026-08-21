import 'dart:async';

import '../data/datasources/authorized_operational_context_remote_datasource.dart';
import '../data/models/authorized_operational_context_models.dart';
import '../data/models/operational_integration_failure.dart';

typedef AuthorizedProfileIdResolver = FutureOr<String?> Function();

class AuthorizedOperationalContextService {
  AuthorizedOperationalContextService({
    required AuthorizedOperationalContextRemoteDataSource remoteDataSource,
    required AuthorizedProfileIdResolver authenticatedProfileId,
  })  : _remoteDataSource = remoteDataSource,
        _authenticatedProfileId = authenticatedProfileId;

  final AuthorizedOperationalContextRemoteDataSource _remoteDataSource;
  final AuthorizedProfileIdResolver _authenticatedProfileId;

  Future<List<AuthorizedOperationalContext>> listAuthorizedContexts() async {
    final profileId = await _authenticatedProfileId();
    if (profileId == null || profileId.trim().isEmpty) {
      throw const OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.unauthorized,
        message: 'An authenticated profile is required for context discovery.',
      );
    }

    final response = await _remoteDataSource.listAuthorizedContexts();
    if (response.profileId != profileId) {
      throw const OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.scopeMismatch,
        message: 'Discovery response profile does not match auth.',
      );
    }

    final scopes = <String>{};
    final branchOwners = <String, String>{};
    for (final context in response.contexts) {
      if (context.profileId != profileId ||
          context.businessId.trim().isEmpty ||
          context.branchId.trim().isEmpty ||
          context.businessStatus != 'active' ||
          context.branchStatus != 'active') {
        throw const OperationalIntegrationException(
          kind: OperationalIntegrationFailureKind.scopeMismatch,
          message: 'Discovery returned an invalid operational scope.',
        );
      }
      if (!scopes.add(context.scopeKey)) {
        throw const OperationalIntegrationException(
          kind: OperationalIntegrationFailureKind.malformedResponse,
          message: 'Discovery returned a duplicate operational context.',
        );
      }
      final priorBusiness = branchOwners[context.branchId];
      if (priorBusiness != null && priorBusiness != context.businessId) {
        throw const OperationalIntegrationException(
          kind: OperationalIntegrationFailureKind.scopeMismatch,
          message: 'Discovery returned one branch under multiple businesses.',
        );
      }
      branchOwners[context.branchId] = context.businessId;
    }
    return List.unmodifiable(response.contexts);
  }
}
