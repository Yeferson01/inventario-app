import '../data/models/runtime_setup_models.dart';
import 'app_sync_coordinator_models.dart';
import 'productive_sync_status.dart';

typedef ProductiveManualSyncInputLoader = Future<AppSyncCoordinatorInput?>
    Function();
typedef ProductiveManualSyncContextValidator = Future<AppRuntimeContext>
    Function(
  AppSyncCoordinatorInput input,
);
typedef ProductiveSyncDomainRunner = Future<ProductiveSyncDomainResult>
    Function(
  ProductiveSyncExecutionContext context,
);
typedef ProductiveSyncStatusLoader = Future<ProductiveSyncStatus> Function({
  required ProductiveSyncScope scope,
  required bool isOnline,
  required bool isSyncing,
});
typedef ProductiveManualSyncRunner = Future<ProductiveManualSyncResult>
    Function();
typedef ProductiveDependencyProgressLoader = Future<(int, int)> Function({
  required String businessId,
  required String branchId,
});

enum ProductiveSyncTrigger { manual, scheduled, cashClose }

extension ProductiveSyncTriggerCode on ProductiveSyncTrigger {
  String get code => switch (this) {
        ProductiveSyncTrigger.manual => 'manual',
        ProductiveSyncTrigger.scheduled => 'scheduled',
        ProductiveSyncTrigger.cashClose => 'cash_close',
      };
}

enum ProductiveSyncDomain { catalog, cash, pos, purchases, inventory }

class ProductiveSyncDomainResult {
  const ProductiveSyncDomainResult({
    required this.domain,
    required this.attempted,
    required this.succeeded,
    required this.pending,
    required this.requiresAttention,
    required this.failedRetryable,
  });

  const ProductiveSyncDomainResult.succeeded(this.domain)
      : attempted = true,
        succeeded = true,
        pending = false,
        requiresAttention = false,
        failedRetryable = false;

  const ProductiveSyncDomainResult.notAttempted(this.domain)
      : attempted = false,
        succeeded = false,
        pending = false,
        requiresAttention = false,
        failedRetryable = false;

  const ProductiveSyncDomainResult.pending(
    this.domain, {
    this.requiresAttention = false,
    this.failedRetryable = false,
  })  : attempted = true,
        succeeded = false,
        pending = true;

  const ProductiveSyncDomainResult.failedRetryable(this.domain)
      : attempted = true,
        succeeded = false,
        pending = true,
        requiresAttention = false,
        failedRetryable = true;

  final ProductiveSyncDomain domain;
  final bool attempted;
  final bool succeeded;
  final bool pending;
  final bool requiresAttention;
  final bool failedRetryable;

  ProductiveSyncDomainResult merge(ProductiveSyncDomainResult other) {
    if (domain != other.domain) {
      throw ArgumentError(
          'Solo pueden combinarse resultados del mismo dominio.');
    }
    final hasProblem = pending ||
        requiresAttention ||
        failedRetryable ||
        other.pending ||
        other.requiresAttention ||
        other.failedRetryable;
    return ProductiveSyncDomainResult(
      domain: domain,
      attempted: attempted || other.attempted,
      succeeded: !hasProblem && (succeeded || other.succeeded),
      pending: pending || other.pending,
      requiresAttention: requiresAttention || other.requiresAttention,
      failedRetryable: failedRetryable || other.failedRetryable,
    );
  }

  ProductiveSyncDomainResult withPending(bool value) {
    if (!value || pending) return this;
    return ProductiveSyncDomainResult(
      domain: domain,
      attempted: attempted,
      succeeded: false,
      pending: true,
      requiresAttention: requiresAttention,
      failedRetryable: failedRetryable,
    );
  }
}

const _notAttemptedDomainResults = [
  ProductiveSyncDomainResult.notAttempted(ProductiveSyncDomain.catalog),
  ProductiveSyncDomainResult.notAttempted(ProductiveSyncDomain.cash),
  ProductiveSyncDomainResult.notAttempted(ProductiveSyncDomain.pos),
  ProductiveSyncDomainResult.notAttempted(ProductiveSyncDomain.purchases),
  ProductiveSyncDomainResult.notAttempted(ProductiveSyncDomain.inventory),
];

class ProductiveSyncExecutionContext {
  const ProductiveSyncExecutionContext({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.installationId,
    required this.appDeviceId,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String installationId;
  final String appDeviceId;

  ProductiveSyncScope get scope => ProductiveSyncScope(
        profileId: profileId,
        businessId: businessId,
        branchId: branchId,
      );
}

enum ProductiveManualSyncOutcome {
  completed,
  pending,
  requiresAttention,
  unavailable,
  failed,
}

class ProductiveManualSyncResult {
  const ProductiveManualSyncResult({
    required this.outcome,
    required this.message,
    this.domainResults = const [],
    this.finalStatus,
    this.scope,
  });

  final ProductiveManualSyncOutcome outcome;
  final String message;
  final List<ProductiveSyncDomainResult> domainResults;
  final ProductiveSyncStatus? finalStatus;
  final ProductiveSyncScope? scope;

  bool get completed => outcome == ProductiveManualSyncOutcome.completed;
}

class ProductiveManualSyncService {
  ProductiveManualSyncService({
    required ProductiveManualSyncInputLoader inputLoader,
    required ProductiveManualSyncContextValidator contextValidator,
    required ProductiveSyncDomainRunner catalogUploadRunner,
    required ProductiveSyncDomainRunner cashRunner,
    required ProductiveSyncDomainRunner posRunner,
    required ProductiveSyncDomainRunner purchasesRunner,
    required ProductiveSyncDomainRunner inventoryRunner,
    required ProductiveSyncDomainRunner catalogRefreshRunner,
    required ProductiveSyncStatusLoader statusLoader,
    ProductiveDependencyProgressLoader? dependencyProgressLoader,
    void Function()? onLocalStateChanged,
  })  : _inputLoader = inputLoader,
        _contextValidator = contextValidator,
        _catalogUploadRunner = catalogUploadRunner,
        _cashRunner = cashRunner,
        _posRunner = posRunner,
        _purchasesRunner = purchasesRunner,
        _inventoryRunner = inventoryRunner,
        _catalogRefreshRunner = catalogRefreshRunner,
        _statusLoader = statusLoader,
        _dependencyProgressLoader = dependencyProgressLoader,
        _onLocalStateChanged = onLocalStateChanged;

  final ProductiveManualSyncInputLoader _inputLoader;
  final ProductiveManualSyncContextValidator _contextValidator;
  final ProductiveSyncDomainRunner _catalogUploadRunner;
  final ProductiveSyncDomainRunner _cashRunner;
  final ProductiveSyncDomainRunner _posRunner;
  final ProductiveSyncDomainRunner _purchasesRunner;
  final ProductiveSyncDomainRunner _inventoryRunner;
  final ProductiveSyncDomainRunner _catalogRefreshRunner;
  final ProductiveSyncStatusLoader _statusLoader;
  final ProductiveDependencyProgressLoader? _dependencyProgressLoader;
  final void Function()? _onLocalStateChanged;

  Future<ProductiveManualSyncResult>? _activeRun;

  Future<ProductiveManualSyncResult> run({
    ProductiveSyncTrigger trigger = ProductiveSyncTrigger.manual,
    AppSyncCoordinatorInput? inputOverride,
  }) {
    final activeRun = _activeRun;
    if (activeRun != null) return activeRun;

    final run = _run(
      trigger: trigger,
      inputOverride: inputOverride,
    );
    _activeRun = run;
    run.whenComplete(() {
      if (identical(_activeRun, run)) _activeRun = null;
    });
    return run;
  }

  Future<ProductiveManualSyncResult> _run({
    required ProductiveSyncTrigger trigger,
    required AppSyncCoordinatorInput? inputOverride,
  }) async {
    final input = inputOverride != null && _hasRequiredContext(inputOverride)
        ? inputOverride
        : await _loadValidInput();
    if (input == null) {
      return const ProductiveManualSyncResult(
        outcome: ProductiveManualSyncOutcome.unavailable,
        message:
            'Se requiere una sesión autenticada y un contexto operacional válido.',
        domainResults: _notAttemptedDomainResults,
      );
    }
    if (!input.isOnline) {
      return const ProductiveManualSyncResult(
        outcome: ProductiveManualSyncOutcome.unavailable,
        message: 'Sin conexión. Las operaciones locales siguen pendientes.',
        domainResults: _notAttemptedDomainResults,
      );
    }

    final ProductiveSyncExecutionContext context;
    try {
      final runtime = await _contextValidator(
        input.copyWithMetadata({
          'source': 'productive_sync',
          'sync_trigger': trigger.code,
        }),
      );
      context = _validatedExecutionContext(input, runtime);
    } catch (_) {
      return const ProductiveManualSyncResult(
        outcome: ProductiveManualSyncOutcome.failed,
        message:
            'No fue posible validar el contexto. Las operaciones locales se conservaron.',
        domainResults: _notAttemptedDomainResults,
      );
    }

    var results = <ProductiveSyncDomainResult>[];
    // The dependency graph is batch-scoped. Re-run the existing domain order
    // only when authoritative prerequisite results make further work eligible.
    // Eight passes bound latency even for unexpectedly deep future chains.
    try {
      for (var pass = 0; pass < 8; pass++) {
        final before = await _dependencyProgressLoader?.call(
          businessId: context.businessId,
          branchId: context.branchId,
        );
        results = [
          await _attempt(
              ProductiveSyncDomain.catalog, _catalogUploadRunner, context),
          await _attempt(ProductiveSyncDomain.cash, _cashRunner, context),
          await _attempt(ProductiveSyncDomain.pos, _posRunner, context),
          await _attempt(
              ProductiveSyncDomain.purchases, _purchasesRunner, context),
          await _attempt(
              ProductiveSyncDomain.inventory, _inventoryRunner, context),
        ];
        if (before == null || pass == 7) break;
        final after = await _dependencyProgressLoader!(
          businessId: context.businessId,
          branchId: context.branchId,
        );
        if (after.$1 <= before.$1 && after.$2 <= before.$2) break;
      }
    } catch (_) {
      return ProductiveManualSyncResult(
        outcome: ProductiveManualSyncOutcome.failed,
        message: 'No fue posible verificar el progreso del outbox.',
        domainResults: results.isEmpty ? _notAttemptedDomainResults : results,
        scope: context.scope,
      );
    }
    final refresh = await _attempt(
      ProductiveSyncDomain.catalog,
      _catalogRefreshRunner,
      context,
    );
    results[0] = results[0].merge(refresh);
    _onLocalStateChanged?.call();

    final ProductiveSyncStatus finalStatus;
    try {
      finalStatus = await _statusLoader(
        scope: context.scope,
        isOnline: true,
        isSyncing: false,
      );
    } catch (_) {
      return ProductiveManualSyncResult(
        outcome: ProductiveManualSyncOutcome.failed,
        message:
            'La sincronización terminó, pero no fue posible verificar el estado final.',
        domainResults: results,
        scope: context.scope,
      );
    }

    final finalResults = _applyFinalPendingCounts(
      finalStatus,
      results,
    );

    if (finalStatus.allUpToDate &&
        finalResults.every((result) => result.succeeded)) {
      return ProductiveManualSyncResult(
        outcome: ProductiveManualSyncOutcome.completed,
        message: 'Todo al día.',
        domainResults: finalResults,
        finalStatus: finalStatus,
        scope: context.scope,
      );
    }
    if (finalStatus.requiresAttention ||
        finalResults.any((result) => result.requiresAttention)) {
      return ProductiveManualSyncResult(
        outcome: ProductiveManualSyncOutcome.requiresAttention,
        message: 'Hay operaciones que necesitan revisión.',
        domainResults: finalResults,
        finalStatus: finalStatus,
        scope: context.scope,
      );
    }
    if (finalStatus.totalPending > 0 ||
        finalResults.any((result) => result.pending)) {
      return ProductiveManualSyncResult(
        outcome: ProductiveManualSyncOutcome.pending,
        message: 'Quedan operaciones pendientes de sincronización.',
        domainResults: finalResults,
        finalStatus: finalStatus,
        scope: context.scope,
      );
    }
    return ProductiveManualSyncResult(
      outcome: ProductiveManualSyncOutcome.failed,
      message: 'No fue posible completar la sincronización.',
      domainResults: finalResults,
      finalStatus: finalStatus,
      scope: context.scope,
    );
  }

  Future<AppSyncCoordinatorInput?> _loadValidInput() async {
    try {
      final input = await _inputLoader();
      if (input == null || !_hasRequiredContext(input)) return null;
      return input;
    } catch (_) {
      return null;
    }
  }

  ProductiveSyncExecutionContext _validatedExecutionContext(
    AppSyncCoordinatorInput input,
    AppRuntimeContext runtime,
  ) {
    final profileId = input.profileId!.trim();
    final branchId = input.branchId!.trim();
    if (runtime.businessId != input.businessId ||
        runtime.branchId != branchId ||
        runtime.profileId != profileId ||
        runtime.installationId != input.installationId ||
        runtime.appDeviceId.trim().isEmpty) {
      throw StateError('El runtime no coincide con el scope solicitado.');
    }
    return ProductiveSyncExecutionContext(
      profileId: profileId,
      businessId: input.businessId,
      branchId: branchId,
      installationId: input.installationId,
      appDeviceId: runtime.appDeviceId,
    );
  }

  Future<ProductiveSyncDomainResult> _attempt(
    ProductiveSyncDomain domain,
    ProductiveSyncDomainRunner runner,
    ProductiveSyncExecutionContext context,
  ) async {
    try {
      final result = await runner(context);
      if (result.domain != domain) {
        throw StateError('El runner devolvió un dominio distinto.');
      }
      return result;
    } catch (_) {
      return ProductiveSyncDomainResult.failedRetryable(domain);
    }
  }

  List<ProductiveSyncDomainResult> _applyFinalPendingCounts(
    ProductiveSyncStatus status,
    List<ProductiveSyncDomainResult> results,
  ) {
    return results.map((result) {
      final remainsPending = switch (result.domain) {
        ProductiveSyncDomain.catalog => status.pendingProductOperations > 0,
        ProductiveSyncDomain.cash => status.pendingCashOperations > 0,
        ProductiveSyncDomain.pos => status.pendingSales > 0,
        ProductiveSyncDomain.purchases => status.pendingPurchases > 0,
        ProductiveSyncDomain.inventory => status.pendingInventoryOperations > 0,
      };
      return result.withPending(remainsPending);
    }).toList(growable: false);
  }

  bool _hasRequiredContext(AppSyncCoordinatorInput input) {
    return input.businessId.trim().isNotEmpty &&
        input.branchId?.trim().isNotEmpty == true &&
        input.profileId?.trim().isNotEmpty == true &&
        input.installationId.trim().isNotEmpty;
  }
}
