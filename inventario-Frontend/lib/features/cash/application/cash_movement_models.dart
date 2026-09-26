enum CashMovementDirection { inflow, outflow }

enum CashMovementFailure {
  invalidRequest,
  invalidContext,
  permissionDenied,
  invalidSession,
  insufficientCash,
  idempotencyConflict,
}

class CashMovementException implements Exception {
  const CashMovementException(this.kind);

  final CashMovementFailure kind;

  @override
  String toString() => 'CashMovementException(${kind.name})';
}

class CashMovementRequest {
  const CashMovementRequest({
    required this.profileId,
    required this.businessId,
    required this.branchId,
    required this.cashRegisterId,
    required this.cashSessionId,
    required this.direction,
    required this.category,
    required this.amountCents,
    required this.idempotencyKey,
    this.currency = 'COP',
    this.sourceType = 'manual',
    this.sourceId,
    this.note,
    this.occurredAt,
  });

  final String profileId;
  final String businessId;
  final String branchId;
  final String cashRegisterId;
  final String cashSessionId;
  final CashMovementDirection direction;
  final String category;
  final BigInt amountCents;
  final String idempotencyKey;
  final String currency;
  final String sourceType;
  final String? sourceId;
  final String? note;
  final DateTime? occurredAt;

  static const categories = <String>{
    'supplier_purchase',
    'payroll',
    'utilities',
    'rent',
    'maintenance',
    'repairs',
    'transport',
    'infrastructure',
    'cleaning',
    'office_supplies',
    'owner_withdrawal',
    'owner_contribution',
    'other_income',
    'other',
  };
  static const inflowOnly = <String>{'owner_contribution', 'other_income'};
  static const outflowOnly = <String>{
    'supplier_purchase',
    'payroll',
    'utilities',
    'rent',
    'maintenance',
    'repairs',
    'transport',
    'infrastructure',
    'cleaning',
    'office_supplies',
    'owner_withdrawal',
  };

  void validate() {
    if (<String>[
          profileId,
          businessId,
          branchId,
          cashRegisterId,
          cashSessionId,
          idempotencyKey,
          currency,
          sourceType,
        ].any((value) => value.isEmpty || value.trim() != value) ||
        idempotencyKey.length > 512 ||
        amountCents <= BigInt.zero ||
        amountCents > BigInt.from(99999999999999) ||
        !categories.contains(category) ||
        (direction == CashMovementDirection.inflow &&
            outflowOnly.contains(category)) ||
        (direction == CashMovementDirection.outflow &&
            inflowOnly.contains(category)) ||
        (sourceType == 'purchase' && sourceId == null) ||
        (sourceType == 'manual' && sourceId != null)) {
      throw const CashMovementException(CashMovementFailure.invalidRequest);
    }
  }
}

class CashMovementResult {
  const CashMovementResult({required this.id, required this.alreadyRecorded});
  final String id;
  final bool alreadyRecorded;
}
