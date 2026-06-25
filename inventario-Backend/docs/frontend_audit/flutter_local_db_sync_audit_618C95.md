# Auditoría Flutter Local DB / Drift — Fase 6.18C.9.5

Fecha: Thu Jun 25 14:19:11 HPS 2026

## 1. Archivos principales de base local

lib/core/database/app_database.dart
lib/core/database/app_database.g.dart
lib/core/database/converters/.gitkeep
lib/core/database/migrations/.gitkeep
lib/core/database/tables/.gitkeep

## 2. Archivos DAO existentes

lib/features/auth/data/datasources/business_dao.dart
lib/features/auth/data/datasources/profile_dao.dart
lib/features/catalog/data/datasources/.gitkeep
lib/features/catalog/data/datasources/catalog_local_dao.dart
lib/features/catalog/data/datasources/catalog_remote_datasource.dart
lib/features/catalog/data/repositories/catalog_local_repository.dart
lib/features/customers/data/datasources/customer_dao.dart
lib/features/inventory/data/datasources/category_dao.dart
lib/features/inventory/data/datasources/product_dao.dart
lib/features/inventory/data/datasources/purchase_dao.dart
lib/features/pos/data/datasources/.gitkeep
lib/features/sales/data/datasources/sale_dao.dart
lib/features/settings/data/datasources/.gitkeep
lib/features/sync/data/datasources/.gitkeep

## 3. Declaración DriftDatabase

lib/core/database/app_database.dart:216:@DriftDatabase(
lib/core/database/app_database.dart:238:class AppDatabase extends _$AppDatabase {
lib/core/database/app_database.dart:246:  int get schemaVersion => 1;

## 4. Tablas locales declaradas

lib/core/database/app_database.dart:30:class Businesses extends Table {
lib/core/database/app_database.dart:54:class Profiles extends Table {
lib/core/database/app_database.dart:72:class Categories extends Table {
lib/core/database/app_database.dart:89:class Customers extends Table {
lib/core/database/app_database.dart:108:class Products extends Table {
lib/core/database/app_database.dart:134:class Sales extends Table {
lib/core/database/app_database.dart:154:class SaleItems extends Table {
lib/core/database/app_database.dart:171:class Purchases extends Table {
lib/core/database/app_database.dart:196:class PurchaseItems extends Table {
lib/core/database/app_database.g.dart:225:class Business extends DataClass implements Insertable<Business> {
lib/core/database/app_database.g.dart:649:class $ProfilesTable extends Profiles with TableInfo<$ProfilesTable, Profile> {
lib/core/database/app_database.g.dart:799:class Profile extends DataClass implements Insertable<Profile> {
lib/core/database/app_database.g.dart:1238:class Category extends DataClass implements Insertable<Category> {
lib/core/database/app_database.g.dart:1704:class Customer extends DataClass implements Insertable<Customer> {
lib/core/database/app_database.g.dart:2042:class $ProductsTable extends Products with TableInfo<$ProductsTable, Product> {
lib/core/database/app_database.g.dart:2335:class Product extends DataClass implements Insertable<Product> {
lib/core/database/app_database.g.dart:2861:class $SalesTable extends Sales with TableInfo<$SalesTable, Sale> {
lib/core/database/app_database.g.dart:3061:class Sale extends DataClass implements Insertable<Sale> {
lib/core/database/app_database.g.dart:3581:class SaleItem extends DataClass implements Insertable<SaleItem> {
lib/core/database/app_database.g.dart:4095:class Purchase extends DataClass implements Insertable<Purchase> {
lib/core/database/app_database.g.dart:4684:class PurchaseItem extends DataClass implements Insertable<PurchaseItem> {
lib/core/database/app_database.g.dart:5539:class $$BusinessesTableTableManager extends RootTableManager<
lib/core/database/app_database.g.dart:6070:class $$ProfilesTableTableManager extends RootTableManager<
lib/core/database/app_database.g.dart:6477:class $$CategoriesTableTableManager extends RootTableManager<
lib/core/database/app_database.g.dart:6891:class $$CustomersTableTableManager extends RootTableManager<
lib/core/database/app_database.g.dart:7516:class $$ProductsTableTableManager extends RootTableManager<
lib/core/database/app_database.g.dart:7814:class $$SalesTableFilterComposer extends Composer<_$AppDatabase, $SalesTable> {
lib/core/database/app_database.g.dart:8141:class $$SalesTableTableManager extends RootTableManager<
lib/core/database/app_database.g.dart:8574:class $$SaleItemsTableTableManager extends RootTableManager<
lib/core/database/app_database.g.dart:9087:class $$PurchasesTableTableManager extends RootTableManager<
lib/core/database/app_database.g.dart:9526:class $$PurchaseItemsTableTableManager extends RootTableManager<

## 5. Columnas de sync/local status

lib/core/database/app_database.dart:246:  int get schemaVersion => 1;
lib/core/database/app_database.g.dart:87:      'deleted_at', aliasedName, true,
lib/core/database/app_database.g.dart:91:      GeneratedColumn<int>('sync_status', aliasedName, false,
lib/core/database/app_database.g.dart:173:    if (data.containsKey('deleted_at')) {
lib/core/database/app_database.g.dart:175:          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
lib/core/database/app_database.g.dart:209:          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
lib/core/database/app_database.g.dart:212:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
lib/core/database/app_database.g.dart:278:      map['deleted_at'] = Variable<DateTime>(deletedAt);
lib/core/database/app_database.g.dart:281:      map['sync_status'] = Variable<int>(
lib/core/database/app_database.g.dart:539:      if (deletedAt != null) 'deleted_at': deletedAt,
lib/core/database/app_database.g.dart:540:      if (syncStatus != null) 'sync_status': syncStatus,
lib/core/database/app_database.g.dart:615:      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
lib/core/database/app_database.g.dart:618:      map['sync_status'] = Variable<int>(
lib/core/database/app_database.g.dart:704:      GeneratedColumn<int>('sync_status', aliasedName, false,
lib/core/database/app_database.g.dart:786:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
lib/core/database/app_database.g.dart:834:      map['sync_status'] =
lib/core/database/app_database.g.dart:1005:      if (syncStatus != null) 'sync_status': syncStatus,
lib/core/database/app_database.g.dart:1058:      map['sync_status'] = Variable<int>(
lib/core/database/app_database.g.dart:1135:      'deleted_at', aliasedName, true,
lib/core/database/app_database.g.dart:1139:      GeneratedColumn<int>('sync_status', aliasedName, false,
lib/core/database/app_database.g.dart:1196:    if (data.containsKey('deleted_at')) {
lib/core/database/app_database.g.dart:1198:          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
lib/core/database/app_database.g.dart:1222:          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
lib/core/database/app_database.g.dart:1225:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
lib/core/database/app_database.g.dart:1270:      map['deleted_at'] = Variable<DateTime>(deletedAt);
lib/core/database/app_database.g.dart:1273:      map['sync_status'] = Variable<int>(
lib/core/database/app_database.g.dart:1447:      if (deletedAt != null) 'deleted_at': deletedAt,
lib/core/database/app_database.g.dart:1448:      if (syncStatus != null) 'sync_status': syncStatus,
lib/core/database/app_database.g.dart:1498:      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
lib/core/database/app_database.g.dart:1501:      map['sync_status'] = Variable<int>(
lib/core/database/app_database.g.dart:1589:      'deleted_at', aliasedName, true,
lib/core/database/app_database.g.dart:1593:      GeneratedColumn<int>('sync_status', aliasedName, false,
lib/core/database/app_database.g.dart:1658:    if (data.containsKey('deleted_at')) {
lib/core/database/app_database.g.dart:1660:          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
lib/core/database/app_database.g.dart:1688:          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
lib/core/database/app_database.g.dart:1691:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
lib/core/database/app_database.g.dart:1746:      map['deleted_at'] = Variable<DateTime>(deletedAt);
lib/core/database/app_database.g.dart:1749:      map['sync_status'] =
lib/core/database/app_database.g.dart:1950:      if (deletedAt != null) 'deleted_at': deletedAt,
lib/core/database/app_database.g.dart:1951:      if (syncStatus != null) 'sync_status': syncStatus,
lib/core/database/app_database.g.dart:2011:      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
lib/core/database/app_database.g.dart:2014:      map['sync_status'] = Variable<int>(
lib/core/database/app_database.g.dart:2151:      'deleted_at', aliasedName, true,
lib/core/database/app_database.g.dart:2161:      GeneratedColumn<int>('sync_status', aliasedName, false,
lib/core/database/app_database.g.dart:2269:    if (data.containsKey('deleted_at')) {
lib/core/database/app_database.g.dart:2271:          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
lib/core/database/app_database.g.dart:2317:          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
lib/core/database/app_database.g.dart:2322:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
lib/core/database/app_database.g.dart:2397:      map['deleted_at'] = Variable<DateTime>(deletedAt);
lib/core/database/app_database.g.dart:2403:      map['sync_status'] =
lib/core/database/app_database.g.dart:2726:      if (deletedAt != null) 'deleted_at': deletedAt,
lib/core/database/app_database.g.dart:2728:      if (syncStatus != null) 'sync_status': syncStatus,
lib/core/database/app_database.g.dart:2820:      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
lib/core/database/app_database.g.dart:2826:      map['sync_status'] = Variable<int>(
lib/core/database/app_database.g.dart:2935:      'deleted_at', aliasedName, true,
lib/core/database/app_database.g.dart:2939:      GeneratedColumn<int>('sync_status', aliasedName, false,
lib/core/database/app_database.g.dart:3013:    if (data.containsKey('deleted_at')) {
lib/core/database/app_database.g.dart:3015:          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
lib/core/database/app_database.g.dart:3045:          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
lib/core/database/app_database.g.dart:3048:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
lib/core/database/app_database.g.dart:3106:      map['deleted_at'] = Variable<DateTime>(deletedAt);
lib/core/database/app_database.g.dart:3109:      map['sync_status'] =
lib/core/database/app_database.g.dart:3328:      if (deletedAt != null) 'deleted_at': deletedAt,
lib/core/database/app_database.g.dart:3329:      if (syncStatus != null) 'sync_status': syncStatus,
lib/core/database/app_database.g.dart:3394:      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
lib/core/database/app_database.g.dart:3397:      map['sync_status'] = Variable<int>(
lib/core/database/app_database.g.dart:3482:      GeneratedColumn<int>('sync_status', aliasedName, false,
lib/core/database/app_database.g.dart:3568:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
lib/core/database/app_database.g.dart:3614:      map['sync_status'] =
lib/core/database/app_database.g.dart:3786:      if (syncStatus != null) 'sync_status': syncStatus,
lib/core/database/app_database.g.dart:3839:      map['sync_status'] = Variable<int>(
lib/core/database/app_database.g.dart:3931:      'deleted_at', aliasedName, true,
lib/core/database/app_database.g.dart:3955:      GeneratedColumn<int>('sync_status', aliasedName, false,
lib/core/database/app_database.g.dart:4025:    if (data.containsKey('deleted_at')) {
lib/core/database/app_database.g.dart:4027:          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
lib/core/database/app_database.g.dart:4073:          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
lib/core/database/app_database.g.dart:4082:          .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
lib/core/database/app_database.g.dart:4141:      map['deleted_at'] = Variable<DateTime>(deletedAt);
lib/core/database/app_database.g.dart:4151:      map['sync_status'] =
lib/core/database/app_database.g.dart:4413:      if (deletedAt != null) 'deleted_at': deletedAt,
lib/core/database/app_database.g.dart:4417:      if (syncStatus != null) 'sync_status': syncStatus,
lib/core/database/app_database.g.dart:4483:      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
lib/core/database/app_database.g.dart:4495:      map['sync_status'] = Variable<int>(
lib/core/database/app_database.g.dart:4583:      GeneratedColumn<int>('sync_status', aliasedName, false,
lib/core/database/app_database.g.dart:4671:              .read(DriftSqlType.int, data['${effectivePrefix}sync_status'])!),
lib/core/database/app_database.g.dart:4717:      map['sync_status'] = Variable<int>(
lib/core/database/app_database.g.dart:4891:      if (syncStatus != null) 'sync_status': syncStatus,
lib/core/database/app_database.g.dart:4944:      map['sync_status'] = Variable<int>(
lib/features/catalog/application/catalog_sync_service.dart:74:          catalogVersion: response.catalogVersion,
lib/features/catalog/data/datasources/catalog_local_dao.dart:73:            and pb.deleted_at is null
lib/features/catalog/data/datasources/catalog_local_dao.dart:132:            and pb.deleted_at is null
lib/features/catalog/data/datasources/catalog_local_dao.dart:133:            and mp.deleted_at is null
lib/features/catalog/data/datasources/catalog_local_dao.dart:218:        catalog_version,
lib/features/catalog/data/datasources/catalog_local_dao.dart:219:        sync_status,
lib/features/catalog/data/datasources/catalog_local_dao.dart:220:        version,
lib/features/catalog/data/datasources/catalog_local_dao.dart:222:        deleted_at,
lib/features/catalog/data/datasources/catalog_local_dao.dart:223:        last_synced_at
lib/features/catalog/data/datasources/catalog_local_dao.dart:246:        catalog_version = excluded.catalog_version,
lib/features/catalog/data/datasources/catalog_local_dao.dart:247:        sync_status = excluded.sync_status,
lib/features/catalog/data/datasources/catalog_local_dao.dart:248:        version = excluded.version,
lib/features/catalog/data/datasources/catalog_local_dao.dart:250:        deleted_at = excluded.deleted_at,
lib/features/catalog/data/datasources/catalog_local_dao.dart:251:        last_synced_at = excluded.last_synced_at
lib/features/catalog/data/datasources/catalog_local_dao.dart:277:        Variable<int>(_int(payload['catalog_version']) ?? 1),
lib/features/catalog/data/datasources/catalog_local_dao.dart:278:        Variable<String>(_string(payload['sync_status']) ?? 'synced'),
lib/features/catalog/data/datasources/catalog_local_dao.dart:279:        Variable<int>(_int(payload['version']) ?? 1),
lib/features/catalog/data/datasources/catalog_local_dao.dart:281:        Variable<DateTime>(_dateTime(payload['deleted_at'])),
lib/features/catalog/data/datasources/catalog_local_dao.dart:309:        sync_status,
lib/features/catalog/data/datasources/catalog_local_dao.dart:310:        version,
lib/features/catalog/data/datasources/catalog_local_dao.dart:312:        deleted_at,
lib/features/catalog/data/datasources/catalog_local_dao.dart:313:        last_synced_at
lib/features/catalog/data/datasources/catalog_local_dao.dart:328:        sync_status = excluded.sync_status,
lib/features/catalog/data/datasources/catalog_local_dao.dart:329:        version = excluded.version,
lib/features/catalog/data/datasources/catalog_local_dao.dart:331:        deleted_at = excluded.deleted_at,
lib/features/catalog/data/datasources/catalog_local_dao.dart:332:        last_synced_at = excluded.last_synced_at
lib/features/catalog/data/datasources/catalog_local_dao.dart:350:        Variable<String>(_string(payload['sync_status']) ?? 'synced'),
lib/features/catalog/data/datasources/catalog_local_dao.dart:351:        Variable<int>(_int(payload['version']) ?? 1),
lib/features/catalog/data/datasources/catalog_local_dao.dart:353:        Variable<DateTime>(_dateTime(payload['deleted_at'])),
lib/features/catalog/data/datasources/catalog_local_dao.dart:362:    required int? catalogVersion,
lib/features/catalog/data/datasources/catalog_local_dao.dart:375:        last_catalog_version,
lib/features/catalog/data/datasources/catalog_local_dao.dart:387:        last_catalog_version = excluded.last_catalog_version,
lib/features/catalog/data/datasources/catalog_local_dao.dart:399:        Variable<int>(catalogVersion),
lib/features/catalog/data/datasources/catalog_local_dao.dart:540:        metadata_json,
lib/features/catalog/data/datasources/catalog_local_dao.dart:541:        local_status,
lib/features/catalog/data/datasources/catalog_local_dao.dart:596:            and local_status in ('pending', 'error')
lib/features/catalog/data/datasources/catalog_local_dao.dart:619:        local_status = 'synced',
lib/features/catalog/data/datasources/catalog_local_dao.dart:645:        local_status = 'error',
lib/features/catalog/data/models/catalog_remote_models.dart:31:    required this.catalogVersion,
lib/features/catalog/data/models/catalog_remote_models.dart:39:  final int? catalogVersion;
lib/features/catalog/data/models/catalog_remote_models.dart:63:    final catalogVersion = _int(
lib/features/catalog/data/models/catalog_remote_models.dart:64:      map['catalog_version'] ??
lib/features/catalog/data/models/catalog_remote_models.dart:65:          map['catalogVersion'] ??
lib/features/catalog/data/models/catalog_remote_models.dart:66:          map['last_catalog_version'],
lib/features/catalog/data/models/catalog_remote_models.dart:82:      catalogVersion: catalogVersion,
lib/features/catalog/data/repositories/catalog_local_repository.dart:42:    required int? catalogVersion,
lib/features/catalog/data/repositories/catalog_local_repository.dart:48:      catalogVersion: catalogVersion,
lib/features/inventory/application/inventory_product_creation_service.dart:78:      columnName: 'sync_status',
lib/features/inventory/application/inventory_product_creation_service.dart:85:      columnName: 'local_status',
lib/features/inventory/application/inventory_product_creation_service.dart:109:      'sync_status': productSyncStatus,
lib/features/inventory/application/inventory_product_creation_service.dart:110:      'local_status': productLocalStatus,
lib/features/inventory/application/inventory_product_creation_service.dart:111:      'version': 1,
lib/features/inventory/application/inventory_product_creation_service.dart:114:      'deleted_at': null,
lib/features/inventory/application/inventory_product_creation_service.dart:115:      'last_synced_at': null,
lib/features/inventory/application/inventory_product_creation_service.dart:116:      'metadata_json': {
lib/features/inventory/application/inventory_product_creation_service.dart:143:      'sync_status': 'pending_upload',
lib/features/inventory/application/inventory_product_creation_service.dart:144:      'local_status': 'dirty',
lib/features/inventory/application/inventory_product_creation_service.dart:145:      'version': 1,
lib/features/inventory/application/inventory_product_creation_service.dart:148:      'deleted_at': null,
lib/features/inventory/application/inventory_product_creation_service.dart:149:      'last_synced_at': null,

## 6. Tablas catálogo local esperadas

lib/features/catalog/data/datasources/catalog_local_dao.dart:64:          from local_product_barcodes pb
lib/features/catalog/data/datasources/catalog_local_dao.dart:67:          left join local_master_products_catalog mp
lib/features/catalog/data/datasources/catalog_local_dao.dart:126:          from local_product_barcodes pb
lib/features/catalog/data/datasources/catalog_local_dao.dart:127:          join local_master_products_catalog mp
lib/features/catalog/data/datasources/catalog_local_dao.dart:197:      insert into local_master_products_catalog (
lib/features/catalog/data/datasources/catalog_local_dao.dart:296:      insert into local_product_barcodes (
lib/features/catalog/data/datasources/catalog_local_dao.dart:369:      insert into local_catalog_sync_state (
lib/features/catalog/data/datasources/catalog_local_dao.dart:414:      insert into local_catalog_sync_state (
lib/features/catalog/data/datasources/catalog_local_dao.dart:444:      insert into local_catalog_sync_state (
lib/features/catalog/data/datasources/catalog_local_dao.dart:473:          from local_catalog_sync_state
lib/features/catalog/data/datasources/catalog_local_dao.dart:517:      insert into local_catalog_contribution_queue (
lib/features/catalog/data/datasources/catalog_local_dao.dart:594:          from local_catalog_contribution_queue
lib/features/catalog/data/datasources/catalog_local_dao.dart:617:      update local_catalog_contribution_queue
lib/features/catalog/data/datasources/catalog_local_dao.dart:643:      update local_catalog_contribution_queue
lib/features/inventory/application/inventory_product_creation_service.dart:159:        tableName: 'local_product_barcodes',

## 7. Outbox / sync mutations local

lib/features/inventory/application/inventory_product_creation_models.dart:129:      'client_mutation_id': clientMutationId,
lib/features/inventory/application/inventory_product_creation_models.dart:130:      'client_sequence': clientSequence,
lib/features/inventory/application/inventory_product_creation_models.dart:136:      'idempotency_key': idempotencyKey,

## 8. Products local columns

lib/core/database/app_database.dart:108:class Products extends Table {
lib/core/database/app_database.dart:157:  TextColumn get productId => text().nullable().references(Products, #id)();
lib/core/database/app_database.dart:199:  TextColumn get productId => text().nullable().references(Products, #id)();
lib/core/database/app_database.dart:222:    Products,
lib/core/database/app_database.g.dart:2042:class $ProductsTable extends Products with TableInfo<$ProductsTable, Product> {
lib/core/database/app_database.g.dart:2046:  $ProductsTable(this.attachedDatabase, [this._alias]);
lib/core/database/app_database.g.dart:2091:      'purchase_price', aliasedName, false,
lib/core/database/app_database.g.dart:2099:      'sale_price', aliasedName, false,
lib/core/database/app_database.g.dart:2105:      'stock_quantity', aliasedName, false,
lib/core/database/app_database.g.dart:2113:      'minimum_stock', aliasedName, false,
lib/core/database/app_database.g.dart:2165:          .withConverter<SyncStatus>($ProductsTable.$convertersyncStatus);
lib/core/database/app_database.g.dart:2190:  static const String $name = 'products';
lib/core/database/app_database.g.dart:2229:    if (data.containsKey('purchase_price')) {
lib/core/database/app_database.g.dart:2233:              data['purchase_price']!, _purchasePriceMeta));
lib/core/database/app_database.g.dart:2235:    if (data.containsKey('sale_price')) {
lib/core/database/app_database.g.dart:2237:          salePrice.isAcceptableOrUnknown(data['sale_price']!, _salePriceMeta));
lib/core/database/app_database.g.dart:2241:    if (data.containsKey('stock_quantity')) {
lib/core/database/app_database.g.dart:2245:              data['stock_quantity']!, _stockQuantityMeta));
lib/core/database/app_database.g.dart:2247:    if (data.containsKey('minimum_stock')) {
lib/core/database/app_database.g.dart:2251:              data['minimum_stock']!, _minimumStockMeta));
lib/core/database/app_database.g.dart:2301:          .read(DriftSqlType.double, data['${effectivePrefix}purchase_price'])!,
lib/core/database/app_database.g.dart:2303:          .read(DriftSqlType.double, data['${effectivePrefix}sale_price'])!,
lib/core/database/app_database.g.dart:2305:          .read(DriftSqlType.int, data['${effectivePrefix}stock_quantity'])!,
lib/core/database/app_database.g.dart:2307:          .read(DriftSqlType.int, data['${effectivePrefix}minimum_stock'])!,
lib/core/database/app_database.g.dart:2320:      syncStatus: $ProductsTable.$convertersyncStatus.fromSql(attachedDatabase
lib/core/database/app_database.g.dart:2327:  $ProductsTable createAlias(String alias) {
lib/core/database/app_database.g.dart:2328:    return $ProductsTable(attachedDatabase, alias);
lib/core/database/app_database.g.dart:2388:    map['purchase_price'] = Variable<double>(purchasePrice);
lib/core/database/app_database.g.dart:2389:    map['sale_price'] = Variable<double>(salePrice);
lib/core/database/app_database.g.dart:2390:    map['stock_quantity'] = Variable<int>(stockQuantity);
lib/core/database/app_database.g.dart:2391:    map['minimum_stock'] = Variable<int>(minimumStock);
lib/core/database/app_database.g.dart:2404:          Variable<int>($ProductsTable.$convertersyncStatus.toSql(syncStatus));
lib/core/database/app_database.g.dart:2409:  ProductsCompanion toCompanion(bool nullToAbsent) {
lib/core/database/app_database.g.dart:2410:    return ProductsCompanion(
lib/core/database/app_database.g.dart:2463:      syncStatus: $ProductsTable.$convertersyncStatus
lib/core/database/app_database.g.dart:2488:          .toJson<int>($ProductsTable.$convertersyncStatus.toJson(syncStatus)),
lib/core/database/app_database.g.dart:2530:  Product copyWithCompanion(ProductsCompanion data) {
lib/core/database/app_database.g.dart:2630:class ProductsCompanion extends UpdateCompanion<Product> {
lib/core/database/app_database.g.dart:2649:  const ProductsCompanion({
lib/core/database/app_database.g.dart:2669:  ProductsCompanion.insert({
lib/core/database/app_database.g.dart:2718:      if (purchasePrice != null) 'purchase_price': purchasePrice,
lib/core/database/app_database.g.dart:2719:      if (salePrice != null) 'sale_price': salePrice,
lib/core/database/app_database.g.dart:2720:      if (stockQuantity != null) 'stock_quantity': stockQuantity,
lib/core/database/app_database.g.dart:2721:      if (minimumStock != null) 'minimum_stock': minimumStock,
lib/core/database/app_database.g.dart:2733:  ProductsCompanion copyWith(
lib/core/database/app_database.g.dart:2752:    return ProductsCompanion(
lib/core/database/app_database.g.dart:2796:      map['purchase_price'] = Variable<double>(purchasePrice.value);
lib/core/database/app_database.g.dart:2799:      map['sale_price'] = Variable<double>(salePrice.value);
lib/core/database/app_database.g.dart:2802:      map['stock_quantity'] = Variable<int>(stockQuantity.value);
lib/core/database/app_database.g.dart:2805:      map['minimum_stock'] = Variable<int>(minimumStock.value);
lib/core/database/app_database.g.dart:2827:          $ProductsTable.$convertersyncStatus.toSql(syncStatus.value));
lib/core/database/app_database.g.dart:2837:    return (StringBuffer('ProductsCompanion(')
lib/core/database/app_database.g.dart:3453:          GeneratedColumn.constraintIsAlways('REFERENCES products (id)'));
lib/core/database/app_database.g.dart:4554:          GeneratedColumn.constraintIsAlways('REFERENCES products (id)'));
lib/core/database/app_database.g.dart:4977:  late final $ProductsTable products = $ProductsTable(this);
lib/core/database/app_database.g.dart:4998:        products,
lib/core/database/app_database.g.dart:5088:  static MultiTypedResultKey<$ProductsTable, List<Product>> _productsRefsTable(
lib/core/database/app_database.g.dart:5090:      MultiTypedResultKey.fromTable(db.products,
lib/core/database/app_database.g.dart:5092:              $_aliasNameGenerator(db.businesses.id, db.products.businessId));
lib/core/database/app_database.g.dart:5094:  $$ProductsTableProcessedTableManager get productsRefs {
lib/core/database/app_database.g.dart:5095:    final manager = $$ProductsTableTableManager($_db, $_db.products)
lib/core/database/app_database.g.dart:5098:    final cache = $_typedResult.readTableOrNull(_productsRefsTable($_db));
lib/core/database/app_database.g.dart:5248:  Expression<bool> productsRefs(
lib/core/database/app_database.g.dart:5249:      Expression<bool> Function($$ProductsTableFilterComposer f) f) {
lib/core/database/app_database.g.dart:5250:    final $$ProductsTableFilterComposer composer = $composerBuilder(
lib/core/database/app_database.g.dart:5253:        referencedTable: $db.products,
lib/core/database/app_database.g.dart:5258:            $$ProductsTableFilterComposer(
lib/core/database/app_database.g.dart:5260:              $table: $db.products,
lib/core/database/app_database.g.dart:5475:  Expression<T> productsRefs<T extends Object>(
lib/core/database/app_database.g.dart:5476:      Expression<T> Function($$ProductsTableAnnotationComposer a) f) {
lib/core/database/app_database.g.dart:5477:    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
lib/core/database/app_database.g.dart:5480:        referencedTable: $db.products,
lib/core/database/app_database.g.dart:5485:            $$ProductsTableAnnotationComposer(
lib/core/database/app_database.g.dart:5487:              $table: $db.products,
lib/core/database/app_database.g.dart:5554:        bool productsRefs,
lib/core/database/app_database.g.dart:5641:              productsRefs = false,
lib/core/database/app_database.g.dart:5650:                if (productsRefs) db.products,
lib/core/database/app_database.g.dart:5696:                  if (productsRefs)
lib/core/database/app_database.g.dart:5701:                            $$BusinessesTableReferences._productsRefsTable(db),
lib/core/database/app_database.g.dart:5704:                                .productsRefs,
lib/core/database/app_database.g.dart:5756:        bool productsRefs,
lib/core/database/app_database.g.dart:6263:  static MultiTypedResultKey<$ProductsTable, List<Product>> _productsRefsTable(
lib/core/database/app_database.g.dart:6265:      MultiTypedResultKey.fromTable(db.products,
lib/core/database/app_database.g.dart:6267:              $_aliasNameGenerator(db.categories.id, db.products.categoryId));
lib/core/database/app_database.g.dart:6269:  $$ProductsTableProcessedTableManager get productsRefs {
lib/core/database/app_database.g.dart:6270:    final manager = $$ProductsTableTableManager($_db, $_db.products)
lib/core/database/app_database.g.dart:6273:    final cache = $_typedResult.readTableOrNull(_productsRefsTable($_db));
lib/core/database/app_database.g.dart:6331:  Expression<bool> productsRefs(
lib/core/database/app_database.g.dart:6332:      Expression<bool> Function($$ProductsTableFilterComposer f) f) {
lib/core/database/app_database.g.dart:6333:    final $$ProductsTableFilterComposer composer = $composerBuilder(
lib/core/database/app_database.g.dart:6336:        referencedTable: $db.products,
lib/core/database/app_database.g.dart:6341:            $$ProductsTableFilterComposer(
lib/core/database/app_database.g.dart:6343:              $table: $db.products,
lib/core/database/app_database.g.dart:6455:  Expression<T> productsRefs<T extends Object>(
lib/core/database/app_database.g.dart:6456:      Expression<T> Function($$ProductsTableAnnotationComposer a) f) {
lib/core/database/app_database.g.dart:6457:    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
lib/core/database/app_database.g.dart:6460:        referencedTable: $db.products,
lib/core/database/app_database.g.dart:6465:            $$ProductsTableAnnotationComposer(
lib/core/database/app_database.g.dart:6467:              $table: $db.products,
lib/core/database/app_database.g.dart:6488:    PrefetchHooks Function({bool businessId, bool productsRefs})> {
lib/core/database/app_database.g.dart:6549:          prefetchHooksCallback: ({businessId = false, productsRefs = false}) {
lib/core/database/app_database.g.dart:6552:              explicitlyWatchedTables: [if (productsRefs) db.products],
lib/core/database/app_database.g.dart:6581:                  if (productsRefs)
lib/core/database/app_database.g.dart:6586:                            $$CategoriesTableReferences._productsRefsTable(db),
lib/core/database/app_database.g.dart:6589:                                .productsRefs,
lib/core/database/app_database.g.dart:6612:    PrefetchHooks Function({bool businessId, bool productsRefs})>;
lib/core/database/app_database.g.dart:7033:typedef $$ProductsTableCreateCompanionBuilder = ProductsCompanion Function({
lib/core/database/app_database.g.dart:7053:typedef $$ProductsTableUpdateCompanionBuilder = ProductsCompanion Function({
lib/core/database/app_database.g.dart:7074:final class $$ProductsTableReferences
lib/core/database/app_database.g.dart:7075:    extends BaseReferences<_$AppDatabase, $ProductsTable, Product> {
lib/core/database/app_database.g.dart:7076:  $$ProductsTableReferences(super.$_db, super.$_table, super.$_typedResult);
lib/core/database/app_database.g.dart:7080:          $_aliasNameGenerator(db.products.businessId, db.businesses.id));
lib/core/database/app_database.g.dart:7095:          $_aliasNameGenerator(db.products.categoryId, db.categories.id));
lib/core/database/app_database.g.dart:7112:                  $_aliasNameGenerator(db.products.id, db.saleItems.productId));
lib/core/database/app_database.g.dart:7127:                  db.products.id, db.purchaseItems.productId));
lib/core/database/app_database.g.dart:7139:class $$ProductsTableFilterComposer
lib/core/database/app_database.g.dart:7140:    extends Composer<_$AppDatabase, $ProductsTable> {
lib/core/database/app_database.g.dart:7141:  $$ProductsTableFilterComposer({
lib/core/database/app_database.g.dart:7279:class $$ProductsTableOrderingComposer
lib/core/database/app_database.g.dart:7280:    extends Composer<_$AppDatabase, $ProductsTable> {
lib/core/database/app_database.g.dart:7281:  $$ProductsTableOrderingComposer({
lib/core/database/app_database.g.dart:7378:class $$ProductsTableAnnotationComposer
lib/core/database/app_database.g.dart:7379:    extends Composer<_$AppDatabase, $ProductsTable> {
lib/core/database/app_database.g.dart:7380:  $$ProductsTableAnnotationComposer({
lib/core/database/app_database.g.dart:7516:class $$ProductsTableTableManager extends RootTableManager<
lib/core/database/app_database.g.dart:7518:    $ProductsTable,
lib/core/database/app_database.g.dart:7520:    $$ProductsTableFilterComposer,
lib/core/database/app_database.g.dart:7521:    $$ProductsTableOrderingComposer,
lib/core/database/app_database.g.dart:7522:    $$ProductsTableAnnotationComposer,
lib/core/database/app_database.g.dart:7523:    $$ProductsTableCreateCompanionBuilder,
lib/core/database/app_database.g.dart:7524:    $$ProductsTableUpdateCompanionBuilder,
lib/core/database/app_database.g.dart:7525:    (Product, $$ProductsTableReferences),
lib/core/database/app_database.g.dart:7532:  $$ProductsTableTableManager(_$AppDatabase db, $ProductsTable table)
lib/core/database/app_database.g.dart:7537:              $$ProductsTableFilterComposer($db: db, $table: table),
lib/core/database/app_database.g.dart:7539:              $$ProductsTableOrderingComposer($db: db, $table: table),
lib/core/database/app_database.g.dart:7541:              $$ProductsTableAnnotationComposer($db: db, $table: table),
lib/core/database/app_database.g.dart:7562:              ProductsCompanion(
lib/core/database/app_database.g.dart:7602:              ProductsCompanion.insert(
lib/core/database/app_database.g.dart:7624:                  (e.readTable(table), $$ProductsTableReferences(db, table, e)))
lib/core/database/app_database.g.dart:7655:                        $$ProductsTableReferences._businessIdTable(db),
lib/core/database/app_database.g.dart:7657:                        $$ProductsTableReferences._businessIdTable(db).id,
lib/core/database/app_database.g.dart:7665:                        $$ProductsTableReferences._categoryIdTable(db),
lib/core/database/app_database.g.dart:7667:                        $$ProductsTableReferences._categoryIdTable(db).id,
lib/core/database/app_database.g.dart:7676:                    await $_getPrefetchedData<Product, $ProductsTable,
lib/core/database/app_database.g.dart:7680:                            $$ProductsTableReferences._saleItemsRefsTable(db),
lib/core/database/app_database.g.dart:7682:                            $$ProductsTableReferences(db, table, p0)
lib/core/database/app_database.g.dart:7689:                    await $_getPrefetchedData<Product, $ProductsTable,
lib/core/database/app_database.g.dart:7692:                        referencedTable: $$ProductsTableReferences
lib/core/database/app_database.g.dart:7695:                            $$ProductsTableReferences(db, table, p0)
lib/core/database/app_database.g.dart:7708:typedef $$ProductsTableProcessedTableManager = ProcessedTableManager<
lib/core/database/app_database.g.dart:7710:    $ProductsTable,
lib/core/database/app_database.g.dart:7712:    $$ProductsTableFilterComposer,
lib/core/database/app_database.g.dart:7713:    $$ProductsTableOrderingComposer,
lib/core/database/app_database.g.dart:7714:    $$ProductsTableAnnotationComposer,
lib/core/database/app_database.g.dart:7715:    $$ProductsTableCreateCompanionBuilder,
lib/core/database/app_database.g.dart:7716:    $$ProductsTableUpdateCompanionBuilder,
lib/core/database/app_database.g.dart:7717:    (Product, $$ProductsTableReferences),
lib/core/database/app_database.g.dart:8351:  static $ProductsTable _productIdTable(_$AppDatabase db) =>
lib/core/database/app_database.g.dart:8352:      db.products.createAlias(
lib/core/database/app_database.g.dart:8353:          $_aliasNameGenerator(db.saleItems.productId, db.products.id));
lib/core/database/app_database.g.dart:8355:  $$ProductsTableProcessedTableManager? get productId {
lib/core/database/app_database.g.dart:8358:    final manager = $$ProductsTableTableManager($_db, $_db.products)
lib/core/database/app_database.g.dart:8416:  $$ProductsTableFilterComposer get productId {
lib/core/database/app_database.g.dart:8417:    final $$ProductsTableFilterComposer composer = $composerBuilder(
lib/core/database/app_database.g.dart:8420:        referencedTable: $db.products,
lib/core/database/app_database.g.dart:8425:            $$ProductsTableFilterComposer(
lib/core/database/app_database.g.dart:8427:              $table: $db.products,
lib/core/database/app_database.g.dart:8484:  $$ProductsTableOrderingComposer get productId {
lib/core/database/app_database.g.dart:8485:    final $$ProductsTableOrderingComposer composer = $composerBuilder(
lib/core/database/app_database.g.dart:8488:        referencedTable: $db.products,
lib/core/database/app_database.g.dart:8493:            $$ProductsTableOrderingComposer(
lib/core/database/app_database.g.dart:8495:              $table: $db.products,
lib/core/database/app_database.g.dart:8553:  $$ProductsTableAnnotationComposer get productId {
lib/core/database/app_database.g.dart:8554:    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
lib/core/database/app_database.g.dart:8557:        referencedTable: $db.products,
lib/core/database/app_database.g.dart:8562:            $$ProductsTableAnnotationComposer(
lib/core/database/app_database.g.dart:8564:              $table: $db.products,
lib/core/database/app_database.g.dart:9303:  static $ProductsTable _productIdTable(_$AppDatabase db) =>
lib/core/database/app_database.g.dart:9304:      db.products.createAlias(
lib/core/database/app_database.g.dart:9305:          $_aliasNameGenerator(db.purchaseItems.productId, db.products.id));
lib/core/database/app_database.g.dart:9307:  $$ProductsTableProcessedTableManager? get productId {
lib/core/database/app_database.g.dart:9310:    final manager = $$ProductsTableTableManager($_db, $_db.products)
lib/core/database/app_database.g.dart:9368:  $$ProductsTableFilterComposer get productId {
lib/core/database/app_database.g.dart:9369:    final $$ProductsTableFilterComposer composer = $composerBuilder(
lib/core/database/app_database.g.dart:9372:        referencedTable: $db.products,
lib/core/database/app_database.g.dart:9377:            $$ProductsTableFilterComposer(
lib/core/database/app_database.g.dart:9379:              $table: $db.products,
lib/core/database/app_database.g.dart:9436:  $$ProductsTableOrderingComposer get productId {
lib/core/database/app_database.g.dart:9437:    final $$ProductsTableOrderingComposer composer = $composerBuilder(
lib/core/database/app_database.g.dart:9440:        referencedTable: $db.products,
lib/core/database/app_database.g.dart:9445:            $$ProductsTableOrderingComposer(
lib/core/database/app_database.g.dart:9447:              $table: $db.products,
lib/core/database/app_database.g.dart:9505:  $$ProductsTableAnnotationComposer get productId {
lib/core/database/app_database.g.dart:9506:    final $$ProductsTableAnnotationComposer composer = $composerBuilder(
lib/core/database/app_database.g.dart:9509:        referencedTable: $db.products,
lib/core/database/app_database.g.dart:9514:            $$ProductsTableAnnotationComposer(
lib/core/database/app_database.g.dart:9516:              $table: $db.products,
lib/core/database/app_database.g.dart:9670:  $$ProductsTableTableManager get products =>
lib/core/database/app_database.g.dart:9671:      $$ProductsTableTableManager(_db, _db.products);
lib/core/database/app_database.g.dart:9742:  $ProductsTable get products => attachedDatabase.products;
lib/core/database/app_database.g.dart:9753:  $$ProductsTableTableManager get products =>
lib/core/database/app_database.g.dart:9754:      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
lib/core/database/app_database.g.dart:9763:  $ProductsTable get products => attachedDatabase.products;
lib/core/database/app_database.g.dart:9781:  $$ProductsTableTableManager get products =>
lib/core/database/app_database.g.dart:9782:      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
lib/core/database/app_database.g.dart:9792:  $ProductsTable get products => attachedDatabase.products;
lib/core/database/app_database.g.dart:9808:  $$ProductsTableTableManager get products =>
lib/core/database/app_database.g.dart:9809:      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
lib/features/inventory/application/inventory_product_creation_models.dart:41:      'master_product_id': masterProductId,
lib/features/inventory/application/inventory_product_creation_models.dart:43:      'barcode_normalized': barcodeNormalized,
lib/features/inventory/application/inventory_product_creation_models.dart:173:      'master_product_id': masterProductId,
lib/features/inventory/application/inventory_product_creation_models.dart:175:      'barcode_normalized': barcodeNormalized,
lib/features/inventory/application/inventory_product_creation_service.dart:24:    final barcodeNormalized = _string(barcodeRecord['barcode_normalized']) ??
lib/features/inventory/application/inventory_product_creation_service.dart:25:        _string(masterProduct['barcode_normalized']) ??
lib/features/inventory/application/inventory_product_creation_service.dart:76:    final productSyncStatus = await _pendingSyncValueForColumn(
lib/features/inventory/application/inventory_product_creation_service.dart:77:      tableName: 'products',
lib/features/inventory/application/inventory_product_creation_service.dart:84:      tableName: 'products',
lib/features/inventory/application/inventory_product_creation_service.dart:96:      'barcode_normalized': draft.barcodeNormalized,
lib/features/inventory/application/inventory_product_creation_service.dart:99:      'purchase_price': input.purchasePrice,
lib/features/inventory/application/inventory_product_creation_service.dart:100:      'sale_price': input.salePrice,
lib/features/inventory/application/inventory_product_creation_service.dart:101:      'stock_quantity': 0,
lib/features/inventory/application/inventory_product_creation_service.dart:102:      'minimum_stock': 0,
lib/features/inventory/application/inventory_product_creation_service.dart:106:      'master_product_id': draft.masterProductId,
lib/features/inventory/application/inventory_product_creation_service.dart:109:      'sync_status': productSyncStatus,
lib/features/inventory/application/inventory_product_creation_service.dart:135:      'master_product_id': draft.masterProductId,
lib/features/inventory/application/inventory_product_creation_service.dart:137:      'barcode_normalized': draft.barcodeNormalized,
lib/features/inventory/application/inventory_product_creation_service.dart:154:        tableName: 'products',
lib/features/inventory/application/inventory_product_creation_service.dart:196:    final productSequence = input.clientSequenceStart;
lib/features/inventory/application/inventory_product_creation_service.dart:201:        clientMutationId: '$installationId:mutation:$productSequence',
lib/features/inventory/application/inventory_product_creation_service.dart:202:        clientSequence: productSequence,
lib/features/inventory/application/inventory_product_creation_service.dart:203:        entityTable: 'products',
lib/features/inventory/application/inventory_product_creation_service.dart:209:            '$installationId:products:$productId:insert:$productSequence',
lib/features/inventory/data/datasources/product_dao.dart:3:@DriftAccessor(tables: [Products, Categories])
lib/features/inventory/data/datasources/product_dao.dart:10:  Stream<List<Product>> watchActiveProducts(String businessId) {
lib/features/inventory/data/datasources/product_dao.dart:11:    return (select(products)
lib/features/inventory/data/datasources/product_dao.dart:19:  Future<List<Product>> searchProducts(String businessId, String query) async {
lib/features/inventory/data/datasources/product_dao.dart:20:    return (select(products)
lib/features/inventory/data/datasources/product_dao.dart:29:    await into(products).insertOnConflictUpdate(companion);
lib/features/inventory/data/datasources/product_dao.dart:34:    await (update(products)..where((t) => t.id.equals(id))).write(
lib/features/inventory/data/datasources/product_dao.dart:35:      ProductsCompanion(
lib/features/inventory/data/datasources/product_dao.dart:46:  Future<List<Product>> getPendingSyncProducts(String businessId) {
lib/features/inventory/data/datasources/product_dao.dart:47:    return (select(products)
lib/features/inventory/data/datasources/purchase_dao.dart:3:@DriftAccessor(tables: [Purchases, PurchaseItems, Products])
lib/features/inventory/data/datasources/purchase_dao.dart:41:        final product = await (select(products)
lib/features/inventory/data/datasources/purchase_dao.dart:46:        await (update(products)..where((t) => t.id.equals(product.id))).write(
lib/features/inventory/data/datasources/purchase_dao.dart:47:          ProductsCompanion(

## 9. Providers relevantes

lib/core/providers/app_config_provider.dart:5:final appConfigProvider = Provider<AppConfig>((ref) {
lib/core/providers/connectivity_provider.dart:5:final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
lib/core/providers/connectivity_provider.dart:9:final isOnlineStreamProvider = StreamProvider<bool>((ref) {
lib/core/providers/connectivity_provider.dart:13:final isOnlineFutureProvider = FutureProvider<bool>((ref) {
lib/core/providers/database_provider.dart:5:final appDatabaseProvider = Provider<AppDatabase>((ref) {
lib/core/providers/device_provider.dart:6:final installationIdServiceProvider = Provider<InstallationIdService>((ref) {
lib/core/providers/device_provider.dart:10:final installationIdProvider = FutureProvider<String>((ref) {
lib/core/providers/device_provider.dart:14:final appDeviceInfoServiceProvider = Provider<AppDeviceInfoService>((ref) {
lib/core/providers/device_provider.dart:18:final appDeviceInfoProvider = FutureProvider<AppDeviceInfo>((ref) {
lib/core/supabase/supabase_client_provider.dart:4:final supabaseClientProvider = Provider<SupabaseClient>((ref) {
lib/core/supabase/supabase_client_provider.dart:8:final supabaseAuthProvider = Provider<GoTrueClient>((ref) {
lib/core/supabase/supabase_client_provider.dart:12:final currentSupabaseSessionProvider = Provider<Session?>((ref) {
lib/core/supabase/supabase_client_provider.dart:16:final currentSupabaseUserProvider = Provider<User?>((ref) {
lib/features/catalog/application/catalog_local_providers.dart:11:final catalogLocalDaoProvider = Provider<CatalogLocalDao>((ref) {
lib/features/catalog/application/catalog_local_providers.dart:16:final catalogLocalRepositoryProvider = Provider<CatalogLocalRepository>((ref) {
lib/features/catalog/application/catalog_local_providers.dart:22:    Provider<CatalogRemoteDataSource>((ref) {
lib/features/catalog/application/catalog_local_providers.dart:27:final catalogSyncServiceProvider = Provider<CatalogSyncService>((ref) {
lib/features/catalog/application/catalog_local_providers.dart:35:    Provider<CatalogBarcodeLookupService>((ref) {
lib/features/inventory/application/inventory_product_providers.dart:7:    Provider<InventoryProductCreationService>((ref) {

## 10. Tests actuales

test/core/utils/app_uuid_test.dart
test/core/utils/barcode_normalizer_test.dart
test/database_test.dart
test/features/catalog/catalog_barcode_lookup_service_test.dart
test/features/catalog/catalog_local_models_test.dart
test/features/catalog/catalog_remote_models_test.dart
test/features/inventory/inventory_product_creation_models_test.dart
test/widget_test.dart
