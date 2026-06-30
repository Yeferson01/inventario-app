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

  // Transacción local legacy:
  // Guarda la compra y sus ítems, pero NO modifica products.stock_quantity.
  //
  // Regla nueva:
  // - El stock se mueve únicamente con inventory_movements.
  // - El saldo visible se lee desde local_product_stock_balances.
  // - products.stock_quantity queda como campo legacy/no autoritativo.
  Future<void> insertCompletePurchase({
    required Purchase purchaseRecord,
    required List<PurchaseItem> itemsList,
  }) async {
    await transaction(() async {
      await into(purchases).insert(purchaseRecord);

      for (final item in itemsList) {
        await into(purchaseItems).insert(item);
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
