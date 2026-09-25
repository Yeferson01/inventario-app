part of 'app_database.dart';

/// Inactive C1 storage. No writer service, outbox, sync or recovery registration.
/// Money is integer cents (BigInt), never a floating-point amount.
class LocalCashMovements extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().references(Businesses, #id)();
  TextColumn get branchId => text().references(Branches, #id)();
  TextColumn get cashRegisterId => text().references(CashRegisters, #id)();
  TextColumn get cashSessionId => text().references(CashSessions, #id)();
  TextColumn get direction => text()();
  TextColumn get category => text()();
  Int64Column get amountCents => int64()();
  TextColumn get currency => text()();
  TextColumn get sourceType => text()();
  TextColumn get sourceId => text().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get occurredAt => dateTime()();
  TextColumn get createdBy => text().references(Profiles, #id)();
  TextColumn get idempotencyKey => text()();
  TextColumn get metadataJson => text().withDefault(const Constant('{}'))();
  TextColumn get reversedMovementId =>
      text().nullable().references(LocalCashMovements, #id)();
  TextColumn get localStatus => text().withDefault(const Constant('dirty'))();
  IntColumn get syncStatus => intEnum<SyncStatus>()
      .withDefault(Constant(SyncStatus.pendingInsert.index))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'UNIQUE (business_id, idempotency_key)',
        "CHECK (direction IN ('inflow', 'outflow'))",
        "CHECK (category IN ('supplier_purchase', 'payroll', 'utilities', "
            "'rent', 'maintenance', 'repairs', 'transport', 'infrastructure', "
            "'cleaning', 'office_supplies', 'owner_withdrawal', "
            "'owner_contribution', 'other_income', 'other'))",
        'CHECK (amount_cents > 0 AND amount_cents <= 99999999999999)',
        'CHECK (length(trim(currency)) > 0)',
        'CHECK (length(trim(source_type)) > 0)',
        'CHECK (length(trim(idempotency_key)) > 0)',
        "CHECK (json_valid(metadata_json) AND json_type(metadata_json) = 'object')",
        "CHECK (source_type <> 'purchase' OR source_id IS NOT NULL)",
        'CHECK (reversed_movement_id IS NULL OR reversed_movement_id <> id)',
        "CHECK (local_status IN ('dirty', 'synced', 'conflict', 'error'))",
        'CHECK (sync_status IN (0, 1, 2, 3))',
      ];
}
