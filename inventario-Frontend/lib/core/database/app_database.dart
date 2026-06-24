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
  RealColumn get total => real()();
  TextColumn get paymentMethod => text().nullable()();
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
  IntColumn get quantity => integer()();
  RealColumn get unitPrice => real()();
  RealColumn get subtotal => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Purchase')
class Purchases extends Table {
  TextColumn get id => text()(); // UUID mapeado como String
  TextColumn get businessId => text().nullable().references(Businesses, #id)();
  TextColumn get supplierId => text()
      .nullable()(); // Puede apuntar a un catálogo de proveedores si lo añades luego
  TextColumn get userId => text().nullable().references(Profiles, #id)();
  RealColumn get total => real()();
  TextColumn get status => text().withDefault(const Constant('completed'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get invoicePhotoUrl => text().nullable()();
  TextColumn get processingStatus =>
      text().withDefault(const Constant('pending'))();
  TextColumn get supplierName => text().nullable()();

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
  TextColumn get productId => text().nullable().references(Products, #id)();
  IntColumn get quantity => integer()();
  RealColumn get unitCost => real()();
  RealColumn get subtotal => real()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  IntColumn get syncStatus =>
      intEnum<SyncStatus>().withDefault(Constant(SyncStatus.synced.index))();

  @override
  Set<Column> get primaryKey => {id};
}

// ==========================================
// CLASE CENTRAL DE BASE DE DATOS DRIFT
// ==========================================

@DriftDatabase(
  tables: [
    Businesses,
    Profiles,
    Categories,
    Customers,
    Products,
    Sales,
    SaleItems,
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
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Aquí manejarás tus futuras migraciones de forma estructurada
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
