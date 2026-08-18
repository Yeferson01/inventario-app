import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../models/core_context_snapshot_models.dart';

class CoreContextLocalDao {
  CoreContextLocalDao(this._db);

  final AppDatabase _db;

  Future<void> upsertBusinessAndBranch(CoreContextSnapshot context) async {
    await _db.into(_db.businesses).insertOnConflictUpdate(
          BusinessesCompanion.insert(
            id: context.business.id,
            name: context.business.name,
            businessType: Value(context.business.businessType),
            ownerName: Value(context.business.ownerName),
            phone: Value(context.business.phone),
            email: Value(context.business.email),
            address: Value(context.business.address),
            subscriptionPlan: Value(context.business.subscriptionPlan),
            status: Value(context.business.status),
            createdAt: Value(context.business.createdAt),
            updatedAt: Value(context.business.updatedAt),
            deletedAt: Value(context.business.deletedAt),
            syncStatus: const Value(SyncStatus.synced),
          ),
        );

    await _db.into(_db.branches).insertOnConflictUpdate(
          BranchesCompanion.insert(
            id: context.branch.id,
            businessId: context.branch.businessId,
            name: context.branch.name,
            address: Value(context.branch.address),
            phone: Value(context.branch.phone),
            status: Value(context.branch.status),
            syncStatus: const Value(0),
            createdAt: Value(context.branch.createdAt),
            updatedAt: Value(context.branch.updatedAt),
            deletedAt: Value(context.branch.deletedAt),
          ),
        );
  }
}
