import 'app_business_selection_models.dart';
import 'app_context_models.dart';

class AppE2ELocalFlowInput {
  const AppE2ELocalFlowInput({
    required this.profileId,
    required this.isOnline,
    this.preferredBusinessId,
    this.preferredBranchId,
    this.lastSyncStatus,
    this.runManualSync = false,
    this.deviceName,
    this.platform,
    this.appVersion,
    this.osVersion,
    this.metadata,
  });

  final String profileId;
  final bool isOnline;

  final String? preferredBusinessId;
  final String? preferredBranchId;
  final String? lastSyncStatus;

  final bool runManualSync;

  final String? deviceName;
  final String? platform;
  final String? appVersion;
  final String? osVersion;

  final Map<String, dynamic>? metadata;

  Map<String, dynamic> toJson() {
    return {
      'profile_id': profileId,
      'is_online': isOnline,
      'preferred_business_id': preferredBusinessId,
      'preferred_branch_id': preferredBranchId,
      'last_sync_status': lastSyncStatus,
      'run_manual_sync': runManualSync,
      'device_name': deviceName,
      'platform': platform,
      'app_version': appVersion,
      'os_version': osVersion,
      'metadata': metadata,
    };
  }
}

class AppE2ELocalFlowResult {
  const AppE2ELocalFlowResult({
    required this.installationId,
    required this.availableContextCount,
    required this.didSelectContext,
    required this.didResolveCurrentContext,
    required this.didAttemptManualSync,
    required this.didRunManualSync,
    required this.reason,
    this.selectedContext,
    this.currentContext,
    this.manualSyncResult,
  });

  final String installationId;
  final int availableContextCount;

  final bool didSelectContext;
  final bool didResolveCurrentContext;
  final bool didAttemptManualSync;
  final bool didRunManualSync;

  final String reason;

  final AppBusinessSelectionResult? selectedContext;
  final AppCurrentContext? currentContext;
  final Map<String, dynamic>? manualSyncResult;

  bool get successfulLocalValidation {
    return didSelectContext && didResolveCurrentContext;
  }

  List<String> get permissions {
    return currentContext?.permissions.sorted() ?? const <String>[];
  }

  Map<String, dynamic> toJson() {
    return {
      'installation_id': installationId,
      'available_context_count': availableContextCount,
      'did_select_context': didSelectContext,
      'did_resolve_current_context': didResolveCurrentContext,
      'did_attempt_manual_sync': didAttemptManualSync,
      'did_run_manual_sync': didRunManualSync,
      'reason': reason,
      'selected_context': selectedContext?.toJson(),
      'current_context': currentContext?.toJson(),
      'permissions': permissions,
      'manual_sync_result': manualSyncResult,
      'successful_local_validation': successfulLocalValidation,
    };
  }
}
