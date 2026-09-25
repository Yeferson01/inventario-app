enum InventoryAdjustmentReason {
  expired,
  damaged,
  lost,
  theft,
  gift,
  internalConsumption,
  manualCorrection,
  other;

  String get code => switch (this) {
        internalConsumption => 'internal_consumption',
        manualCorrection => 'manual_correction',
        _ => name,
      };
  bool get isLoss => this != manualCorrection && this != other;
  String get sourceType => isLoss ? 'loss' : 'manual_adjustment';
}

enum InventoryAdjustmentFailure {
  invalidRequest,
  invalidContext,
  permissionDenied,
  invalidProduct,
  insufficientStock,
  reservedStockConflict,
  invalidBalance,
  idempotencyConflict,
}

class InventoryAdjustmentException implements Exception {
  const InventoryAdjustmentException(this.kind);
  final InventoryAdjustmentFailure kind;
  @override
  String toString() => 'InventoryAdjustmentException(${kind.name})';
}

/// The scope is an expectation, not caller-supplied authorization.
class InventoryAdjustmentRequest {
  const InventoryAdjustmentRequest.loss({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.productId,
    required this.reason,
    required int quantity,
    required this.idempotencyKey,
    this.note,
    this.occurredAt,
  })  : quantityOrDelta = quantity,
        isLossRequest = true;

  const InventoryAdjustmentRequest.correction({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.productId,
    required this.reason,
    required int delta,
    required this.idempotencyKey,
    this.note,
    this.occurredAt,
  })  : quantityOrDelta = delta,
        isLossRequest = false;

  final String profileId, businessId, branchId, productId, idempotencyKey;
  final InventoryAdjustmentReason reason;
  final int quantityOrDelta;
  final bool isLossRequest;
  final String? note;
  final DateTime? occurredAt;
  int get delta => isLossRequest ? -quantityOrDelta : quantityOrDelta;

  void validate() {
    if ([profileId, businessId, branchId, productId, idempotencyKey]
            .any((v) => v.isEmpty || v.trim() != v) ||
        idempotencyKey.length > 512 ||
        reason.isLoss != isLossRequest ||
        (isLossRequest && quantityOrDelta <= 0) ||
        delta == 0 ||
        delta < -2147483648 ||
        delta > 2147483647) {
      throw const InventoryAdjustmentException(
          InventoryAdjustmentFailure.invalidRequest);
    }
  }
}

class InventoryAdjustmentResult {
  const InventoryAdjustmentResult(
      {required this.movementId,
      required this.previousOnHand,
      required this.resultingOnHand,
      required this.unitCost,
      required this.alreadyApplied});
  final String movementId;

  /// Values at the original operation, not a fresh balance on retry.
  final int previousOnHand, resultingOnHand;
  final double? unitCost;
  final bool alreadyApplied;
}
