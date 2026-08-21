import '../data/models/local_recovery_models.dart';

enum OperationalBootstrapMode {
  bootstrap,
  recovery,
  refresh,
}

enum OperationalBootstrapOutcome {
  ready,
  authorizationRevoked,
  runtimeSetupRequired,
  recoveryBlocked,
  networkUnavailableWithCachedContext,
  transientFailure,
  failed,
}

enum OperationalBootstrapProgressStage {
  idle,
  validatingContext,
  core,
  products,
  inventory,
  cash,
  finalizing,
  ready,
  blocked,
  error,
}

class OperationalBootstrapRuntimeResolution {
  const OperationalBootstrapRuntimeResolution({
    required this.businessId,
    required this.branchId,
    required this.installationId,
    required this.appDeviceId,
    required this.runtimeReady,
    this.cashRegisterId,
    this.cashSessionId,
    this.receiptSequenceId,
  });

  final String businessId;
  final String branchId;
  final String installationId;
  final String appDeviceId;
  final bool runtimeReady;
  final String? cashRegisterId;
  final String? cashSessionId;
  final String? receiptSequenceId;
}

class OperationalBootstrapRequest {
  const OperationalBootstrapRequest({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.installationId,
    required this.appDeviceId,
    required this.runtime,
    required this.mode,
    this.pageLimit = 1000,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String installationId;
  final String appDeviceId;
  final OperationalBootstrapRuntimeResolution runtime;
  final OperationalBootstrapMode mode;
  final int pageLimit;
}

class OperationalBootstrapProgress {
  const OperationalBootstrapProgress({
    required this.stage,
    this.bundle,
    this.dataset,
    this.message,
  });

  const OperationalBootstrapProgress.idle()
      : stage = OperationalBootstrapProgressStage.idle,
        bundle = null,
        dataset = null,
        message = null;

  final OperationalBootstrapProgressStage stage;
  final String? bundle;
  final String? dataset;
  final String? message;
}

class OperationalBootstrapBlockingIssue {
  const OperationalBootstrapBlockingIssue({
    required this.issueType,
    required this.domain,
    required this.message,
    this.entityType,
    this.entityId,
    this.metadata = const {},
  });

  final String issueType;
  final String domain;
  final String? entityType;
  final String? entityId;
  final String message;
  final Map<String, Object?> metadata;
}

class OperationalBootstrapCheckpointSummary {
  const OperationalBootstrapCheckpointSummary({
    required this.bundle,
    required this.dataset,
    required this.present,
    required this.complete,
    required this.convergenceStatus,
    this.status,
  });

  factory OperationalBootstrapCheckpointSummary.missing({
    required String bundle,
    required String dataset,
  }) {
    return OperationalBootstrapCheckpointSummary(
      bundle: bundle,
      dataset: dataset,
      present: false,
      complete: false,
      convergenceStatus: 'missing',
    );
  }

  factory OperationalBootstrapCheckpointSummary.fromRecord(
    OperationalBootstrapCheckpointRecord record,
  ) {
    return OperationalBootstrapCheckpointSummary(
      bundle: record.scope.bundle,
      dataset: record.scope.dataset,
      present: true,
      complete: record.isComplete,
      status: record.status,
      convergenceStatus: record.convergenceStatus,
    );
  }

  final String bundle;
  final String dataset;
  final bool present;
  final bool complete;
  final OperationalBootstrapCheckpointStatus? status;
  final String convergenceStatus;
}

class OperationalBootstrapResult {
  const OperationalBootstrapResult({
    required this.outcome,
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.appDeviceId,
    required this.requiredBundles,
    required this.completedBundles,
    required this.blockingIssues,
    required this.warnings,
    required this.recoveredCounts,
    required this.checkpoints,
    required this.offlineReady,
    required this.message,
    this.authorizationValidatedAt,
    this.canonicalCashRegisterId,
    this.openCashSessionId,
    this.runtimeSetupAllowed = false,
  });

  final OperationalBootstrapOutcome outcome;
  final String profileId;
  final String businessId;
  final String branchId;
  final String appDeviceId;
  final List<String> requiredBundles;
  final List<String> completedBundles;
  final DateTime? authorizationValidatedAt;
  final String? canonicalCashRegisterId;
  final String? openCashSessionId;
  final List<OperationalBootstrapBlockingIssue> blockingIssues;
  final List<String> warnings;
  final Map<String, int> recoveredCounts;
  final List<OperationalBootstrapCheckpointSummary> checkpoints;
  final bool offlineReady;
  final bool runtimeSetupAllowed;
  final String message;
}
