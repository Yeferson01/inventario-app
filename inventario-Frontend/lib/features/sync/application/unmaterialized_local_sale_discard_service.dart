import '../../sales/data/datasources/pos_local_sale_dao.dart';
import '../data/datasources/pos_sync_remote_datasource.dart';

typedef UnmaterializedSaleRemoteVerifier
    = Future<UnmaterializedSaleRemoteEvidence> Function({
  required String businessId,
  required String branchId,
  required String saleId,
});

typedef UnmaterializedSaleRemoteFinalizer = Future<SaleDidNotOccurRemoteResult>
    Function({
  required String businessId,
  required String branchId,
  required String appDeviceId,
  required String saleId,
  required String syncConflictId,
  required String idempotencyKey,
  required String reason,
});

enum UnmaterializedSaleDiscardFailureKind {
  confirmationRequired,
  invalidInput,
  remoteUnavailable,
  remoteMaterializationFound,
  expectedConflictMissing,
  remoteFinalizationFailed,
  localValidationFailed,
}

class UnmaterializedSaleDiscardException implements Exception {
  const UnmaterializedSaleDiscardException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final UnmaterializedSaleDiscardFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() {
    final detail = cause == null ? '' : ' Cause: $cause';
    return 'UnmaterializedSaleDiscardException: $message$detail';
  }
}

class DiscardUnmaterializedLocalSaleInput {
  const DiscardUnmaterializedLocalSaleInput({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.appDeviceId,
    required this.saleId,
    required this.syncConflictId,
    required this.idempotencyKey,
    required this.confirmedSaleDidNotOccur,
    required this.reason,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String appDeviceId;
  final String saleId;
  final String syncConflictId;
  final String idempotencyKey;
  final bool confirmedSaleDidNotOccur;
  final String reason;
}

class DiscardUnmaterializedLocalSaleResult {
  const DiscardUnmaterializedLocalSaleResult({
    required this.remoteEvidence,
    required this.remoteFinalization,
    required this.localResult,
  });

  final UnmaterializedSaleRemoteEvidence remoteEvidence;
  final SaleDidNotOccurRemoteResult remoteFinalization;
  final DiscardUnmaterializedLocalSaleLocalResult localResult;

  Map<String, dynamic> toJson() => {
        'remote_evidence': remoteEvidence.toJson(),
        'remote_finalization': remoteFinalization.toJson(),
        'sale_id': localResult.saleId,
        'already_discarded': localResult.alreadyDiscarded,
        'movements_discarded': localResult.movementsDiscarded,
        'mutations_terminalized': localResult.mutationsTerminalized,
        'issues_resolved': localResult.issuesResolved,
        'restored_quantity_by_product': localResult.restoredQuantityByProduct,
      };
}

class UnmaterializedLocalSaleDiscardService {
  UnmaterializedLocalSaleDiscardService({
    required PosLocalSaleDao localDao,
    required UnmaterializedSaleRemoteVerifier remoteVerifier,
    required UnmaterializedSaleRemoteFinalizer remoteFinalizer,
  })  : _localDao = localDao,
        _remoteVerifier = remoteVerifier,
        _remoteFinalizer = remoteFinalizer;

  final PosLocalSaleDao _localDao;
  final UnmaterializedSaleRemoteVerifier _remoteVerifier;
  final UnmaterializedSaleRemoteFinalizer _remoteFinalizer;

  Future<DiscardUnmaterializedLocalSaleResult> discard(
    DiscardUnmaterializedLocalSaleInput input,
  ) async {
    if (!input.confirmedSaleDidNotOccur) {
      throw const UnmaterializedSaleDiscardException(
        kind: UnmaterializedSaleDiscardFailureKind.confirmationRequired,
        message: 'Debe confirmarse explícitamente que la venta nunca ocurrió.',
      );
    }
    if ([
          input.profileId,
          input.businessId,
          input.branchId,
          input.appDeviceId,
          input.saleId,
          input.syncConflictId,
          input.idempotencyKey,
        ].any((value) => value.trim().isEmpty) ||
        input.reason.trim().isEmpty) {
      throw const UnmaterializedSaleDiscardException(
        kind: UnmaterializedSaleDiscardFailureKind.invalidInput,
        message:
            'El contexto, device, conflict, idempotency, saleId y motivo son requeridos.',
      );
    }

    late final UnmaterializedSaleRemoteEvidence evidence;
    try {
      evidence = await _remoteVerifier(
        businessId: input.businessId,
        branchId: input.branchId,
        saleId: input.saleId,
      );
    } catch (error) {
      throw UnmaterializedSaleDiscardException(
        kind: UnmaterializedSaleDiscardFailureKind.remoteUnavailable,
        message:
            'No se pudo demostrar server-side que la venta no fue materializada.',
        cause: error,
      );
    }
    if (evidence.businessId != input.businessId ||
        evidence.branchId != input.branchId ||
        evidence.saleId != input.saleId) {
      throw const UnmaterializedSaleDiscardException(
        kind: UnmaterializedSaleDiscardFailureKind.remoteUnavailable,
        message: 'La evidencia remota no coincide con el contexto solicitado.',
      );
    }
    if (evidence.hasRemoteMaterialization) {
      throw const UnmaterializedSaleDiscardException(
        kind: UnmaterializedSaleDiscardFailureKind.remoteMaterializationFound,
        message:
            'Existe evidencia remota de la venta, sus hijos o su inventario.',
      );
    }
    if (!evidence.expectedConflictFound) {
      throw const UnmaterializedSaleDiscardException(
        kind: UnmaterializedSaleDiscardFailureKind.expectedConflictMissing,
        message:
            'No existe el rechazo remoto sale_cash_session_invalid esperado.',
      );
    }

    late final SaleDidNotOccurRemoteResult finalization;
    try {
      finalization = await _remoteFinalizer(
        businessId: input.businessId,
        branchId: input.branchId,
        appDeviceId: input.appDeviceId,
        saleId: input.saleId,
        syncConflictId: input.syncConflictId,
        idempotencyKey: input.idempotencyKey,
        reason: input.reason.trim(),
      );
    } catch (error) {
      throw UnmaterializedSaleDiscardException(
        kind: UnmaterializedSaleDiscardFailureKind.remoteFinalizationFailed,
        message: 'El servidor no pudo finalizar autoritativamente el descarte.',
        cause: error,
      );
    }
    if (finalization.businessId != input.businessId ||
        finalization.branchId != input.branchId ||
        finalization.saleId != input.saleId ||
        finalization.syncConflictId != input.syncConflictId ||
        finalization.idempotencyKey != input.idempotencyKey ||
        finalization.status != 'resolved' ||
        finalization.resolutionStrategy != 'sale_did_not_occur') {
      throw const UnmaterializedSaleDiscardException(
        kind: UnmaterializedSaleDiscardFailureKind.remoteFinalizationFailed,
        message:
            'La finalización remota no coincide con el descarte solicitado.',
      );
    }

    try {
      final localResult = await _localDao.discardUnmaterializedLocalSale(
        profileId: input.profileId,
        businessId: input.businessId,
        branchId: input.branchId,
        saleId: input.saleId,
        reason: input.reason.trim(),
        syncConflictId: input.syncConflictId,
        discardIdempotencyKey: input.idempotencyKey,
        confirmedAppDeviceId: input.appDeviceId,
      );
      return DiscardUnmaterializedLocalSaleResult(
        remoteEvidence: evidence,
        remoteFinalization: finalization,
        localResult: localResult,
      );
    } catch (error) {
      throw UnmaterializedSaleDiscardException(
        kind: UnmaterializedSaleDiscardFailureKind.localValidationFailed,
        message: 'La validación o transacción local rechazó el descarte.',
        cause: error,
      );
    }
  }
}
