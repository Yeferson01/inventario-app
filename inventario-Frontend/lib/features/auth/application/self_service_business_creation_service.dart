import '../data/datasources/self_service_business_creation_remote_datasource.dart';

typedef SelfServiceOnlineCheck = Future<bool> Function();

class SelfServiceBusinessCreationService {
  const SelfServiceBusinessCreationService({
    required SelfServiceBusinessCreationRemoteDataSource remote,
    required SelfServiceOnlineCheck isOnline,
  })  : _remote = remote,
        _isOnline = isOnline;

  static const defaultBranchName = 'Sucursal Principal';

  final SelfServiceBusinessCreationRemoteDataSource _remote;
  final SelfServiceOnlineCheck _isOnline;

  Future<SelfServiceBusinessCreationResult> create({
    required String businessName,
    required String branchName,
    required String idempotencyKey,
  }) async {
    final normalizedBusinessName = businessName.trim();
    final normalizedBranchName =
        branchName.trim().isEmpty ? defaultBranchName : branchName.trim();
    final normalizedKey = idempotencyKey.trim();
    if (normalizedBusinessName.isEmpty ||
        normalizedBusinessName.length > 255 ||
        normalizedBranchName.length > 255 ||
        normalizedKey.isEmpty) {
      throw const SelfServiceBusinessCreationException(
        kind: SelfServiceBusinessCreationFailureKind.invalidInput,
        message: 'Revisa los datos del negocio e intenta nuevamente.',
      );
    }
    if (!await _isOnline()) {
      throw const SelfServiceBusinessCreationException(
        kind: SelfServiceBusinessCreationFailureKind.network,
        message: 'Necesitas conexión a internet para crear un negocio.',
      );
    }
    return _remote.create(
      businessName: normalizedBusinessName,
      branchName: normalizedBranchName,
      idempotencyKey: normalizedKey,
    );
  }
}
