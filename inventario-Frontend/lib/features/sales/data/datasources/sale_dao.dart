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

  // Registro atómico de checkout local con impacto inmediato al Stock local
  Future<void> insertCompleteSale({
    required Sale saleRecord,
    required List<SaleItem> itemsList,
  }) async {
    await transaction(() async {
      // 1. Guardar cabecera de la venta
      await into(sales).insert(saleRecord);

      // 2. Procesar ítems e impactar inventario
      for (final item in itemsList) {
        await into(saleItems).insert(item);

        // Descontar inventario local inmediatamente para dar feedback ágil a la UI
        final product = await (select(products)
              ..where((t) => t.id.equals(item.productId!)))
            .getSingle();
        final newStock = product.stockQuantity - item.quantity;

        await (update(products)..where((t) => t.id.equals(product.id))).write(
          ProductsCompanion(
            stockQuantity: Value(newStock),
            syncStatus: const Value(SyncStatus.pendingUpdate),
            updatedAt: Value(DateTime.now()),
          ),
        );
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
