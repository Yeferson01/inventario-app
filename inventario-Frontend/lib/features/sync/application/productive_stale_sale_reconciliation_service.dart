import '../../cash/data/datasources/cash_session_local_dao.dart';
import '../../sales/data/datasources/pos_local_sale_dao.dart';
import 'intentional_stale_sale_reconciliation_service.dart';
import 'unmaterialized_local_sale_discard_service.dart';

export '../../sales/data/datasources/pos_local_sale_dao.dart'
    show
        StaleSaleItemSummary,
        StaleSalePaymentSummary,
        StaleSaleResolutionCandidate;

enum ProductiveStaleSaleFailureKind {
  permissionDenied,
  destinationRequired,
  conflictUnavailable,
}

class ProductiveStaleSaleException implements Exception {
  const ProductiveStaleSaleException(this.kind, this.message);

  final ProductiveStaleSaleFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

typedef StaleSaleConflictIdResolver = Future<String?> Function({
  required String businessId,
  required String branchId,
  required String appDeviceId,
  required String saleId,
});

typedef StaleSalePostDiscardRefresher = Future<void> Function({
  required String profileId,
  required String appDeviceId,
  required StaleSaleResolutionCandidate candidate,
});

({String reconciliationId, String idempotencyKey})
    buildStaleSaleReconciliationIdentity(String saleId) {
  final normalizedSaleId = saleId.trim();
  return (
    reconciliationId: normalizedSaleId,
    idempotencyKey: 'stale-sale-reconciliation:$normalizedSaleId',
  );
}

abstract class ProductiveStaleSaleReconciliationController {
  Future<List<StaleSaleResolutionCandidate>> loadPending({
    required String profileId,
    required String businessId,
    required String branchId,
  });

  Future<String?> resolveOpenDestination(
    StaleSaleResolutionCandidate candidate,
  );

  Future<IntentionalStaleSaleReconciliationPreview> previewOccurred({
    required StaleSaleResolutionCandidate candidate,
    required String destinationCashSessionId,
    required IntentionalStaleSaleCashTreatment cashTreatment,
  });

  Future<DiscardUnmaterializedLocalSaleResult> discardDidNotOccur({
    required String profileId,
    required String appDeviceId,
    required StaleSaleResolutionCandidate candidate,
  });

  Future<IntentionalStaleSaleReconciliationResult> reconcileDidOccur({
    required String profileId,
    required String appDeviceId,
    required Set<String> effectivePermissions,
    required StaleSaleResolutionCandidate candidate,
    required String destinationCashSessionId,
    required IntentionalStaleSaleCashTreatment cashTreatment,
  });
}

class ProductiveStaleSaleReconciliationService
    implements ProductiveStaleSaleReconciliationController {
  ProductiveStaleSaleReconciliationService({
    required PosLocalSaleDao saleDao,
    required CashSessionLocalDao cashDao,
    required UnmaterializedLocalSaleDiscardService discardService,
    required IntentionalStaleSaleReconciliationService reconciliationService,
    required StaleSaleConflictIdResolver conflictIdResolver,
    required StaleSalePostDiscardRefresher postDiscardRefresher,
  })  : _saleDao = saleDao,
        _cashDao = cashDao,
        _discardService = discardService,
        _reconciliationService = reconciliationService,
        _conflictIdResolver = conflictIdResolver,
        _postDiscardRefresher = postDiscardRefresher;

  final PosLocalSaleDao _saleDao;
  final CashSessionLocalDao _cashDao;
  final UnmaterializedLocalSaleDiscardService _discardService;
  final IntentionalStaleSaleReconciliationService _reconciliationService;
  final StaleSaleConflictIdResolver _conflictIdResolver;
  final StaleSalePostDiscardRefresher _postDiscardRefresher;

  @override
  Future<List<StaleSaleResolutionCandidate>> loadPending({
    required String profileId,
    required String businessId,
    required String branchId,
  }) {
    return _saleDao.loadPendingStaleCashSessionSales(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
    );
  }

  @override
  Future<String?> resolveOpenDestination(
    StaleSaleResolutionCandidate candidate,
  ) async {
    final row = await _cashDao.getOpenCashSessionForRegister(
      businessId: candidate.businessId,
      branchId: candidate.branchId,
      cashRegisterId: candidate.cashRegisterId,
    );
    final id = row?['id']?.toString().trim();
    if (id == null ||
        id.isEmpty ||
        id == candidate.originalCashSessionId ||
        row?['business_id']?.toString() != candidate.businessId ||
        row?['branch_id']?.toString() != candidate.branchId ||
        row?['cash_register_id']?.toString() != candidate.cashRegisterId ||
        row?['status']?.toString() != 'open' ||
        row?['deleted_at'] != null) {
      return null;
    }
    return id;
  }

  @override
  Future<IntentionalStaleSaleReconciliationPreview> previewOccurred({
    required StaleSaleResolutionCandidate candidate,
    required String destinationCashSessionId,
    required IntentionalStaleSaleCashTreatment cashTreatment,
  }) {
    return _reconciliationService.preview(
      businessId: candidate.businessId,
      branchId: candidate.branchId,
      saleId: candidate.saleId,
      destinationCashSessionId: destinationCashSessionId,
      cashTreatment: cashTreatment,
    );
  }

  @override
  Future<DiscardUnmaterializedLocalSaleResult> discardDidNotOccur({
    required String profileId,
    required String appDeviceId,
    required StaleSaleResolutionCandidate candidate,
  }) async {
    final conflictId = candidate.syncConflictId?.trim().isNotEmpty == true
        ? candidate.syncConflictId!.trim()
        : await _conflictIdResolver(
            businessId: candidate.businessId,
            branchId: candidate.branchId,
            appDeviceId: appDeviceId,
            saleId: candidate.saleId,
          );
    if (conflictId == null || conflictId.trim().isEmpty) {
      throw const ProductiveStaleSaleException(
        ProductiveStaleSaleFailureKind.conflictUnavailable,
        'No se pudo verificar el rechazo original en el servidor.',
      );
    }
    final idempotencyKey =
        'sale-did-not-occur:${candidate.saleId}:${conflictId.trim()}';
    final result = await _discardService.discard(
      DiscardUnmaterializedLocalSaleInput(
        profileId: profileId,
        businessId: candidate.businessId,
        branchId: candidate.branchId,
        appDeviceId: appDeviceId,
        saleId: candidate.saleId,
        syncConflictId: conflictId.trim(),
        idempotencyKey: idempotencyKey,
        confirmedSaleDidNotOccur: true,
        reason:
            'El usuario confirmó que no recibió dinero ni entregó productos.',
      ),
    );
    await _postDiscardRefresher(
      profileId: profileId,
      appDeviceId: appDeviceId,
      candidate: candidate,
    );
    return result;
  }

  @override
  Future<IntentionalStaleSaleReconciliationResult> reconcileDidOccur({
    required String profileId,
    required String appDeviceId,
    required Set<String> effectivePermissions,
    required StaleSaleResolutionCandidate candidate,
    required String destinationCashSessionId,
    required IntentionalStaleSaleCashTreatment cashTreatment,
  }) async {
    if (!effectivePermissions.contains('sales.reconcile_stale_cash_session') ||
        !effectivePermissions.contains('sales.create')) {
      throw const ProductiveStaleSaleException(
        ProductiveStaleSaleFailureKind.permissionDenied,
        'No tiene permiso para reconciliar esta venta.',
      );
    }
    if (destinationCashSessionId.trim().isEmpty) {
      throw const ProductiveStaleSaleException(
        ProductiveStaleSaleFailureKind.destinationRequired,
        'Debe abrir una caja antes de reconciliar esta venta.',
      );
    }
    final conflictId = candidate.syncConflictId?.trim().isNotEmpty == true
        ? candidate.syncConflictId!.trim()
        : await _conflictIdResolver(
            businessId: candidate.businessId,
            branchId: candidate.branchId,
            appDeviceId: appDeviceId,
            saleId: candidate.saleId,
          );
    if (conflictId == null || conflictId.trim().isEmpty) {
      throw const ProductiveStaleSaleException(
        ProductiveStaleSaleFailureKind.conflictUnavailable,
        'No se pudo verificar el rechazo original en el servidor.',
      );
    }
    final identity = buildStaleSaleReconciliationIdentity(candidate.saleId);
    return _reconciliationService.reconcile(
      IntentionalStaleSaleReconciliationInput(
        profileId: profileId,
        businessId: candidate.businessId,
        branchId: candidate.branchId,
        appDeviceId: appDeviceId,
        saleId: candidate.saleId,
        syncConflictId: conflictId,
        destinationCashSessionId: destinationCashSessionId,
        reconciliationId: identity.reconciliationId,
        idempotencyKey: identity.idempotencyKey,
        reason: 'El usuario confirmó que la venta ocurrió realmente.',
        cashTreatment: cashTreatment,
        confirmedSaleDidOccur: true,
      ),
    );
  }
}
