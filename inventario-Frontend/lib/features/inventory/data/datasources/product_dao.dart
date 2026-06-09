part of 'package:inventario_frontend/core/database/app_database.dart';

@DriftAccessor(tables: [Products, Categories])
class ProductDao extends DatabaseAccessor<AppDatabase> with _$ProductDaoMixin {
  ProductDao(AppDatabase db) : super(db);

  // --- Operaciones de UI (Fase 5.3) ---
  
  // Obtener todos los productos activos de un negocio
  Stream<List<Product>> watchActiveProducts(String businessId) {
    return (select(products)
          ..where((t) => t.businessId.equals(businessId))
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.status.equals('active')))
        .watch();
  }

  // Buscar productos por nombre o código de barras (POS/Inventario)
  Future<List<Product>> searchProducts(String businessId, String query) async {
    return (select(products)
          ..where((t) => t.businessId.equals(businessId))
          ..where((t) => t.deletedAt.isNull())
          ..where((t) => t.name.like('%$query%') | t.barcode.like('%$query%')))
        .get();
  }

  // Insertar o actualizar localmente (Inyecciones Offline)
  Future<void> saveProductLocal(Product companion) async {
    await into(products).insertOnConflictUpdate(companion);
  }

  // Borrado lógico (Soft Delete) para no romper la sincronización
  Future<void> softDeleteProduct(String id) async {
    await (update(products)..where((t) => t.id.equals(id))).write(
      ProductsCompanion(
        deletedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncStatus.pendingDelete),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // --- Operaciones para el Sync Engine (Fase 4) ---
  
  // Obtener cambios locales pendientes de subir a la nube
  Future<List<Product>> getPendingSyncProducts(String businessId) {
    return (select(products)
          ..where((t) => t.businessId.equals(businessId))
          ..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not()))
        .get();
  }
}