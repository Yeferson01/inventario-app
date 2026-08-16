import '../data/models/operational_bootstrap_models.dart';

abstract interface class OperationalBootstrapPageApplier {
  Future<OperationalBootstrapPageApplyResult> applyPage({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  });
}

class OperationalBootstrapPageApplyResult {
  const OperationalBootstrapPageApplyResult({
    this.seenEntityIds = const [],
    this.warnings = const [],
  });

  final List<String> seenEntityIds;
  final List<String> warnings;
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
