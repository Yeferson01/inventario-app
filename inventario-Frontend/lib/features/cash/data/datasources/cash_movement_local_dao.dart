import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../sync/data/datasources/authorized_operational_context_local_dao.dart';
import '../../application/cash_movement_models.dart';

class CashMovementLocalDao {
  CashMovementLocalDao(this._db);

  final AppDatabase _db;

  Future<T> transaction<T>(Future<T> Function() action) =>
      _db.transaction(action);

  Future<void> validateScope({
    required String profileId,
    required String businessId,
    required String branchId,
    required String cashRegisterId,
    required String cashSessionId,
    required String permission,
  }) async {
    final authorization =
        await AuthorizedOperationalContextLocalDao(_db).getContextRecord(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
    );
    if (authorization?.isActive != true ||
        !authorization!.effectivePermissions.contains(permission)) {
      throw const CashMovementException(CashMovementFailure.permissionDenied);
    }

    final rows = await _db.customSelect('''
      select s.id
      from cash_sessions s
      join cash_registers r on r.id = s.cash_register_id
      join branches b on b.id = s.branch_id
      join businesses bus on bus.id = s.business_id
      join profiles p on p.id = ?
      where s.id = ? and s.business_id = ? and s.branch_id = ?
        and s.cash_register_id = ? and s.status = 'open'
        and s.deleted_at is null and r.business_id = s.business_id
        and r.branch_id = s.branch_id and r.deleted_at is null
        and r.status = 'active' and b.business_id = s.business_id
        and b.status = 'active' and b.deleted_at is null
        and bus.status = 'active' and bus.deleted_at is null
        and p.status = 'active'
      limit 1
    ''', variables: [
      Variable<String>(profileId),
      Variable<String>(cashSessionId),
      Variable<String>(businessId),
      Variable<String>(branchId),
      Variable<String>(cashRegisterId),
    ]).get();
    if (rows.isEmpty) {
      throw const CashMovementException(CashMovementFailure.invalidSession);
    }
  }

  Future<LocalCashMovement?> findByKey(String businessId, String key) => (_db
          .select(_db.localCashMovements)
        ..where((row) =>
            row.businessId.equals(businessId) & row.idempotencyKey.equals(key)))
      .getSingleOrNull();

  Future<bool> outboxKeyExists(String businessId, String key) async =>
      (await _db.customSelect(
        'select id from local_sync_mutations where business_id = ? '
        'and idempotency_key = ? limit 1',
        variables: [Variable<String>(businessId), Variable<String>(key)],
      ).get())
          .isNotEmpty;

  Future<void> insert(LocalCashMovementsCompanion movement) async {
    await _db.into(_db.localCashMovements).insert(movement);
  }

  /// Returns false for a conflicting local intent; never replaces a dirty row.
  Future<bool> applyRemote(Map<String, Object?> data) async {
    String requiredString(String key) {
      final value = data[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Invalid cash movement $key');
      }
      return value;
    }

    DateTime requiredDate(String key) {
      final value = DateTime.tryParse(requiredString(key));
      if (value == null) throw FormatException('Invalid cash movement $key');
      return value.toUtc();
    }

    final id = requiredString('id');
    final businessId = requiredString('business_id');
    final branchId = requiredString('branch_id');
    final registerId = requiredString('cash_register_id');
    final sessionId = requiredString('cash_session_id');
    final direction = requiredString('direction');
    final category = requiredString('category');
    final amount = requiredString('amount');
    final match = RegExp(r'^(\d{1,12})(?:\.(\d{1,2}))?$').firstMatch(amount);
    if (match == null) {
      throw const FormatException('Invalid cash movement amount');
    }
    final cents = BigInt.parse(match.group(1)!) * BigInt.from(100) +
        BigInt.parse((match.group(2) ?? '0').padRight(2, '0'));
    final key = requiredString('idempotency_key');
    final currency = requiredString('currency');
    final sourceType = requiredString('source_type');
    final actorId = requiredString('created_by');
    final reversedId = data['reversed_movement_id'] as String?;
    final sourceId = data['source_id'] as String?;
    final note = data['note'] as String?;
    final occurredAt = requiredDate('occurred_at');
    final createdAt = requiredDate('created_at');
    final updatedAt = requiredDate('updated_at');
    final metadata = data['metadata'];
    if (metadata is! Map) {
      throw const FormatException('Invalid cash movement metadata');
    }
    final existing = await (_db.select(_db.localCashMovements)
          ..where((row) => row.id.equals(id)))
        .getSingleOrNull();
    final keyOwner = await findByKey(businessId, key);
    if (keyOwner != null && keyOwner.id != id) return false;
    if (existing != null) {
      if (existing.businessId != businessId ||
          existing.branchId != branchId ||
          existing.cashRegisterId != registerId ||
          existing.cashSessionId != sessionId ||
          existing.direction != direction ||
          existing.category != category ||
          existing.amountCents != cents ||
          existing.currency != currency ||
          existing.sourceType != sourceType ||
          existing.sourceId != sourceId ||
          existing.note != note ||
          existing.createdBy != actorId ||
          existing.reversedMovementId != reversedId ||
          existing.idempotencyKey != key ||
          !_sameJson(jsonDecode(existing.metadataJson), metadata) ||
          existing.occurredAt.toUtc() != occurredAt) {
        return false;
      }
      await markSynced(id);
      await _db.customUpdate('''
        update local_sync_mutations
        set status = 'applied', last_error = null, error_code = null,
          updated_at = ?
        where entity_table = 'cash_movements' and entity_id = ?
          and idempotency_key = ? and business_id = ? and branch_id = ?
      ''', variables: [
        Variable<DateTime>(DateTime.now().toUtc()),
        Variable<String>(id),
        Variable<String>(key),
        Variable<String>(businessId),
        Variable<String>(branchId),
      ]);
      await _db.customUpdate('''
        update local_sync_batches
        set status = 'completed', updated_at = ?
        where id in (select local_sync_batch_id from local_sync_mutations
          where entity_table = 'cash_movements' and entity_id = ?
            and idempotency_key = ?)
          and not exists (select 1 from local_sync_mutations m
            where m.local_sync_batch_id = local_sync_batches.id
              and m.status not in ('applied', 'skipped'))
      ''', variables: [
        Variable<DateTime>(DateTime.now().toUtc()),
        Variable<String>(id),
        Variable<String>(key),
      ]);
      return true;
    }
    final session = await _db.customSelect('''
      select 1 from cash_sessions s join cash_registers r
        on r.id = s.cash_register_id
      where s.id = ? and s.business_id = ? and s.branch_id = ?
        and s.cash_register_id = ? and r.business_id = ?
        and r.branch_id = ? and s.deleted_at is null and r.deleted_at is null
      limit 1
    ''', variables: [
      Variable<String>(sessionId),
      Variable<String>(businessId),
      Variable<String>(branchId),
      Variable<String>(registerId),
      Variable<String>(businessId),
      Variable<String>(branchId),
    ]).get();
    if (session.isEmpty) return false;
    if (reversedId != null &&
        await (_db.select(_db.localCashMovements)
                  ..where((row) => row.id.equals(reversedId)))
                .getSingleOrNull() ==
            null) {
      return false;
    }
    // The snapshot exposes only the actor UUID. A profile stub satisfies the
    // existing FK without granting membership or any effective permission.
    await _db.into(_db.profiles).insert(
          ProfilesCompanion.insert(id: actorId),
          mode: InsertMode.insertOrIgnore,
        );
    await insert(LocalCashMovementsCompanion.insert(
      id: id,
      businessId: businessId,
      branchId: branchId,
      cashRegisterId: registerId,
      cashSessionId: sessionId,
      direction: direction,
      category: category,
      amountCents: cents,
      currency: currency,
      sourceType: sourceType,
      sourceId: Value(sourceId),
      note: Value(note),
      occurredAt: occurredAt,
      createdBy: actorId,
      idempotencyKey: key,
      metadataJson: Value(jsonEncode(metadata)),
      reversedMovementId: Value(reversedId),
      localStatus: const Value('synced'),
      syncStatus: const Value(SyncStatus.synced),
      createdAt: createdAt,
      updatedAt: updatedAt,
    ));
    return true;
  }

  Future<void> markSynced(String id) async {
    await (_db.update(_db.localCashMovements)
          ..where((row) => row.id.equals(id)))
        .write(LocalCashMovementsCompanion(
      localStatus: const Value('synced'),
      syncStatus: const Value(SyncStatus.synced),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  Future<void> markRejected(String id) async {
    await (_db.update(_db.localCashMovements)
          ..where((row) => row.id.equals(id)))
        .write(LocalCashMovementsCompanion(
      localStatus: const Value('conflict'),
      // C1's SyncStatus enum has no conflict member; localStatus is the
      // durable conflict classification and the insert remains unapplied.
      syncStatus: const Value(SyncStatus.pendingInsert),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  Future<void> markAmbiguous(String id) async {
    await (_db.update(_db.localCashMovements)
          ..where((row) => row.id.equals(id)))
        .write(LocalCashMovementsCompanion(
      localStatus: const Value('error'),
      syncStatus: const Value(SyncStatus.pendingInsert),
      updatedAt: Value(DateTime.now().toUtc()),
    ));
  }

  bool _sameJson(Object? left, Object? right) {
    if (left is Map && right is Map) {
      return left.length == right.length &&
          left.keys.every(
            (key) => right.containsKey(key) && _sameJson(left[key], right[key]),
          );
    }
    if (left is List && right is List) {
      if (left.length != right.length) return false;
      for (var index = 0; index < left.length; index++) {
        if (!_sameJson(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }
}
