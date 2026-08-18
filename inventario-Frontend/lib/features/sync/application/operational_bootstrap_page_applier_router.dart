import '../data/models/operational_bootstrap_models.dart';
import 'operational_bootstrap_page_applier.dart';

class OperationalBootstrapPageApplierRouter
    implements
        OperationalBootstrapPageApplier,
        OperationalBootstrapDatasetFinalizer,
        OperationalBootstrapDatasetOrdering {
  OperationalBootstrapPageApplierRouter({
    required Map<String, OperationalBootstrapPageApplier> routes,
    Map<String, List<String>> dependencyOrder = const {},
  })  : _routes = Map.unmodifiable(routes),
        _dependencyOrder = Map.unmodifiable(dependencyOrder);

  final Map<String, OperationalBootstrapPageApplier> _routes;
  final Map<String, List<String>> _dependencyOrder;

  @override
  List<T> orderDatasets<T>(
    String bundle,
    List<T> values,
    String Function(T value) datasetOf,
  ) {
    final order = _dependencyOrder[bundle];
    if (order == null) return List<T>.of(values);
    final positions = {
      for (var index = 0; index < order.length; index++) order[index]: index
    };
    return List<T>.of(values)
      ..sort(
        (left, right) => (positions[datasetOf(left)] ?? order.length)
            .compareTo(positions[datasetOf(right)] ?? order.length),
      );
  }

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
