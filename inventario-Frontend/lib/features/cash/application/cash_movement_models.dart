enum CashMovementDirection { inflow, outflow }

/// Cash classification, not accrual accounting or a purchase payment record.
/// Supplier purchases acquire inventory; subtracting them from gross profit
/// would count the same cost again after COGS is recognized on sale.
enum CashMovementFinancialClass {
  inventoryAcquisition,
  operatingExpense,
  ownerMovement,
  otherCashMovement,
}

class CashMovementCategoryMetadata {
  const CashMovementCategoryMetadata({
    required this.code,
    required this.displayLabel,
    required this.directions,
    required this.financialClass,
  });

  final String code;
  final String displayLabel;
  final Set<CashMovementDirection> directions;
  final CashMovementFinancialClass financialClass;

  bool supports(CashMovementDirection direction) =>
      directions.contains(direction);
  bool get countsAsOperatingExpense =>
      financialClass == CashMovementFinancialClass.operatingExpense;
  bool get countsAsInventoryAcquisition =>
      financialClass == CashMovementFinancialClass.inventoryAcquisition;
  bool get countsAsOwnerMovement =>
      financialClass == CashMovementFinancialClass.ownerMovement;
  bool countsAsOtherCashOutflow(CashMovementDirection direction) =>
      direction == CashMovementDirection.outflow &&
      supports(direction) &&
      financialClass == CashMovementFinancialClass.otherCashMovement;

  static const byCode = <String, CashMovementCategoryMetadata>{
    'supplier_purchase': CashMovementCategoryMetadata(
      code: 'supplier_purchase',
      displayLabel: 'Compra a proveedor',
      directions: {CashMovementDirection.outflow},
      financialClass: CashMovementFinancialClass.inventoryAcquisition,
    ),
    'payroll': CashMovementCategoryMetadata(
      code: 'payroll',
      displayLabel: 'Nómina',
      directions: {CashMovementDirection.outflow},
      financialClass: CashMovementFinancialClass.operatingExpense,
    ),
    'utilities': CashMovementCategoryMetadata(
      code: 'utilities',
      displayLabel: 'Servicios públicos',
      directions: {CashMovementDirection.outflow},
      financialClass: CashMovementFinancialClass.operatingExpense,
    ),
    'rent': CashMovementCategoryMetadata(
      code: 'rent',
      displayLabel: 'Arriendo',
      directions: {CashMovementDirection.outflow},
      financialClass: CashMovementFinancialClass.operatingExpense,
    ),
    'maintenance': CashMovementCategoryMetadata(
      code: 'maintenance',
      displayLabel: 'Mantenimiento',
      directions: {CashMovementDirection.outflow},
      financialClass: CashMovementFinancialClass.operatingExpense,
    ),
    'repairs': CashMovementCategoryMetadata(
      code: 'repairs',
      displayLabel: 'Reparaciones',
      directions: {CashMovementDirection.outflow},
      financialClass: CashMovementFinancialClass.operatingExpense,
    ),
    'transport': CashMovementCategoryMetadata(
      code: 'transport',
      displayLabel: 'Transporte',
      directions: {CashMovementDirection.outflow},
      financialClass: CashMovementFinancialClass.operatingExpense,
    ),
    'infrastructure': CashMovementCategoryMetadata(
      code: 'infrastructure',
      displayLabel: 'Infraestructura',
      directions: {CashMovementDirection.outflow},
      financialClass: CashMovementFinancialClass.operatingExpense,
    ),
    'cleaning': CashMovementCategoryMetadata(
      code: 'cleaning',
      displayLabel: 'Aseo',
      directions: {CashMovementDirection.outflow},
      financialClass: CashMovementFinancialClass.operatingExpense,
    ),
    'office_supplies': CashMovementCategoryMetadata(
      code: 'office_supplies',
      displayLabel: 'Papelería / suministros',
      directions: {CashMovementDirection.outflow},
      financialClass: CashMovementFinancialClass.operatingExpense,
    ),
    'owner_withdrawal': CashMovementCategoryMetadata(
      code: 'owner_withdrawal',
      displayLabel: 'Retiro del propietario',
      directions: {CashMovementDirection.outflow},
      financialClass: CashMovementFinancialClass.ownerMovement,
    ),
    'owner_contribution': CashMovementCategoryMetadata(
      code: 'owner_contribution',
      displayLabel: 'Aporte del propietario',
      directions: {CashMovementDirection.inflow},
      financialClass: CashMovementFinancialClass.ownerMovement,
    ),
    'other_income': CashMovementCategoryMetadata(
      code: 'other_income',
      displayLabel: 'Otro ingreso',
      directions: {CashMovementDirection.inflow},
      financialClass: CashMovementFinancialClass.otherCashMovement,
    ),
    'other': CashMovementCategoryMetadata(
      code: 'other',
      displayLabel: 'Otro',
      directions: {CashMovementDirection.inflow, CashMovementDirection.outflow},
      financialClass: CashMovementFinancialClass.otherCashMovement,
    ),
  };
}

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
        !(CashMovementCategoryMetadata.byCode[category]?.supports(direction) ??
            false) ||
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
