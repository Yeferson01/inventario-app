import '../data/models/authorized_operational_context_models.dart';
import '../data/models/runtime_resolution_models.dart';
import '../data/models/runtime_setup_models.dart';
import 'operational_bootstrap_orchestration_models.dart';

enum OperationalBootstrapEntryOutcome {
  selectionRequired,
  deviceBlocked,
  runtimeReadyAndBootstrapCompleted,
  runtimeSetupRequired,
  authorizationRevoked,
  transientFailure,
  bootstrapRecoveryBlocked,
  failed,
}

class OperationalContextSelection {
  const OperationalContextSelection({
    required this.businessId,
    required this.branchId,
  });

  final String businessId;
  final String branchId;
}

class OperationalBootstrapEntryRequest {
  const OperationalBootstrapEntryRequest({
    required this.mode,
    this.selection,
    this.deviceName,
    this.platform,
    this.appVersion,
    this.osVersion,
    this.metadata = const {},
    this.pageLimit = 1000,
  });

  final OperationalBootstrapMode mode;
  final OperationalContextSelection? selection;
  final String? deviceName;
  final String? platform;
  final String? appVersion;
  final String? osVersion;
  final Map<String, Object?> metadata;
  final int pageLimit;
}

class OperationalBootstrapEntryResult {
  const OperationalBootstrapEntryResult({
    required this.outcome,
    required this.contexts,
    required this.message,
    required this.offlineReady,
    required this.canRequestAdministrativeSetup,
    this.profileId,
    this.installationId,
    this.selectedContext,
    this.device,
    this.runtime,
    this.bootstrapResult,
  });

  final OperationalBootstrapEntryOutcome outcome;
  final List<AuthorizedOperationalContext> contexts;
  final String message;
  final bool offlineReady;
  final bool canRequestAdministrativeSetup;
  final String? profileId;
  final String? installationId;
  final AuthorizedOperationalContext? selectedContext;
  final RegisteredAppDeviceResult? device;
  final ResolvedBusinessRuntime? runtime;
  final OperationalBootstrapResult? bootstrapResult;

  Map<String, Object?> toJson() => {
        'outcome': outcome.name,
        'profile_id': profileId,
        'installation_id': installationId,
        'contexts_discovered': contexts.length,
        'contexts': contexts.map((context) => context.toJson()).toList(),
        'selected_context': selectedContext?.toJson(),
        'app_device_id': device?.appDeviceId,
        'device_status': device?.status,
        'runtime_ready': runtime?.runtimeReady,
        'runtime': runtime?.toJson(),
        'bootstrap_outcome': bootstrapResult?.outcome.name,
        'offline_ready': offlineReady,
        'can_request_administrative_setup': canRequestAdministrativeSetup,
        'blocking_issues': bootstrapResult?.blockingIssues
            .map(
              (issue) => {
                'issue_type': issue.issueType,
                'domain': issue.domain,
                'entity_type': issue.entityType,
                'entity_id': issue.entityId,
                'message': issue.message,
              },
            )
            .toList(),
        'message': message,
      };
}
