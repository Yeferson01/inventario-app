import '../../sales/data/datasources/pos_local_sale_dao.dart';
import '../data/datasources/pos_sync_remote_datasource.dart';

typedef UnmaterializedSaleRemoteVerifier
    = Future<UnmaterializedSaleRemoteEvidence> Function({
  required String businessId,
  required String branchId,
  required String saleId,
});

enum UnmaterializedSaleDiscardFailureKind {
  confirmationRequired,
  invalidInput,
  remoteUnavailable,
  remoteMaterializationFound,
  expectedConflictMissing,
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
    required this.saleId,
    required this.confirmedSaleDidNotOccur,
    required this.reason,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String saleId;
  final bool confirmedSaleDidNotOccur;
  final String reason;
}

class DiscardUnmaterializedLocalSaleResult {
  const DiscardUnmaterializedLocalSaleResult({
    required this.remoteEvidence,
    required this.localResult,
  });

  final UnmaterializedSaleRemoteEvidence remoteEvidence;
  final DiscardUnmaterializedLocalSaleLocalResult localResult;

  Map<String, dynamic> toJson() => {
        'remote_evidence': remoteEvidence.toJson(),
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
  })  : _localDao = localDao,
        _remoteVerifier = remoteVerifier;

  final PosLocalSaleDao _localDao;
  final UnmaterializedSaleRemoteVerifier _remoteVerifier;

  Future<DiscardUnmaterializedLocalSaleResult> discard(
    DiscardUnmaterializedLocalSaleInput input,
  ) async {
    if (!input.confirmedSaleDidNotOccur) {
      throw const UnmaterializedSaleDiscardException(
        kind: UnmaterializedSaleDiscardFailureKind.confirmationRequired,
        message: 'Debe confirmarse explícitamente que la venta nunca ocurrió.',
      );
    }
    if ([input.profileId, input.businessId, input.branchId, input.saleId]
            .any((value) => value.trim().isEmpty) ||
        input.reason.trim().isEmpty) {
      throw const UnmaterializedSaleDiscardException(
        kind: UnmaterializedSaleDiscardFailureKind.invalidInput,
        message: 'El contexto, saleId y motivo de descarte son requeridos.',
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

    try {
      final localResult = await _localDao.discardUnmaterializedLocalSale(
        profileId: input.profileId,
        businessId: input.businessId,
        branchId: input.branchId,
        saleId: input.saleId,
        reason: input.reason.trim(),
      );
      return DiscardUnmaterializedLocalSaleResult(
        remoteEvidence: evidence,
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
