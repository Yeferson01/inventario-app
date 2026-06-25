import '../../../core/logging/app_logger.dart';
import '../data/datasources/runtime_setup_remote_datasource.dart';
import '../data/models/runtime_setup_models.dart';
import 'app_runtime_context_store.dart';

class AppRuntimeSetupService {
  AppRuntimeSetupService({
    required RuntimeSetupRemoteDataSource remoteDataSource,
    required AppRuntimeContextStore contextStore,
  })  : _remoteDataSource = remoteDataSource,
        _contextStore = contextStore;

  final RuntimeSetupRemoteDataSource _remoteDataSource;
  final AppRuntimeContextStore _contextStore;

  Future<AppRuntimeContext> prepareRuntimeContext({
    required String businessId,
    required String installationId,
    String? branchId,
    String? profileId,
    String? deviceName,
    String? platform,
    String? appVersion,
    String? osVersion,
    Map<String, dynamic>? metadata,
  }) async {
    final registeredDevice = await _remoteDataSource.registerOrUpdateAppDevice(
      RegisterAppDeviceInput(
        businessId: businessId,
        branchId: branchId,
        profileId: profileId,
        installationId: installationId,
        deviceName: deviceName,
        platform: platform,
        appVersion: appVersion,
        osVersion: osVersion,
        metadata: {
          'source': 'flutter_runtime_setup',
          if (metadata != null) ...metadata,
        },
      ),
    );

    final runtimeSetup = await _remoteDataSource.ensureBusinessRuntimeSetup(
      EnsureBusinessRuntimeSetupInput(
        businessId: businessId,
        branchId: branchId,
        profileId: profileId,
        appDeviceId: registeredDevice.appDeviceId,
        metadata: {
          'source': 'flutter_runtime_setup',
        },
      ),
    );

    final context = AppRuntimeContext(
      businessId: businessId,
      branchId: runtimeSetup.branchId ?? branchId,
      profileId: profileId,
      installationId: installationId,
      appDeviceId: registeredDevice.appDeviceId,
      cashRegisterId: runtimeSetup.cashRegisterId,
      cashSessionId: runtimeSetup.cashSessionId,
      receiptSequenceId: runtimeSetup.receiptSequenceId,
    );

    await _contextStore.saveContext(context);

    AppLogger.info(
      'Runtime context prepared: business=$businessId '
      'branch=${context.branchId} appDevice=${context.appDeviceId}',
    );

    return context;
  }

  Future<AppRuntimeContext?> getStoredContext({
    required String businessId,
    required String installationId,
  }) {
    return _contextStore.getContext(
      businessId: businessId,
      installationId: installationId,
    );
  }
}
