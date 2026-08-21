import '../data/datasources/runtime_resolution_remote_datasource.dart';
import '../data/models/operational_integration_failure.dart';
import '../data/models/runtime_resolution_models.dart';

class RuntimeResolutionService {
  RuntimeResolutionService(this._remoteDataSource);

  final RuntimeResolutionRemoteDataSource _remoteDataSource;

  Future<ResolvedBusinessRuntime> resolve({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async {
    if (profileId.trim().isEmpty ||
        businessId.trim().isEmpty ||
        branchId.trim().isEmpty) {
      throw const OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.malformedResponse,
        message: 'Runtime resolution requires a complete explicit scope.',
      );
    }
    final runtime = await _remoteDataSource.resolve(
      businessId: businessId,
      branchId: branchId,
    );
    if (runtime.profileId != profileId) {
      throw const OperationalIntegrationException(
        kind: OperationalIntegrationFailureKind.scopeMismatch,
        message: 'Resolved runtime profile does not match auth.',
      );
    }
    return runtime;
  }
}
