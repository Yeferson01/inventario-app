import 'app_sync_coordinator_models.dart';
import 'app_sync_coordinator_service.dart';

class CashCloseSyncTriggerService {
  CashCloseSyncTriggerService(this._coordinatorService);

  final AppSyncCoordinatorService _coordinatorService;

  Future<AppSyncCoordinatorResult> runAfterCashClose(
    AppSyncCoordinatorInput input,
  ) {
    return _coordinatorService.runSyncForCashClose(input);
  }
}
