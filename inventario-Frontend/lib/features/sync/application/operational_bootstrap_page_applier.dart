import '../data/models/operational_bootstrap_models.dart';

abstract interface class OperationalBootstrapPageApplier {
  Future<OperationalBootstrapPageApplyResult> applyPage({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  });
}

abstract interface class OperationalBootstrapDatasetFinalizer {
  Future<void> finalizeDataset({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  });
}

abstract interface class OperationalBootstrapDatasetOrdering {
  List<T> orderDatasets<T>(
    String bundle,
    List<T> values,
    String Function(T value) datasetOf,
  );
}

class OperationalBootstrapPageApplyResult {
  const OperationalBootstrapPageApplyResult({
    this.seenEntityIds = const [],
    this.warnings = const [],
    this.completeConvergenceStatus = 'complete',
  });

  final List<String> seenEntityIds;
  final List<String> warnings;
  final String completeConvergenceStatus;
}

class JournalOnlyOperationalBootstrapPageApplier
    implements OperationalBootstrapPageApplier {
  const JournalOnlyOperationalBootstrapPageApplier();

  @override
  Future<OperationalBootstrapPageApplyResult> applyPage({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  }) async {
    return OperationalBootstrapPageApplyResult(
      seenEntityIds: page.rows
          .map((row) => row.entityId)
          .whereType<String>()
          .toList(growable: false),
    );
  }
}
