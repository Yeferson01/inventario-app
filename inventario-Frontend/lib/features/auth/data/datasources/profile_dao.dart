part of 'package:inventario_frontend/core/database/app_database.dart';

@DriftAccessor(tables: [Profiles])
class ProfileDao extends DatabaseAccessor<AppDatabase> with _$ProfileDaoMixin {
  ProfileDao(AppDatabase db) : super(db);

  // Observar el perfil del usuario autenticado en la app
  Stream<Profile?> watchProfileById(String id) {
    return (select(profiles)..where((t) => t.id.equals(id))).watchSingleOrNull();
  }

  Future<Profile?> getProfileById(String id) {
    return (select(profiles)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  // Obtener todos los empleados/perfiles de un negocio (Gestión de usuarios)
  Stream<List<Profile>> watchProfilesByBusiness(String businessId) {
    return (select(profiles)
          ..where((t) => t.businessId.equals(businessId))
          ..where((t) => t.status.equals('active')))
        .watch();
  }

  Future<void> saveProfileLocal(Profile profile) async {
    await into(profiles).insertOnConflictUpdate(profile);
  }

  // Sync Engine: Obtener cambios de perfiles locales
  Future<List<Profile>> getPendingSyncProfiles() {
    return (select(profiles)..where((t) => t.syncStatus.equals(SyncStatus.synced.index).not())).get();
  }
}