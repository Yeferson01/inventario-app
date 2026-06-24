part of 'package:inventario_frontend/core/database/app_database.dart';

@DriftAccessor(tables: [Businesses])
class BusinessDao extends DatabaseAccessor<AppDatabase>
    with _$BusinessDaoMixin {
  BusinessDao(AppDatabase db) : super(db);

  // Obtener el negocio actual de manera reactiva (UI)
  Stream<Business?> watchBusinessById(String id) {
    return (select(businesses)..where((t) => t.id.equals(id)))
        .watchSingleOrNull();
  }

  // Obtener datos del negocio de forma asíncrona
  Future<Business?> getBusinessById(String id) {
    return (select(businesses)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  // Insertar o actualizar los datos del negocio (SaaS)
  Future<void> saveBusinessLocal(Business business) async {
    await into(businesses).insertOnConflictUpdate(business);
  }

  // Desactivar o marcar borrado lógico
  Future<void> softDeleteBusiness(String id) async {
    await (update(businesses)..where((t) => t.id.equals(id))).write(
      BusinessesCompanion(
        deletedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncStatus.pendingDelete),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // Sync Engine: Obtener negocios pendientes de sincronizar
  Future<List<Business>> getPendingSyncBusinesses() {
    return (select(businesses)
          ..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not()))
        .get();
  }
}
