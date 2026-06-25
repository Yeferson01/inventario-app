import '../../../core/logging/app_logger.dart';
import '../data/datasources/operational_context_local_dao.dart';
import '../data/datasources/operational_context_remote_datasource.dart';
import '../data/models/operational_context_pull_models.dart';

class OperationalContextPullService {
  OperationalContextPullService({
    required OperationalContextRemoteDataSource remoteDataSource,
    required OperationalContextLocalDao localDao,
  })  : _remoteDataSource = remoteDataSource,
        _localDao = localDao;

  final OperationalContextRemoteDataSource _remoteDataSource;
  final OperationalContextLocalDao _localDao;

  Future<OperationalContextPullResult> pullAndApply({
    required String businessId,
    required String profileId,
  }) async {
    final snapshot = await _remoteDataSource.pullOperationalContext(
      businessId: businessId,
      profileId: profileId,
    );

    final result = await _localDao.applySnapshot(
      businessId: businessId,
      profileId: profileId,
      snapshot: snapshot,
    );

    AppLogger.info(
      'Operational context pulled: business=$businessId '
      'profile=$profileId total=${result.totalApplied}',
    );

    return result;
  }
}
