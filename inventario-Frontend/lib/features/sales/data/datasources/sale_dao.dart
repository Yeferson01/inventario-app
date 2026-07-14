part of 'package:inventario_frontend/core/database/app_database.dart';

@DriftAccessor(tables: [Sales, SaleItems, Products])
class SaleDao extends DatabaseAccessor<AppDatabase> with _$SaleDaoMixin {
  SaleDao(AppDatabase db) : super(db);

  // Ver historial de ventas en tiempo real
  Stream<List<Sale>> watchSalesHistory(String businessId) {
    return (select(sales)
          ..where((t) => t.businessId.equals(businessId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([
            (t) =>
                OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)
          ]))
        .watch();
  }

  // Obtener los artículos específicos de una venta seleccionada
  Future<List<SaleItem>> getItemsBySaleId(String saleId) {
    return (select(saleItems)..where((t) => t.saleId.equals(saleId))).get();
  }

  // Transacción local legacy:
  // Guarda la venta y sus ítems, pero NO modifica products.stock_quantity.
  //
  // Regla nueva:
  // - El descuento de stock debe modelarse con inventory_movements.
  // - El saldo visible se lee desde local_product_stock_balances.
  // - products.stock_quantity queda como campo legacy/no autoritativo.
  Future<void> insertCompleteSale({
    required Sale saleRecord,
    required List<SaleItem> itemsList,
  }) async {
    await transaction(() async {
      await into(sales).insert(saleRecord);

      for (final item in itemsList) {
        await into(saleItems).insert(item);
      }
    });
  }

  // Sync Engine: Obtener ventas pendientes de subir a la nube
  Future<List<Sale>> getPendingSyncSales(String businessId) {
    return (select(sales)
          ..where((t) => t.businessId.equals(businessId))
          ..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not()))
        .get();
  }

  // Sync Engine: Obtener ítems de venta pendientes vinculados a esas ventas
  Future<List<SaleItem>> getPendingSyncSaleItems(List<String> pendingSaleIds) {
    return (select(saleItems)..where((t) => t.saleId.isIn(pendingSaleIds)))
        .get();
  }
}
