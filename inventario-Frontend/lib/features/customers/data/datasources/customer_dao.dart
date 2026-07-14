part of 'package:inventario_frontend/core/database/app_database.dart';

@DriftAccessor(tables: [Customers])
class CustomerDao extends DatabaseAccessor<AppDatabase>
    with _$CustomerDaoMixin {
  CustomerDao(AppDatabase db) : super(db);

  // Ver lista de clientes en tiempo real en la UI reactiva
  Stream<List<Customer>> watchCustomers(String businessId) {
    return (select(customers)
          ..where((t) => t.businessId.equals(businessId))
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm(expression: t.fullName)]))
        .watch();
  }

  Future<void> insertOrUpdateCustomer(Customer customer) async {
    await into(customers).insertOnConflictUpdate(customer);
  }

  // Soft Delete del cliente
  Future<void> softDeleteCustomer(String id) async {
    await (update(customers)..where((t) => t.id.equals(id))).write(
      CustomersCompanion(
        deletedAt: Value(DateTime.now()),
        syncStatus: const Value(SyncStatus.pendingDelete),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  // Cambios pendientes de este módulo
  Future<List<Customer>> getPendingSyncCustomers(String businessId) {
    return (select(customers)
          ..where((t) => t.businessId.equals(businessId))
          ..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not()))
        .get();
  }
}
