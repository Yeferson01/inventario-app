import '../../../core/logging/app_logger.dart';
import '../data/models/catalog_remote_models.dart';
import 'catalog_readiness.dart';

typedef CatalogReadinessReader = Future<CatalogReadiness> Function(
  String businessId,
);
typedef CatalogInitialPullRunner = Future<CatalogSyncRunResult> Function({
  required String businessId,
});
typedef CatalogBootstrapContinuation = bool Function();
typedef CatalogBootstrapYield = Future<void> Function();

enum InitialCatalogBootstrapOutcome {
  operationalNotReady,
  alreadyReady,
  completed,
  incomplete,
  failed,
}

class InitialCatalogBootstrapResult {
  const InitialCatalogBootstrapResult({
    required this.outcome,
    required this.readiness,
    required this.runs,
    this.lastRun,
  });

  final InitialCatalogBootstrapOutcome outcome;
  final CatalogReadiness readiness;
  final int runs;
  final CatalogSyncRunResult? lastRun;
}

class InitialCatalogBootstrapCoordinator {
  InitialCatalogBootstrapCoordinator({
    required CatalogReadinessReader readReadiness,
    required CatalogInitialPullRunner pullCatalog,
    int maxConsecutiveRuns = 10,
    CatalogBootstrapYield? yieldBetweenRuns,
  })  : _readReadiness = readReadiness,
        _pullCatalog = pullCatalog,
        _maxConsecutiveRuns = maxConsecutiveRuns,
        _yieldBetweenRuns = yieldBetweenRuns ?? _yieldToEventLoop {
    if (maxConsecutiveRuns <= 0) {
      throw ArgumentError.value(
        maxConsecutiveRuns,
        'maxConsecutiveRuns',
        'must be greater than zero',
      );
    }
  }

  final CatalogReadinessReader _readReadiness;
  final CatalogInitialPullRunner _pullCatalog;
  final int _maxConsecutiveRuns;
  final CatalogBootstrapYield _yieldBetweenRuns;
  final Map<String, Future<InitialCatalogBootstrapResult>> _activeRuns = {};

  Future<InitialCatalogBootstrapResult> ensureCatalogReady({
    required String businessId,
    required bool operationalReady,
    CatalogBootstrapContinuation? shouldContinue,
  }) {
    final normalizedBusinessId = businessId.trim();
    if (normalizedBusinessId.isEmpty) {
      throw ArgumentError.value(businessId, 'businessId', 'must not be empty');
    }

    final active = _activeRuns[normalizedBusinessId];
    if (active != null) return active;

    final run = _run(
      businessId: normalizedBusinessId,
      operationalReady: operationalReady,
      shouldContinue: shouldContinue ?? _alwaysContinue,
    );
    _activeRuns[normalizedBusinessId] = run;
    run.then<void>(
      (_) => _removeActiveRun(normalizedBusinessId, run),
      onError: (_, __) => _removeActiveRun(normalizedBusinessId, run),
    );
    return run;
  }

  Future<InitialCatalogBootstrapResult> _run({
    required String businessId,
    required bool operationalReady,
    required CatalogBootstrapContinuation shouldContinue,
  }) async {
    var readiness = await _readReadiness(businessId);
    if (!operationalReady) {
      return InitialCatalogBootstrapResult(
        outcome: InitialCatalogBootstrapOutcome.operationalNotReady,
        readiness: readiness,
        runs: 0,
      );
    }
    if (readiness.isReady) {
      return InitialCatalogBootstrapResult(
        outcome: InitialCatalogBootstrapOutcome.alreadyReady,
        readiness: readiness,
        runs: 0,
      );
    }

    AppLogger.info('Initial catalog bootstrap started: business=$businessId');
    CatalogSyncRunResult? lastRun;
    var runs = 0;

    for (var runNumber = 1;
        runNumber <= _maxConsecutiveRuns && shouldContinue();
        runNumber++) {
      runs = runNumber;
      lastRun = await _pullCatalog(businessId: businessId);
      readiness = await _readReadiness(businessId);

      if (lastRun.status == CatalogSyncRunStatus.complete &&
          readiness.isReady) {
        AppLogger.info(
          'Initial catalog bootstrap completed: business=$businessId '
          'runs=$runNumber',
        );
        return InitialCatalogBootstrapResult(
          outcome: InitialCatalogBootstrapOutcome.completed,
          readiness: readiness,
          runs: runNumber,
          lastRun: lastRun,
        );
      }

      if (lastRun.status == CatalogSyncRunStatus.failed) {
        AppLogger.warning(
          'Initial catalog bootstrap failed: business=$businessId '
          'classification=${lastRun.failureClassification}',
        );
        return InitialCatalogBootstrapResult(
          outcome: InitialCatalogBootstrapOutcome.failed,
          readiness: readiness,
          runs: runNumber,
          lastRun: lastRun,
        );
      }

      AppLogger.info(
        'Initial catalog bootstrap incomplete/resumable: '
        'business=$businessId run=$runNumber',
      );
      if (runNumber < _maxConsecutiveRuns && shouldContinue()) {
        await _yieldBetweenRuns();
      }
    }

    readiness = await _readReadiness(businessId);
    return InitialCatalogBootstrapResult(
      outcome: InitialCatalogBootstrapOutcome.incomplete,
      readiness: readiness,
      runs: runs,
      lastRun: lastRun,
    );
  }

  void _removeActiveRun(
    String businessId,
    Future<InitialCatalogBootstrapResult> run,
  ) {
    if (identical(_activeRuns[businessId], run)) {
      _activeRuns.remove(businessId);
    }
  }
}

bool _alwaysContinue() => true;

Future<void> _yieldToEventLoop() => Future<void>.delayed(Duration.zero);
