part of 'package:inventario_frontend/core/database/app_database.dart';

@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase> with _$CategoryDaoMixin {
  CategoryDao(AppDatabase db) : super(db);

  // Transmitir las categorías activas a los formularios del inventario
  Stream<List<Category>> watchCategories(String businessId) {
    return (select(categories)
          ..where((t) => t.businessId.equals(businessId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  Future<void> saveCategoryLocal(Category category) async {
    await into(categories).insertOnConflictUpdate(category);
  }

  Future<void> softDeleteCategory(String id) async {
    await (update(categories)..where((t) => t.id.equals(id))).write(
      CategoriesCompanion(
        deletedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncStatus.pendingDelete),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // Sync Engine
  Future<List<Category>> getPendingSyncCategories(String businessId) {
    return (select(categories)
          ..where((t) => t.businessId.equals(businessId))
          ..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not()))
        .get();
  }
}