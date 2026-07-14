import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

part 'app_database.g.dart';

part '../../features/inventory/data/datasources/product_dao.dart';
part '../../features/inventory/data/datasources/category_dao.dart';
part '../../features/inventory/data/datasources/purchase_dao.dart';
part '../../features/sales/data/datasources/sale_dao.dart';
part '../../features/customers/data/datasources/customer_dao.dart';
part '../../features/auth/data/datasources/profile_dao.dart';
part '../../features/auth/data/datasources/business_dao.dart';

/// Estado de sincronización local para el Sync Engine (Fase 4)
enum SyncStatus {
  synced,
  pendingInsert,
  pendingUpdate,
  pendingDelete,
}

// ==========================================
// DEFINICIÓN DE TABLAS LOCALES (DRIFT)
// ==========================================

@DataClassName('Business')
class Businesses extends Table {
  TextColumn get id => text()(); // UUID de Supabase mapped como String
  TextColumn get name => text()();
  TextColumn get businessType => text().nullable()();
  TextColumn get ownerName => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable().unique()();
  TextColumn get address => text().nullable()();
  TextColumn get subscriptionPlan =>
      text().withDefault(const Constant('free'))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  // Control Local Offline-First
  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Profile')
class Profiles extends Table {
  TextColumn get id => text()(); // ID correspondiente a auth.users(id)
  TextColumn get businessId => text().nullable().references(Businesses, #id)();
  TextColumn get fullName => text().nullable()();
  TextColumn get role =>
      text().nullable()(); // 'owner', 'admin', 'cashier', etc.
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Category')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().nullable().references(Businesses, #id)();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Customer')
class Customers extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().nullable().references(Businesses, #id)();
  TextColumn get fullName => text()();
  TextColumn get phone => text().nullable()();
  TextColumn get email => text().nullable()();
  TextColumn get address => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Product')
class Products extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().nullable().references(Businesses, #id)();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get barcode => text().nullable()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  RealColumn get purchasePrice => real().withDefault(const Constant(0.0))();
  RealColumn get salePrice => real()();
  IntColumn get stockQuantity => integer().withDefault(const Constant(0))();
  IntColumn get minimumStock => integer().withDefault(const Constant(0))();
  TextColumn get unit => text().withDefault(const Constant('unidad'))();
  TextColumn get status => text().withDefault(const Constant('active'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get simpleCategory => text().nullable()();

  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Sale')
class Sales extends Table {
  TextColumn get id => text()();
  TextColumn get businessId => text().nullable().references(Businesses, #id)();
  TextColumn get userId => text().nullable().references(Profiles, #id)();
  TextColumn get customerId => text().nullable().references(Customers, #id)();

  TextColumn get branchId => text().nullable().references(Branches, #id)();

  TextColumn get cashRegisterId =>
      text().nullable().named('cash_register_id')();

  TextColumn get cashSessionId => text().nullable().named('cash_session_id')();

  RealColumn get subtotal => real().withDefault(const Constant(0))();

  RealColumn get discountTotal =>
      real().withDefault(const Constant(0)).named('discount_total')();

  RealColumn get taxTotal =>
      real().withDefault(const Constant(0)).named('tax_total')();

  RealColumn get total => real()();

  // Campo legacy. Para POS profesional usar sale_payments.
  TextColumn get paymentMethod => text().nullable()();

  TextColumn get paymentStatus =>
      text().withDefault(const Constant('paid')).named('payment_status')();

  TextColumn get idempotencyKey => text().nullable().named('idempotency_key')();

  TextColumn get localStatus =>
      text().withDefault(const Constant('synced')).named('local_status')();

  TextColumn get metadataJson => text().nullable().named('metadata_json')();

  TextColumn get status => text().withDefault(const Constant('completed'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SaleItem')
class SaleItems extends Table {
  TextColumn get id => text()();
  TextColumn get saleId => text().nullable().references(Sales, #id)();
  TextColumn get productId => text().nullable().references(Products, #id)();

  TextColumn get productNameSnapshot =>
      text().nullable().named('product_name_snapshot')();

  TextColumn get barcodeSnapshot =>
      text().nullable().named('barcode_snapshot')();

  IntColumn get quantity => integer()();

  RealColumn get unitPrice => real()();

  RealColumn get discountTotal =>
      real().withDefault(const Constant(0)).named('discount_total')();

  RealColumn get taxTotal =>
      real().withDefault(const Constant(0)).named('tax_total')();

  RealColumn get subtotal => real()();

  RealColumn get lineTotal =>
      real().withDefault(const Constant(0)).named('line_total')();

  TextColumn get metadataJson => text().nullable().named('metadata_json')();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SalePayment')
class SalePayments extends Table {
  TextColumn get id => text()();

  TextColumn get businessId => text().named('business_id')();

  TextColumn get branchId => text().nullable().named('branch_id')();

  TextColumn get saleId => text().named('sale_id').references(Sales, #id)();

  TextColumn get paymentMethod => text().named('payment_method')();

  RealColumn get amount => real()();

  TextColumn get currency => text().withDefault(const Constant('COP'))();

  TextColumn get status => text().withDefault(const Constant('completed'))();

  TextColumn get reference => text().nullable()();

  TextColumn get metadataJson => text().nullable().named('metadata_json')();

  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  TextColumn get localStatus =>
      text().withDefault(const Constant('synced')).named('local_status')();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Purchase')
class Purchases extends Table {
  TextColumn get id => text()(); // UUID mapeado como String
  TextColumn get businessId => text().nullable().references(Businesses, #id)();

  TextColumn get branchId => text().nullable().references(Branches, #id)();

  TextColumn get supplierId => text()
      .nullable()(); // Puede apuntar a un catálogo de proveedores si lo añades luego

  TextColumn get userId => text().nullable().references(Profiles, #id)();

  RealColumn get total => real()();

  TextColumn get status => text().withDefault(const Constant('completed'))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  DateTimeColumn get lastSyncedAt =>
      dateTime().nullable().named('last_synced_at')();

  TextColumn get invoicePhotoUrl => text().nullable()();

  TextColumn get processingStatus =>
      text().withDefault(const Constant('pending'))();

  TextColumn get supplierName => text().nullable()();

  TextColumn get idempotencyKey => text().nullable().named('idempotency_key')();

  TextColumn get localStatus =>
      text().withDefault(const Constant('synced')).named('local_status')();

  TextColumn get metadataJson => text().nullable().named('metadata_json')();

  IntColumn get version => integer().withDefault(const Constant(1))();

  // Control Local Offline-First
  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PurchaseItem')
class PurchaseItems extends Table {
  TextColumn get id => text()();
  TextColumn get purchaseId => text().nullable().references(Purchases, #id)();

  TextColumn get businessId => text().nullable().references(Businesses, #id)();

  TextColumn get branchId => text().nullable().references(Branches, #id)();

  TextColumn get productId => text().nullable().references(Products, #id)();

  IntColumn get quantity => integer()();

  RealColumn get unitCost => real()();

  RealColumn get subtotal => real()();

  TextColumn get idempotencyKey => text().nullable().named('idempotency_key')();

  TextColumn get localStatus =>
      text().withDefault(const Constant('synced')).named('local_status')();

  TextColumn get metadataJson => text().nullable().named('metadata_json')();

  IntColumn get version => integer().withDefault(const Constant(1))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  DateTimeColumn get lastSyncedAt =>
      dateTime().nullable().named('last_synced_at')();

  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('CashRegister')
class CashRegisters extends Table {
  TextColumn get id => text()();

  TextColumn get businessId => text().nullable().references(Businesses, #id)();

  TextColumn get branchId => text().nullable().references(Branches, #id)();

  TextColumn get name => text().withDefault(const Constant('Caja principal'))();

  TextColumn get code => text().nullable()();

  TextColumn get status => text().withDefault(const Constant('active'))();

  TextColumn get idempotencyKey => text().nullable().named('idempotency_key')();

  TextColumn get localStatus =>
      text().withDefault(const Constant('synced')).named('local_status')();

  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  IntColumn get version => integer().withDefault(const Constant(1))();

  TextColumn get metadataJson => text().nullable().named('metadata_json')();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  DateTimeColumn get lastSyncedAt =>
      dateTime().nullable().named('last_synced_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('CashSession')
class CashSessions extends Table {
  TextColumn get id => text()();

  TextColumn get businessId => text().nullable().references(Businesses, #id)();

  TextColumn get branchId => text().nullable().references(Branches, #id)();

  TextColumn get cashRegisterId => text()
      .nullable()
      .references(CashRegisters, #id)
      .named('cash_register_id')();

  TextColumn get openedByProfileId => text()
      .nullable()
      .references(Profiles, #id)
      .named('opened_by_profile_id')();

  TextColumn get closedByProfileId => text()
      .nullable()
      .references(Profiles, #id)
      .named('closed_by_profile_id')();

  DateTimeColumn get openedAt =>
      dateTime().withDefault(currentDateAndTime).named('opened_at')();

  DateTimeColumn get closedAt => dateTime().nullable().named('closed_at')();

  RealColumn get openingCashAmount =>
      real().withDefault(const Constant(0)).named('opening_cash_amount')();

  RealColumn get closingCashAmount =>
      real().nullable().named('closing_cash_amount')();

  RealColumn get expectedCashAmount =>
      real().nullable().named('expected_cash_amount')();

  RealColumn get differenceAmount =>
      real().nullable().named('difference_amount')();

  TextColumn get status => text().withDefault(const Constant('open'))();

  TextColumn get idempotencyKey => text().nullable().named('idempotency_key')();

  TextColumn get localStatus =>
      text().withDefault(const Constant('synced')).named('local_status')();

  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  IntColumn get version => integer().withDefault(const Constant(1))();

  TextColumn get metadataJson => text().nullable().named('metadata_json')();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get deletedAt => dateTime().nullable()();

  DateTimeColumn get lastSyncedAt =>
      dateTime().nullable().named('last_synced_at')();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

// ==========================================
// CLASE CENTRAL DE BASE DE DATOS DRIFT
// ==========================================

// === 6.18C.9.6 LOCAL CATALOG AND SYNC TABLES ===

class LocalMasterProductsCatalog extends Table {
  @override
  String get tableName => 'local_master_products_catalog';

  TextColumn get id => text()();

  TextColumn get barcode => text().nullable()();
  TextColumn get gtin => text().nullable()();
  TextColumn get barcodeNormalized =>
      text().nullable().named('barcode_normalized')();

  TextColumn get name => text().nullable()();
  TextColumn get productName => text().nullable().named('product_name')();
  TextColumn get normalizedName => text().nullable().named('normalized_name')();

  TextColumn get brand => text().nullable()();
  TextColumn get manufacturer => text().nullable()();
  TextColumn get categoryName => text().nullable().named('category_name')();
  TextColumn get subcategoryName =>
      text().nullable().named('subcategory_name')();

  RealColumn get packageSize => real().nullable().named('package_size')();
  TextColumn get packageUnit => text().nullable().named('package_unit')();
  TextColumn get unitType => text().nullable().named('unit_type')();

  BoolColumn get hasImage =>
      boolean().withDefault(const Constant(false)).named('has_image')();
  TextColumn get imageThumbUrl => text().nullable().named('image_thumb_url')();
  TextColumn get imageHash => text().nullable().named('image_hash')();

  TextColumn get source => text().nullable()();
  TextColumn get verificationStatus =>
      text().nullable().named('verification_status')();
  RealColumn get confidenceScore =>
      real().nullable().named('confidence_score')();
  IntColumn get catalogVersion =>
      integer().withDefault(const Constant(1)).named('catalog_version')();

  TextColumn get syncStatus =>
      text().withDefault(const Constant('synced')).named('sync_status')();
  TextColumn get localStatus =>
      text().withDefault(const Constant('clean')).named('local_status')();
  IntColumn get version => integer().withDefault(const Constant(1))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime).named('created_at')();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime).named('updated_at')();
  DateTimeColumn get deletedAt => dateTime().nullable().named('deleted_at')();
  DateTimeColumn get lastSyncedAt =>
      dateTime().nullable().named('last_synced_at')();

  TextColumn get metadataJson => text().nullable().named('metadata_json')();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalProductBarcodes extends Table {
  @override
  String get tableName => 'local_product_barcodes';

  TextColumn get id => text()();

  TextColumn get scope => text()();
  TextColumn get businessId => text().nullable().named('business_id')();
  TextColumn get productId => text().nullable().named('product_id')();
  TextColumn get masterProductId =>
      text().nullable().named('master_product_id')();

  TextColumn get barcode => text()();
  TextColumn get barcodeNormalized => text().named('barcode_normalized')();
  TextColumn get barcodeType => text().nullable().named('barcode_type')();

  BoolColumn get isPrimary =>
      boolean().withDefault(const Constant(false)).named('is_primary')();
  TextColumn get status => text().withDefault(const Constant('active'))();
  TextColumn get source => text().nullable()();
  RealColumn get confidenceScore =>
      real().nullable().named('confidence_score')();

  TextColumn get syncStatus =>
      text().withDefault(const Constant('synced')).named('sync_status')();
  TextColumn get localStatus =>
      text().withDefault(const Constant('clean')).named('local_status')();
  IntColumn get version => integer().withDefault(const Constant(1))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime).named('created_at')();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime).named('updated_at')();
  DateTimeColumn get deletedAt => dateTime().nullable().named('deleted_at')();
  DateTimeColumn get lastSyncedAt =>
      dateTime().nullable().named('last_synced_at')();

  TextColumn get metadataJson => text().nullable().named('metadata_json')();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalCatalogSyncState extends Table {
  @override
  String get tableName => 'local_catalog_sync_state';

  TextColumn get id => text()();
  TextColumn get businessId => text().named('business_id')();

  DateTimeColumn get lastCatalogPullAt =>
      dateTime().nullable().named('last_catalog_pull_at')();
  DateTimeColumn get lastServerTime =>
      dateTime().nullable().named('last_server_time')();
  DateTimeColumn get lastSinceUpdatedAt =>
      dateTime().nullable().named('last_since_updated_at')();
  IntColumn get lastCatalogVersion =>
      integer().nullable().named('last_catalog_version')();

  TextColumn get lastPageToken => text().nullable().named('last_page_token')();
  BoolColumn get isSyncing =>
      boolean().withDefault(const Constant(false)).named('is_syncing')();
  TextColumn get lastError => text().nullable().named('last_error')();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime).named('created_at')();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime).named('updated_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalCatalogContributionQueue extends Table {
  @override
  String get tableName => 'local_catalog_contribution_queue';

  TextColumn get id => text()();

  TextColumn get businessId => text().named('business_id')();
  TextColumn get branchId => text().nullable().named('branch_id')();

  TextColumn get localProductId =>
      text().nullable().named('local_product_id')();
  TextColumn get masterProductId =>
      text().nullable().named('master_product_id')();

  TextColumn get contributionType => text().named('contribution_type')();

  TextColumn get barcode => text().nullable()();
  TextColumn get barcodeNormalized =>
      text().nullable().named('barcode_normalized')();
  TextColumn get barcodeType => text().nullable().named('barcode_type')();

  TextColumn get suggestedName => text().nullable().named('suggested_name')();
  TextColumn get suggestedBrand => text().nullable().named('suggested_brand')();
  TextColumn get suggestedManufacturer =>
      text().nullable().named('suggested_manufacturer')();
  TextColumn get suggestedCategoryName =>
      text().nullable().named('suggested_category_name')();
  TextColumn get suggestedSubcategoryName =>
      text().nullable().named('suggested_subcategory_name')();
  RealColumn get suggestedPackageSize =>
      real().nullable().named('suggested_package_size')();
  TextColumn get suggestedPackageUnit =>
      text().nullable().named('suggested_package_unit')();
  TextColumn get suggestedUnitType =>
      text().nullable().named('suggested_unit_type')();

  TextColumn get suggestedImageUrl =>
      text().nullable().named('suggested_image_url')();
  TextColumn get suggestedImageThumbUrl =>
      text().nullable().named('suggested_image_thumb_url')();
  TextColumn get suggestedImageHash =>
      text().nullable().named('suggested_image_hash')();

  TextColumn get source => text().withDefault(const Constant('app'))();
  RealColumn get confidenceScore =>
      real().nullable().named('confidence_score')();
  TextColumn get metadataJson => text().nullable().named('metadata_json')();

  TextColumn get localStatus =>
      text().withDefault(const Constant('pending')).named('local_status')();
  TextColumn get serverContributionId =>
      text().nullable().named('server_contribution_id')();
  IntColumn get retryCount =>
      integer().withDefault(const Constant(0)).named('retry_count')();
  TextColumn get lastError => text().nullable().named('last_error')();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime).named('created_at')();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime).named('updated_at')();
  DateTimeColumn get syncedAt => dateTime().nullable().named('synced_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalSyncBatches extends Table {
  @override
  String get tableName => 'local_sync_batches';

  TextColumn get id => text()();
  TextColumn get serverSyncBatchId =>
      text().nullable().named('server_sync_batch_id')();

  TextColumn get clientBatchId => text().named('client_batch_id')();

  TextColumn get businessId => text().named('business_id')();
  TextColumn get branchId => text().nullable().named('branch_id')();
  TextColumn get appDeviceId => text().nullable().named('app_device_id')();
  TextColumn get profileId => text().nullable().named('profile_id')();

  TextColumn get domain => text()();
  TextColumn get direction => text().withDefault(const Constant('upload'))();
  TextColumn get status => text().withDefault(const Constant('pending'))();

  IntColumn get mutationCount =>
      integer().withDefault(const Constant(0)).named('mutation_count')();
  IntColumn get appliedCount =>
      integer().withDefault(const Constant(0)).named('applied_count')();
  IntColumn get skippedCount =>
      integer().withDefault(const Constant(0)).named('skipped_count')();
  IntColumn get conflictCount =>
      integer().withDefault(const Constant(0)).named('conflict_count')();
  IntColumn get errorCount =>
      integer().withDefault(const Constant(0)).named('error_count')();

  TextColumn get metadataJson => text().nullable().named('metadata_json')();
  TextColumn get lastError => text().nullable().named('last_error')();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime).named('created_at')();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime).named('updated_at')();
  DateTimeColumn get uploadedAt => dateTime().nullable().named('uploaded_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalSyncMutations extends Table {
  @override
  String get tableName => 'local_sync_mutations';

  TextColumn get id => text()();
  TextColumn get serverSyncMutationId =>
      text().nullable().named('server_sync_mutation_id')();

  TextColumn get localSyncBatchId =>
      text().nullable().named('local_sync_batch_id')();
  TextColumn get clientBatchId => text().nullable().named('client_batch_id')();
  TextColumn get clientMutationId => text().named('client_mutation_id')();
  IntColumn get clientSequence => integer().named('client_sequence')();

  TextColumn get businessId => text().named('business_id')();
  TextColumn get branchId => text().nullable().named('branch_id')();
  TextColumn get appDeviceId => text().nullable().named('app_device_id')();
  TextColumn get profileId => text().nullable().named('profile_id')();

  TextColumn get entityTable => text().named('entity_table')();
  TextColumn get entityId => text().named('entity_id')();
  TextColumn get operation => text()();

  TextColumn get payloadJson => text().named('payload_json')();
  TextColumn get beforePayloadJson =>
      text().nullable().named('before_payload_json')();
  TextColumn get changedFieldsJson =>
      text().nullable().named('changed_fields_json')();

  IntColumn get baseVersion => integer().nullable().named('base_version')();
  DateTimeColumn get baseUpdatedAt =>
      dateTime().nullable().named('base_updated_at')();

  TextColumn get idempotencyKey => text().named('idempotency_key')();
  TextColumn get status => text().withDefault(const Constant('pending'))();

  IntColumn get retryCount =>
      integer().withDefault(const Constant(0)).named('retry_count')();
  TextColumn get lastError => text().nullable().named('last_error')();
  TextColumn get errorCode => text().nullable().named('error_code')();

  TextColumn get metadataJson => text().nullable().named('metadata_json')();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime).named('created_at')();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime).named('updated_at')();
  DateTimeColumn get uploadedAt => dateTime().nullable().named('uploaded_at')();
  DateTimeColumn get resolvedAt => dateTime().nullable().named('resolved_at')();

  @override
  Set<Column> get primaryKey => {id};
}

// === 6.18C.17 LOCAL APP CONTEXT TABLES ===

class Branches extends Table {
  @override
  String get tableName => 'branches';

  TextColumn get id => text()();
  TextColumn get businessId =>
      text().named('business_id').references(Businesses, #id)();

  TextColumn get name => text()();
  TextColumn get address => text().nullable()();
  TextColumn get phone => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();

  IntColumn get syncStatus =>
      integer().withDefault(const Constant(0)).named('sync_status')();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime).named('created_at')();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime).named('updated_at')();
  DateTimeColumn get deletedAt => dateTime().nullable().named('deleted_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class Roles extends Table {
  @override
  String get tableName => 'roles';

  TextColumn get id => text()();
  TextColumn get businessId => text().nullable().named('business_id')();

  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  BoolColumn get isSystemRole =>
      boolean().withDefault(const Constant(false)).named('is_system_role')();

  IntColumn get syncStatus =>
      integer().withDefault(const Constant(0)).named('sync_status')();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime).named('created_at')();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime).named('updated_at')();
  DateTimeColumn get deletedAt => dateTime().nullable().named('deleted_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class Permissions extends Table {
  @override
  String get tableName => 'permissions';

  TextColumn get id => text()();
  TextColumn get key => text()();
  TextColumn get description => text().nullable()();

  IntColumn get syncStatus =>
      integer().withDefault(const Constant(0)).named('sync_status')();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime).named('created_at')();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime).named('updated_at')();
  DateTimeColumn get deletedAt => dateTime().nullable().named('deleted_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class RolePermissions extends Table {
  @override
  String get tableName => 'role_permissions';

  TextColumn get roleId => text().named('role_id').references(Roles, #id)();
  TextColumn get permissionId =>
      text().named('permission_id').references(Permissions, #id)();

  IntColumn get syncStatus =>
      integer().withDefault(const Constant(0)).named('sync_status')();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime).named('created_at')();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime).named('updated_at')();
  DateTimeColumn get deletedAt => dateTime().nullable().named('deleted_at')();

  @override
  Set<Column> get primaryKey => {roleId, permissionId};
}

class BusinessMembers extends Table {
  @override
  String get tableName => 'business_members';

  TextColumn get id => text()();

  TextColumn get businessId =>
      text().named('business_id').references(Businesses, #id)();
  TextColumn get profileId =>
      text().named('profile_id').references(Profiles, #id)();
  TextColumn get branchId =>
      text().nullable().named('branch_id').references(Branches, #id)();
  TextColumn get roleId => text().named('role_id').references(Roles, #id)();

  TextColumn get status => text().withDefault(const Constant('active'))();

  TextColumn get invitedBy => text().nullable().named('invited_by')();
  DateTimeColumn get invitedAt => dateTime().nullable().named('invited_at')();
  DateTimeColumn get acceptedAt => dateTime().nullable().named('accepted_at')();

  IntColumn get syncStatus =>
      integer().withDefault(const Constant(0)).named('sync_status')();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime).named('created_at')();
  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime).named('updated_at')();
  DateTimeColumn get deletedAt => dateTime().nullable().named('deleted_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalInventoryMovements extends Table {
  TextColumn get id => text()();

  TextColumn get businessId => text().named('business_id')();
  TextColumn get branchId => text().nullable().named('branch_id')();
  TextColumn get productId => text().named('product_id')();

  TextColumn get movementType => text().named('movement_type')();
  IntColumn get quantityChange => integer().named('quantity_change')();

  RealColumn get unitCost => real().nullable().named('unit_cost')();

  TextColumn get sourceType => text().nullable().named('source_type')();
  TextColumn get sourceId => text().nullable().named('source_id')();

  TextColumn get referenceType => text().nullable().named('reference_type')();
  TextColumn get referenceId => text().nullable().named('reference_id')();

  TextColumn get notes => text().nullable()();

  TextColumn get idempotencyKey => text().named('idempotency_key')();

  IntColumn get syncStatus =>
      integer().withDefault(const Constant(0)).named('sync_status')();

  TextColumn get localStatus =>
      text().withDefault(const Constant('dirty')).named('local_status')();

  IntColumn get version => integer().withDefault(const Constant(1))();

  DateTimeColumn get occurredAt => dateTime().named('occurred_at')();

  TextColumn get metadataJson => text().nullable().named('metadata_json')();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime).named('created_at')();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime).named('updated_at')();

  DateTimeColumn get deletedAt => dateTime().nullable().named('deleted_at')();

  DateTimeColumn get lastSyncedAt =>
      dateTime().nullable().named('last_synced_at')();

  @override
  Set<Column> get primaryKey => {id};
}

class LocalProductStockBalances extends Table {
  TextColumn get id => text()();

  TextColumn get businessId => text()();

  TextColumn get branchId => text()();

  TextColumn get productId => text()();

  IntColumn get quantityOnHand => integer().withDefault(const Constant(0))();

  IntColumn get quantityReserved => integer().withDefault(const Constant(0))();

  IntColumn get quantityAvailable => integer().withDefault(const Constant(0))();

  RealColumn get averageCost => real().nullable()();

  DateTimeColumn get lastMovementAt => dateTime().nullable()();

  DateTimeColumn get remoteUpdatedAt => dateTime().nullable()();

  DateTimeColumn get lastSyncedAt => dateTime().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();

  TextColumn get metadataJson => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Branches,
    Roles,
    Permissions,
    RolePermissions,
    BusinessMembers,
    LocalMasterProductsCatalog,
    LocalProductBarcodes,
    LocalCatalogSyncState,
    LocalCatalogContributionQueue,
    LocalSyncBatches,
    LocalSyncMutations,
    LocalInventoryMovements,
    LocalProductStockBalances,
    Businesses,
    Profiles,
    Categories,
    Customers,
    Products,
    Sales,
    SaleItems,
    CashRegisters,
    CashSessions,
    SalePayments,
    Purchases,
    PurchaseItems,
  ],
  daos: [
    BusinessDao,
    ProfileDao,
    CategoryDao,
    CustomerDao,
    ProductDao,
    SaleDao,
    PurchaseDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

// Constructor secundario (o de fábrica) que usaremos exclusivamente para los tests
  AppDatabase.executor(QueryExecutor e) : super(e);

  // Incrementa la versión si cambias la estructura de las tablas en el futuro
  @override
  int get schemaVersion => 8;

  Future<void> _createCashSessionIndexes() async {
    final cashRegistersTable = await customSelect(
      "select name from sqlite_master "
      "where type = 'table' and name = 'cash_registers' "
      "limit 1",
    ).getSingleOrNull();

    final cashSessionsTable = await customSelect(
      "select name from sqlite_master "
      "where type = 'table' and name = 'cash_sessions' "
      "limit 1",
    ).getSingleOrNull();

    if (cashRegistersTable == null || cashSessionsTable == null) {
      return;
    }

    await customStatement(
      'create index if not exists idx_cash_registers_business_branch '
      'on cash_registers(business_id, branch_id)',
    );

    await customStatement(
      'create unique index if not exists ux_cash_registers_idempotency_key '
      'on cash_registers(idempotency_key) where idempotency_key is not null',
    );

    await customStatement(
      'create index if not exists idx_cash_sessions_business_branch_status '
      'on cash_sessions(business_id, branch_id, status)',
    );

    await customStatement(
      'create index if not exists idx_cash_sessions_register_status '
      'on cash_sessions(cash_register_id, status, opened_at)',
    );

    await customStatement(
      'create unique index if not exists ux_cash_sessions_idempotency_key '
      'on cash_sessions(idempotency_key) where idempotency_key is not null',
    );

    await customStatement(
      "create unique index if not exists ux_cash_sessions_one_open_per_register "
      "on cash_sessions(cash_register_id) "
      "where status = 'open' and deleted_at is null",
    );
  }

  Future<void> _createPurchaseIndexes() async {
    await customStatement(
      'create index if not exists idx_purchases_business_branch_created '
      'on purchases(business_id, branch_id, created_at)',
    );

    await customStatement(
      'create unique index if not exists ux_purchases_idempotency_key '
      'on purchases(idempotency_key) where idempotency_key is not null',
    );

    await customStatement(
      'create index if not exists idx_purchase_items_purchase '
      'on purchase_items(purchase_id)',
    );

    await customStatement(
      'create index if not exists idx_purchase_items_business_branch_product '
      'on purchase_items(business_id, branch_id, product_id)',
    );

    await customStatement(
      'create unique index if not exists ux_purchase_items_idempotency_key '
      'on purchase_items(idempotency_key) where idempotency_key is not null',
    );
  }

  Future<void> _createPosIndexes() async {
    await customStatement(
      'create index if not exists idx_sales_business_branch_created '
      'on sales(business_id, branch_id, created_at)',
    );

    await customStatement(
      'create index if not exists idx_sales_cash_session '
      'on sales(cash_session_id, created_at)',
    );

    await customStatement(
      'create unique index if not exists ux_sales_idempotency_key '
      'on sales(idempotency_key) where idempotency_key is not null',
    );

    await customStatement(
      'create index if not exists idx_sale_items_sale '
      'on sale_items(sale_id)',
    );

    await customStatement(
      'create index if not exists idx_sale_items_product '
      'on sale_items(product_id)',
    );

    await customStatement(
      'create index if not exists idx_sale_payments_sale '
      'on sale_payments(sale_id)',
    );

    await customStatement(
      'create index if not exists idx_sale_payments_business_branch '
      'on sale_payments(business_id, branch_id, created_at)',
    );
  }

  Future<void> _createInventoryMovementIndexes() async {
    await customStatement(
      'create unique index if not exists ux_local_inventory_movements_idempotency_key '
      'on local_inventory_movements(idempotency_key)',
    );

    await customStatement(
      'create index if not exists idx_local_inventory_movements_business_product '
      'on local_inventory_movements(business_id, branch_id, product_id)',
    );

    await customStatement(
      'create index if not exists idx_local_inventory_movements_sync_status '
      'on local_inventory_movements(sync_status, local_status, created_at)',
    );
  }

  Future<void> _createAppContextIndexes() async {
    await customStatement(
      'create index if not exists idx_branches_business_status on branches(business_id, status)',
    );
    await customStatement(
      'create index if not exists idx_business_members_lookup on business_members(business_id, profile_id, branch_id, status)',
    );
    await customStatement(
      'create index if not exists idx_roles_business_name on roles(business_id, name)',
    );
    await customStatement(
      'create unique index if not exists idx_permissions_key on permissions(key)',
    );
    await customStatement(
      'create index if not exists idx_role_permissions_role on role_permissions(role_id)',
    );
    await customStatement(
      'create index if not exists idx_role_permissions_permission on role_permissions(permission_id)',
    );
  }

  Future<void> ensureLocalSyncOutboxIndexes() async {
    final outboxTable = await customSelect(
      '''
      select name
      from sqlite_master
      where type = 'table'
        and name = ?
      limit 1
      ''',
      variables: [Variable<String>('local_sync_outbox')],
    ).getSingleOrNull();

    if (outboxTable == null) {
      return;
    }

    await customStatement(
      'create index if not exists idx_local_sync_outbox_status_created_at '
      'on local_sync_outbox(status, created_at)',
    );

    await customStatement(
      'create index if not exists idx_local_sync_outbox_business_status '
      'on local_sync_outbox(business_id, status)',
    );

    await customStatement(
      'create index if not exists idx_local_sync_outbox_entity '
      'on local_sync_outbox(entity_type, entity_id)',
    );
  }

  Future<void> _createProductStockBalanceIndexes() async {
    await customStatement('''
      create unique index if not exists ux_local_product_stock_balances_scope
      on local_product_stock_balances (business_id, branch_id, product_id)
    ''');

    await customStatement('''
      create index if not exists idx_local_product_stock_balances_branch
      on local_product_stock_balances (business_id, branch_id)
    ''');

    await customStatement('''
      create index if not exists idx_local_product_stock_balances_product
      on local_product_stock_balances (product_id)
    ''');

    await customStatement('''
      create index if not exists idx_local_product_stock_balances_updated
      on local_product_stock_balances (remote_updated_at)
    ''');
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createCashSessionIndexes();

          await _createAppContextIndexes();
          await _createInventoryMovementIndexes();
          await _createProductStockBalanceIndexes();
          await _createPosIndexes();
          await _createPurchaseIndexes();
          await ensureLocalSyncOutboxIndexes();
        },
        onUpgrade: (m, from, to) async {
          if (from < 8) {
            await m.createTable(cashRegisters);
            await m.createTable(cashSessions);
            await _createCashSessionIndexes();
          }

          if (from < 7) {
            await m.addColumn(purchases, purchases.branchId);
            await m.addColumn(purchases, purchases.lastSyncedAt);
            await m.addColumn(purchases, purchases.idempotencyKey);
            await m.addColumn(purchases, purchases.localStatus);
            await m.addColumn(purchases, purchases.metadataJson);
            await m.addColumn(purchases, purchases.version);

            await m.addColumn(purchaseItems, purchaseItems.businessId);
            await m.addColumn(purchaseItems, purchaseItems.branchId);
            await m.addColumn(purchaseItems, purchaseItems.idempotencyKey);
            await m.addColumn(purchaseItems, purchaseItems.localStatus);
            await m.addColumn(purchaseItems, purchaseItems.metadataJson);
            await m.addColumn(purchaseItems, purchaseItems.version);
            await m.addColumn(purchaseItems, purchaseItems.updatedAt);
            await m.addColumn(purchaseItems, purchaseItems.deletedAt);
            await m.addColumn(purchaseItems, purchaseItems.lastSyncedAt);

            await _createPurchaseIndexes();
          }
          if (from < 6) {
            await m.addColumn(sales, sales.branchId);
            await m.addColumn(sales, sales.cashRegisterId);
            await m.addColumn(sales, sales.cashSessionId);
            await m.addColumn(sales, sales.subtotal);
            await m.addColumn(sales, sales.discountTotal);
            await m.addColumn(sales, sales.taxTotal);
            await m.addColumn(sales, sales.paymentStatus);
            await m.addColumn(sales, sales.idempotencyKey);
            await m.addColumn(sales, sales.localStatus);
            await m.addColumn(sales, sales.metadataJson);

            await m.addColumn(saleItems, saleItems.productNameSnapshot);
            await m.addColumn(saleItems, saleItems.barcodeSnapshot);
            await m.addColumn(saleItems, saleItems.discountTotal);
            await m.addColumn(saleItems, saleItems.taxTotal);
            await m.addColumn(saleItems, saleItems.lineTotal);
            await m.addColumn(saleItems, saleItems.metadataJson);
            await m.addColumn(saleItems, saleItems.updatedAt);

            await m.createTable(salePayments);
            await _createPosIndexes();
          }
          if (from < 5) {
            await m.createTable(localProductStockBalances);
            await _createProductStockBalanceIndexes();
            await _createPosIndexes();
          }

          if (from < 3) {
            await m.createTable(branches);
            await m.createTable(roles);
            await m.createTable(permissions);
            await m.createTable(rolePermissions);
            await m.createTable(businessMembers);
            await _createAppContextIndexes();
          }

          if (from < 4) {
            await m.createTable(localInventoryMovements);
            await _createInventoryMovementIndexes();
          }

          // Aquí manejarás tus futuras migraciones de forma estructurada
        },
        beforeOpen: (details) async {
          await _createCashSessionIndexes();
          await _createProductStockBalanceIndexes();
          await _createPosIndexes();
          await _createInventoryMovementIndexes();
          await ensureLocalSyncOutboxIndexes();
        },
      );
}

// Conexión nativa adaptada a Móvil (Android/iOS) y Escritorio
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'app_local_database.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
