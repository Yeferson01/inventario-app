import '../data/models/runtime_resolution_models.dart';
import '../data/models/runtime_setup_models.dart';

enum AdministrativeRuntimeSetupOutcome {
  completed,
  notPermitted,
  runtimeStillMissing,
}

class AdministrativeRuntimeSetupResult {
  const AdministrativeRuntimeSetupResult({
    required this.outcome,
    required this.message,
    this.setupResult,
    this.runtime,
  });

  final AdministrativeRuntimeSetupOutcome outcome;
  final String message;
  final BusinessRuntimeSetupResult? setupResult;
  final ResolvedBusinessRuntime? runtime;

  bool get completed => outcome == AdministrativeRuntimeSetupOutcome.completed;
}
