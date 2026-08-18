import '../data/models/operational_bootstrap_models.dart';
import 'operational_bootstrap_page_applier.dart';

class OperationalBootstrapPageApplierRouter
    implements
        OperationalBootstrapPageApplier,
        OperationalBootstrapDatasetFinalizer {
  OperationalBootstrapPageApplierRouter({
    required Map<String, OperationalBootstrapPageApplier> routes,
  }) : _routes = Map.unmodifiable(routes);

  final Map<String, OperationalBootstrapPageApplier> _routes;

  @override
  Future<OperationalBootstrapPageApplyResult> applyPage({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  }) {
    return _route(snapshot.bundle, page.dataset).applyPage(
      profileId: profileId,
      snapshot: snapshot,
      page: page,
    );
  }

  @override
  Future<void> finalizeDataset({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required OperationalBootstrapDatasetPage page,
  }) async {
    final applier = _route(snapshot.bundle, page.dataset);
    if (applier is OperationalBootstrapDatasetFinalizer) {
      await (applier as OperationalBootstrapDatasetFinalizer).finalizeDataset(
        profileId: profileId,
        snapshot: snapshot,
        page: page,
      );
    }
  }

  OperationalBootstrapPageApplier _route(String bundle, String dataset) {
    final key = '$bundle/$dataset';
    final applier = _routes[key];
    if (applier == null) {
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.malformedResponse,
        message: 'No local bootstrap applier is registered for $key.',
      );
    }
    return applier;
  }
}
