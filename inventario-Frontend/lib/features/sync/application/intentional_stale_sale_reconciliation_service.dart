import '../../sales/data/datasources/pos_local_sale_dao.dart';
import '../data/datasources/pos_sync_remote_datasource.dart';

enum IntentionalStaleSaleCashTreatment {
  notIncludedInDestinationOpening(
    'not_included_in_destination_opening',
  ),
  alreadyIncludedInDestinationOpening(
    'already_included_in_destination_opening',
  );

  const IntentionalStaleSaleCashTreatment(this.wireValue);

  final String wireValue;
}

enum IntentionalStaleSaleReconciliationFailureKind {
  confirmationRequired,
  invalidInput,
  remoteRejected,
  localProjectionFailed,
  postReconciliationRefreshFailed,
}

class IntentionalStaleSaleReconciliationException implements Exception {
  const IntentionalStaleSaleReconciliationException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final IntentionalStaleSaleReconciliationFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final detail = cause == null ? '' : ' Cause: $cause';
    return 'IntentionalStaleSaleReconciliationException: $message$detail';
  }
}

class IntentionalStaleSaleReconciliationInput {
  const IntentionalStaleSaleReconciliationInput({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.appDeviceId,
    required this.saleId,
    required this.syncConflictId,
    required this.destinationCashSessionId,
    required this.reconciliationId,
    required this.idempotencyKey,
    required this.reason,
    required this.cashTreatment,
    required this.confirmedSaleDidOccur,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String appDeviceId;
  final String saleId;
  final String syncConflictId;
  final String destinationCashSessionId;
  final String reconciliationId;
  final String idempotencyKey;
  final String reason;
  final IntentionalStaleSaleCashTreatment cashTreatment;
  final bool confirmedSaleDidOccur;
}

typedef IntentionalStaleSaleRemoteExecutor
    = Future<IntentionalStaleSaleRemoteResult> Function({
  required String businessId,
  required String branchId,
  required String appDeviceId,
  required String saleId,
  required String syncConflictId,
  required String destinationCashSessionId,
  required String reconciliationId,
  required String idempotencyKey,
  required String reason,
  required String cashTreatment,
});

typedef IntentionalStaleSaleLocalProjector
    = Future<IntentionalStaleSaleLocalProjectionResult> Function({
  required String profileId,
  required String businessId,
  required String branchId,
  required String saleId,
  required String destinationCashSessionId,
  required String reconciliationId,
  required String cashTreatment,
  required String reason,
});

typedef IntentionalStaleSaleLocalPreviewLoader
    = Future<IntentionalStaleSaleLocalPreview> Function({
  required String businessId,
  required String branchId,
  required String saleId,
  required String destinationCashSessionId,
});

typedef IntentionalStaleSaleScopedRefresher = Future<void> Function(
  IntentionalStaleSaleReconciliationInput input,
  IntentionalStaleSaleRemoteResult remote,
);

class IntentionalStaleSaleReconciliationResult {
  const IntentionalStaleSaleReconciliationResult({
    required this.remote,
    required this.local,
    required this.inventoryRefreshed,
    required this.cashRefreshed,
  });

  final IntentionalStaleSaleRemoteResult remote;
  final IntentionalStaleSaleLocalProjectionResult local;
  final bool inventoryRefreshed;
  final bool cashRefreshed;

  Map<String, dynamic> toJson() => {
        'remote': remote.toJson(),
        'local': {
          'sale_id': local.saleId,
          'already_projected': local.alreadyProjected,
          'movements_acknowledged': local.movementsAcknowledged,
          'mutations_superseded': local.mutationsSuperseded,
          'issues_resolved': local.issuesResolved,
          'stock_before': local.stockByProductBefore,
          'stock_after': local.stockByProductAfter,
        },
        'inventory_refreshed': inventoryRefreshed,
        'cash_refreshed': cashRefreshed,
      };
}

class IntentionalStaleSaleReconciliationPreview {
  const IntentionalStaleSaleReconciliationPreview({
    required this.local,
    required this.cashTreatment,
    required this.expectedAdjustment,
    required this.projectedExpectedCash,
  });

  final IntentionalStaleSaleLocalPreview local;
  final IntentionalStaleSaleCashTreatment cashTreatment;
  final double expectedAdjustment;
  final double projectedExpectedCash;
}

class IntentionalStaleSaleReconciliationService {
  IntentionalStaleSaleReconciliationService({
    required IntentionalStaleSaleRemoteExecutor remoteExecutor,
    required IntentionalStaleSaleLocalProjector localProjector,
    required IntentionalStaleSaleLocalPreviewLoader localPreviewLoader,
    required IntentionalStaleSaleScopedRefresher inventoryRefresher,
    required IntentionalStaleSaleScopedRefresher cashRefresher,
  })  : _remoteExecutor = remoteExecutor,
        _localProjector = localProjector,
        _localPreviewLoader = localPreviewLoader,
        _inventoryRefresher = inventoryRefresher,
        _cashRefresher = cashRefresher;

  final IntentionalStaleSaleRemoteExecutor _remoteExecutor;
  final IntentionalStaleSaleLocalProjector _localProjector;
  final IntentionalStaleSaleLocalPreviewLoader _localPreviewLoader;
  final IntentionalStaleSaleScopedRefresher _inventoryRefresher;
  final IntentionalStaleSaleScopedRefresher _cashRefresher;

  Future<IntentionalStaleSaleReconciliationPreview> preview({
    required String businessId,
    required String branchId,
    required String saleId,
    required String destinationCashSessionId,
    required IntentionalStaleSaleCashTreatment cashTreatment,
  }) async {
    final local = await _localPreviewLoader(
      businessId: businessId,
      branchId: branchId,
      saleId: saleId,
      destinationCashSessionId: destinationCashSessionId,
    );
    final adjustment = cashTreatment ==
            IntentionalStaleSaleCashTreatment
                .alreadyIncludedInDestinationOpening
        ? -local.cashTotal
        : 0.0;
    return IntentionalStaleSaleReconciliationPreview(
      local: local,
      cashTreatment: cashTreatment,
      expectedAdjustment: adjustment,
      projectedExpectedCash: local.destinationOpeningAmount +
          local.destinationCurrentCashPayments +
          local.cashTotal +
          adjustment,
    );
  }

  Future<IntentionalStaleSaleReconciliationResult> reconcile(
    IntentionalStaleSaleReconciliationInput input,
  ) async {
    if (!input.confirmedSaleDidOccur) {
      throw const IntentionalStaleSaleReconciliationException(
        kind:
            IntentionalStaleSaleReconciliationFailureKind.confirmationRequired,
        message: 'Debe confirmarse explícitamente que la venta sí ocurrió.',
      );
    }
    if ([
      input.profileId,
      input.businessId,
      input.branchId,
      input.appDeviceId,
      input.saleId,
      input.syncConflictId,
      input.destinationCashSessionId,
      input.reconciliationId,
      input.idempotencyKey,
      input.reason,
    ].any((value) => value.trim().isEmpty)) {
      throw const IntentionalStaleSaleReconciliationException(
        kind: IntentionalStaleSaleReconciliationFailureKind.invalidInput,
        message: 'El contexto, las identidades y el motivo son requeridos.',
      );
    }

    late final IntentionalStaleSaleRemoteResult remote;
    try {
      remote = await _remoteExecutor(
        businessId: input.businessId,
        branchId: input.branchId,
        appDeviceId: input.appDeviceId,
        saleId: input.saleId,
        syncConflictId: input.syncConflictId,
        destinationCashSessionId: input.destinationCashSessionId,
        reconciliationId: input.reconciliationId,
        idempotencyKey: input.idempotencyKey,
        reason: input.reason.trim(),
        cashTreatment: input.cashTreatment.wireValue,
      );
    } catch (error) {
      throw IntentionalStaleSaleReconciliationException(
        kind: IntentionalStaleSaleReconciliationFailureKind.remoteRejected,
        message: 'Hosted rechazó o no pudo completar la reconciliación.',
        cause: error,
      );
    }

    late final IntentionalStaleSaleLocalProjectionResult local;
    try {
      local = await _localProjector(
        profileId: input.profileId,
        businessId: input.businessId,
        branchId: input.branchId,
        saleId: input.saleId,
        destinationCashSessionId: input.destinationCashSessionId,
        reconciliationId: input.reconciliationId,
        cashTreatment: input.cashTreatment.wireValue,
        reason: input.reason.trim(),
      );
    } catch (error) {
      throw IntentionalStaleSaleReconciliationException(
        kind:
            IntentionalStaleSaleReconciliationFailureKind.localProjectionFailed,
        message:
            'Hosted completó la reconciliación, pero Drift no pudo proyectarla.',
        cause: error,
      );
    }

    try {
      await _inventoryRefresher(input, remote);
      await _cashRefresher(input, remote);
    } catch (error) {
      throw IntentionalStaleSaleReconciliationException(
        kind: IntentionalStaleSaleReconciliationFailureKind
            .postReconciliationRefreshFailed,
        message:
            'La reconciliación quedó aplicada, pero el refresh local debe reintentarse.',
        cause: error,
      );
    }

    return IntentionalStaleSaleReconciliationResult(
      remote: remote,
      local: local,
      inventoryRefreshed: true,
      cashRefreshed: true,
    );
  }
}
