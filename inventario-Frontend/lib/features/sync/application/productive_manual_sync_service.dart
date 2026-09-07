import 'app_sync_coordinator_models.dart';
import 'scheduled_sync_models.dart';

typedef ProductiveManualSyncInputLoader = Future<AppSyncCoordinatorInput?>
    Function();
typedef ProductiveManualSyncCoordinator = Future<AppSyncCoordinatorResult>
    Function(AppSyncCoordinatorInput input);
typedef ProductiveManualSyncRunner = Future<ProductiveManualSyncResult>
    Function();

enum ProductiveManualSyncOutcome {
  completed,
  completedWithIssues,
  unavailable,
  failed,
}

class ProductiveManualSyncResult {
  const ProductiveManualSyncResult({
    required this.outcome,
    required this.message,
    this.coordinatorResult,
  });

  final ProductiveManualSyncOutcome outcome;
  final String message;
  final AppSyncCoordinatorResult? coordinatorResult;

  bool get completed => outcome == ProductiveManualSyncOutcome.completed;
}

class ProductiveManualSyncService {
  ProductiveManualSyncService({
    required ProductiveManualSyncInputLoader inputLoader,
    required ProductiveManualSyncCoordinator coordinator,
  })  : _inputLoader = inputLoader,
        _coordinator = coordinator;

  final ProductiveManualSyncInputLoader _inputLoader;
  final ProductiveManualSyncCoordinator _coordinator;

  Future<ProductiveManualSyncResult>? _activeRun;

  Future<ProductiveManualSyncResult> run() {
    final activeRun = _activeRun;
    if (activeRun != null) {
      return activeRun;
    }

    final run = _run();
    _activeRun = run;
    run.whenComplete(() {
      if (identical(_activeRun, run)) {
        _activeRun = null;
      }
    });
    return run;
  }

  Future<ProductiveManualSyncResult> _run() async {
    try {
      final input = await _inputLoader();
      if (input == null) {
        return const ProductiveManualSyncResult(
          outcome: ProductiveManualSyncOutcome.unavailable,
          message:
              'Se requiere una sesión autenticada y un contexto operacional seleccionado.',
        );
      }

      if (!input.isOnline) {
        return const ProductiveManualSyncResult(
          outcome: ProductiveManualSyncOutcome.unavailable,
          message: 'No hay conexión disponible para sincronizar ahora.',
        );
      }

      if (!_hasRequiredContext(input)) {
        return const ProductiveManualSyncResult(
          outcome: ProductiveManualSyncOutcome.unavailable,
          message:
              'La sincronización requiere perfil, negocio, sucursal e instalación válidos.',
        );
      }

      final result = await _coordinator(
        input.copyWithMetadata(const {
          'source': 'productive_manual_sync',
        }),
      );

      if (result.trigger != ScheduledSyncTrigger.manual || !result.didRun) {
        return ProductiveManualSyncResult(
          outcome: ProductiveManualSyncOutcome.unavailable,
          message: result.reason,
          coordinatorResult: result,
        );
      }

      final scheduled = result.scheduledSyncResult;
      if (scheduled == null ||
          scheduled.trigger != ScheduledSyncTrigger.manual) {
        return ProductiveManualSyncResult(
          outcome: ProductiveManualSyncOutcome.failed,
          message:
              'La sincronización manual no devolvió un resultado verificable.',
          coordinatorResult: result,
        );
      }

      final upload = scheduled.catalogUploadResult;
      final pull = scheduled.catalogPullResult;
      final hasUploadIssues = _int(upload?['batches_partial']) > 0 ||
          _int(upload?['batches_failed']) > 0;
      final pullCompleted = pull?['completed'] == true;

      if (hasUploadIssues || !pullCompleted) {
        return ProductiveManualSyncResult(
          outcome: ProductiveManualSyncOutcome.completedWithIssues,
          message:
              'La sincronización terminó con pendientes o un pull incompleto.',
          coordinatorResult: result,
        );
      }

      return ProductiveManualSyncResult(
        outcome: ProductiveManualSyncOutcome.completed,
        message: 'Pendientes publicados y catálogo actualizado.',
        coordinatorResult: result,
      );
    } catch (_) {
      return const ProductiveManualSyncResult(
        outcome: ProductiveManualSyncOutcome.failed,
        message:
            'No fue posible completar la sincronización. Los pendientes se conservaron.',
      );
    }
  }

  bool _hasRequiredContext(AppSyncCoordinatorInput input) {
    return input.businessId.trim().isNotEmpty &&
        input.branchId?.trim().isNotEmpty == true &&
        input.profileId?.trim().isNotEmpty == true &&
        input.installationId.trim().isNotEmpty;
  }
}

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
