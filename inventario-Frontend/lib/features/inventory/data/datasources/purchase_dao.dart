part of 'package:inventario_frontend/core/database/app_database.dart';

@DriftAccessor(tables: [Purchases, PurchaseItems, Products])
class PurchaseDao extends DatabaseAccessor<AppDatabase>
    with _$PurchaseDaoMixin {
  PurchaseDao(AppDatabase db) : super(db);

  // Observar el historial de compras en la UI
  Stream<List<Purchase>> watchPurchasesHistory(String businessId) {
    return (select(purchases)
          ..where((t) => t.businessId.equals(businessId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
          ]))
        .watch();
  }

  // Obtener los detalles de una compra específica
  Future<List<PurchaseItem>> getItemsByPurchaseId(String purchaseId) {
    return (select(purchaseItems)
          ..where((t) => t.purchaseId.equals(purchaseId)))
        .get();
  }

  // Transacción local: Guardar Compra e incrementar Stock en caliente
  Future<void> insertCompletePurchase({
    required Purchase purchaseRecord,
    required List<PurchaseItem> itemsList,
  }) async {
    await transaction(() async {
      // 1. Insertar la cabecera de la orden de compra
      await into(purchases).insert(purchaseRecord);

      // 2. Insertar cada ítem e incrementar el stock local del producto
      for (final item in itemsList) {
        await into(purchaseItems).insert(item);

        // Buscar producto local para actualizar existencias y costos
        final product = await (select(products)
              ..where((t) => t.id.equals(item.productId!)))
            .getSingle();
        final newStock = product.stockQuantity + item.quantity;

        await (update(products)..where((t) => t.id.equals(product.id))).write(
          ProductsCompanion(
            stockQuantity: Value(newStock),
            // Opcional: Actualizar el precio de compra local con el último costo unitario
            purchasePrice: Value(item.unitCost),
            syncStatus: const Value(SyncStatus.pendingUpdate),
            updatedAt: Value(DateTime.now()),
          ),
        );
      }
    });
  }

  // Sync Engine: Obtener compras pendientes de sincronizar
  Future<List<Purchase>> getPendingSyncPurchases(String businessId) {
    return (select(purchases)
          ..where((t) => t.businessId.equals(businessId))
          ..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not()))
        .get();
  }

  // Sync Engine: Obtener ítems asociados a esas compras pendientes
  Future<List<PurchaseItem>> getPendingSyncPurchaseItems(
      List<String> pendingPurchaseIds) {
    return (select(purchaseItems)
          ..where((t) => t.purchaseId.isIn(pendingPurchaseIds)))
        .get();
  }
}
