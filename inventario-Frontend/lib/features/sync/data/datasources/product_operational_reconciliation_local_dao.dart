import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../models/product_operational_snapshot_models.dart';

class ProductOperationalReconciliationLocalDao {
  ProductOperationalReconciliationLocalDao(this._db);

  final AppDatabase _db;

  Future<Map<String, dynamic>?> getCategory(String id) {
    return _getById('categories', id);
  }

  Future<Map<String, dynamic>?> getProduct(String id) {
    return _getById('products', id);
  }

  Future<Map<String, dynamic>?> getProductBarcode(String id) {
    return _getById('local_product_barcodes', id);
  }

  Future<void> upsertCategory(
    ProductOperationalCategorySnapshot remote,
  ) async {
    await _db.into(_db.categories).insertOnConflictUpdate(
          CategoriesCompanion.insert(
            id: remote.id,
            businessId: Value(remote.businessId),
            name: remote.name,
            description: Value(remote.description),
            createdAt: Value(remote.createdAt),
            updatedAt: Value(remote.updatedAt),
            deletedAt: Value(remote.deletedAt),
            syncStatus: const Value(SyncStatus.synced),
          ),
        );
  }

  Future<void> upsertProduct(
    ProductOperationalProductSnapshot remote,
  ) async {
    if (remote.categoryId != null &&
        !await categoryBelongsToBusiness(
          categoryId: remote.categoryId!,
          businessId: remote.businessId,
        )) {
      throw StateError(
        'Product ${remote.id} references a category unavailable in its business.',
      );
    }
    await _db.into(_db.products).insertOnConflictUpdate(
          ProductsCompanion.insert(
            id: remote.id,
            businessId: Value(remote.businessId),
            categoryId: Value(remote.categoryId),
            masterProductId: Value(remote.masterProductId),
            barcode: Value(remote.barcode),
            name: remote.name,
            description: Value(remote.description),
            purchasePrice: Value(remote.purchasePrice),
            salePrice: remote.salePrice,
            stockQuantity: Value(remote.stockQuantity),
            minimumStock: Value(remote.minimumStock),
            unit: Value(remote.unit),
            status: Value(remote.status),
            createdAt: Value(remote.createdAt),
            updatedAt: Value(remote.updatedAt),
            deletedAt: Value(remote.deletedAt),
            simpleCategory: Value(remote.simpleCategory),
            syncStatus: const Value(SyncStatus.synced),
          ),
        );
  }

  Future<void> upsertProductBarcode(
    ProductOperationalBarcodeSnapshot remote, {
    bool validateProductReference = true,
  }) async {
    if (validateProductReference &&
        remote.scope == 'business' &&
        !await activeProductBelongsToBusiness(
          productId: remote.productId!,
          businessId: remote.businessId!,
        )) {
      throw StateError(
        'Product barcode ${remote.id} references an unavailable product.',
      );
    }
    final now = DateTime.now().toUtc();
    await _db.into(_db.localProductBarcodes).insertOnConflictUpdate(
          LocalProductBarcodesCompanion.insert(
            id: remote.id,
            scope: remote.scope,
            businessId: Value(remote.businessId),
            productId: Value(remote.productId),
            masterProductId: Value(remote.masterProductId),
            barcode: remote.barcode,
            barcodeNormalized: remote.barcodeNormalized,
            barcodeType: Value(remote.barcodeType),
            isPrimary: Value(remote.isPrimary),
            status: Value(remote.status),
            source: Value(remote.source),
            confidenceScore: Value(remote.confidenceScore),
            syncStatus: const Value('synced'),
            localStatus: const Value('clean'),
            version: Value(remote.version),
            createdAt: Value(remote.createdAt),
            updatedAt: Value(remote.updatedAt),
            deletedAt: Value(remote.deletedAt),
            lastSyncedAt: Value(now),
            metadataJson: Value(
              remote.metadata == null ? null : jsonEncode(remote.metadata),
            ),
          ),
        );
  }

  Future<bool> categoryBelongsToBusiness({
    required String categoryId,
    required String businessId,
  }) async {
    final row = await _db.customSelect(
      '''
      select 1 from categories
      where id = ? and business_id = ?
      limit 1
      ''',
      variables: [
        Variable<String>(categoryId),
        Variable<String>(businessId),
      ],
      readsFrom: {_db.categories},
    ).getSingleOrNull();
    return row != null;
  }

  Future<bool> activeProductBelongsToBusiness({
    required String productId,
    required String businessId,
  }) async {
    final row = await _db.customSelect(
      '''
      select 1 from products
      where id = ? and business_id = ? and deleted_at is null
      limit 1
      ''',
      variables: [
        Variable<String>(productId),
        Variable<String>(businessId),
      ],
      readsFrom: {_db.products},
    ).getSingleOrNull();
    return row != null;
  }

  Future<List<Map<String, dynamic>>> categoriesForSweep(String businessId) {
    return _rowsForSweep(
      tableName: 'categories',
      businessId: businessId,
    );
  }

  Future<List<Map<String, dynamic>>> productsForSweep(String businessId) {
    return _rowsForSweep(
      tableName: 'products',
      businessId: businessId,
    );
  }

  Future<List<Map<String, dynamic>>> businessBarcodesForSweep(
    String businessId,
  ) async {
    final rows = await _db.customSelect(
      '''
      select * from local_product_barcodes
      where scope = 'business' and business_id = ? and deleted_at is null
      order by id
      ''',
      variables: [Variable<String>(businessId)],
      readsFrom: {_db.localProductBarcodes},
    ).get();
    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }

  Future<void> softInvalidateCategory({
    required String id,
    required String businessId,
    required DateTime invalidatedAt,
  }) async {
    await (_db.update(_db.categories)
          ..where(
            (row) => row.id.equals(id) & row.businessId.equals(businessId),
          ))
        .write(
      CategoriesCompanion(
        deletedAt: Value(invalidatedAt),
        updatedAt: Value(invalidatedAt),
        syncStatus: const Value(SyncStatus.synced),
      ),
    );
  }

  Future<void> softInvalidateProduct({
    required String id,
    required String businessId,
    required DateTime invalidatedAt,
  }) async {
    await (_db.update(_db.products)
          ..where(
            (row) => row.id.equals(id) & row.businessId.equals(businessId),
          ))
        .write(
      ProductsCompanion(
        deletedAt: Value(invalidatedAt),
        updatedAt: Value(invalidatedAt),
        status: const Value('inactive'),
        syncStatus: const Value(SyncStatus.synced),
      ),
    );
  }

  Future<void> softInvalidateBusinessBarcode({
    required String id,
    required String businessId,
    required DateTime invalidatedAt,
  }) async {
    await (_db.update(_db.localProductBarcodes)
          ..where(
            (row) =>
                row.id.equals(id) &
                row.scope.equals('business') &
                row.businessId.equals(businessId),
          ))
        .write(
      LocalProductBarcodesCompanion(
        deletedAt: Value(invalidatedAt),
        updatedAt: Value(invalidatedAt),
        status: const Value('inactive'),
        syncStatus: const Value('synced'),
        localStatus: const Value('clean'),
        lastSyncedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<Map<String, dynamic>?> _getById(
    String tableName,
    String id,
  ) async {
    final row = await _db.customSelect(
      'select * from $tableName where id = ? limit 1',
      variables: [Variable<String>(id)],
    ).getSingleOrNull();
    return row == null ? null : Map<String, dynamic>.from(row.data);
  }

  Future<List<Map<String, dynamic>>> _rowsForSweep({
    required String tableName,
    required String businessId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select * from $tableName
      where business_id = ? and deleted_at is null
      order by id
      ''',
      variables: [Variable<String>(businessId)],
    ).get();
    return rows
        .map((row) => Map<String, dynamic>.from(row.data))
        .toList(growable: false);
  }
}
