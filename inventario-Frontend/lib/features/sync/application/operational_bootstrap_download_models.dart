import '../data/models/local_recovery_models.dart';
import '../data/models/operational_bootstrap_models.dart';

class OperationalBootstrapDownloadRequest {
  const OperationalBootstrapDownloadRequest({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.appDeviceId,
    required this.bundle,
    this.dataset,
    this.limit = 500,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String appDeviceId;
  final String bundle;
  final String? dataset;
  final int limit;

  OperationalBootstrapScope scopeFor(String datasetName) {
    return OperationalBootstrapScope(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
      appDeviceId: appDeviceId,
      bundle: bundle,
      dataset: datasetName,
    );
  }
}

class OperationalBootstrapDownloadResult {
  const OperationalBootstrapDownloadResult({
    required this.snapshotId,
    required this.bundle,
    required this.dataset,
    required this.pagesApplied,
    required this.rowsReceived,
    required this.completed,
    required this.resumed,
    required this.restarted,
    required this.authorizationValidatedAt,
    required this.checkpointStatus,
    required this.warnings,
    this.error,
  });

  final String snapshotId;
  final String bundle;
  final String? dataset;
  final int pagesApplied;
  final int rowsReceived;
  final bool completed;
  final bool resumed;
  final bool restarted;
  final DateTime authorizationValidatedAt;
  final OperationalBootstrapCheckpointStatus checkpointStatus;
  final List<String> warnings;
  final OperationalBootstrapException? error;
}
