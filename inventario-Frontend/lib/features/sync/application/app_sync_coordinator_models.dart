import '../data/models/runtime_setup_models.dart';
import 'scheduled_sync_models.dart';

class AppSyncCoordinatorInput {
  const AppSyncCoordinatorInput({
    required this.businessId,
    required this.installationId,
    required this.isOnline,
    this.branchId,
    this.profileId,
    this.deviceName,
    this.platform,
    this.appVersion,
    this.osVersion,
    this.metadata,
    this.now,
  });

  final String businessId;
  final String installationId;
  final bool isOnline;

  final String? branchId;
  final String? profileId;

  final String? deviceName;
  final String? platform;
  final String? appVersion;
  final String? osVersion;

  final Map<String, dynamic>? metadata;
  final DateTime? now;

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      'profile_id': profileId,
      'installation_id': installationId,
      'is_online': isOnline,
      'device_name': deviceName,
      'platform': platform,
      'app_version': appVersion,
      'os_version': osVersion,
      'metadata': metadata,
      'now': now?.toUtc().toIso8601String(),
    };
  }
}

class AppSyncCoordinatorResult {
  const AppSyncCoordinatorResult({
    required this.didRun,
    required this.didPrepareRuntime,
    required this.trigger,
    required this.reason,
    this.runtimeContext,
    this.scheduledSyncResult,
  });

  final bool didRun;
  final bool didPrepareRuntime;
  final ScheduledSyncTrigger trigger;
  final String reason;

  final AppRuntimeContext? runtimeContext;
  final ScheduledSyncRunResult? scheduledSyncResult;

  Map<String, dynamic> toJson() {
    return {
      'did_run': didRun,
      'did_prepare_runtime': didPrepareRuntime,
      'trigger': trigger.code,
      'reason': reason,
      'runtime_context': runtimeContext?.toJson(),
      'scheduled_sync_result': scheduledSyncResult?.toJson(),
    };
  }
}
