import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../../../../core/utils/app_uuid.dart';
import '../models/local_recovery_models.dart';

class OperationalBootstrapSeenRecordLocalDao {
  OperationalBootstrapSeenRecordLocalDao(this._db);

  final AppDatabase _db;

  Future<void> recordSeen(SeenRecordDraft record) async {
    await _db.customStatement(
      _insertSql,
      normalizeSqliteParameters(_parameters(record)),
    );
  }

  Future<void> recordSeenBatch(List<SeenRecordDraft> records) async {
    if (records.isEmpty) {
      return;
    }

    await _db.batch((batch) {
      for (final record in records) {
        batch.customStatement(
          _insertSql,
          normalizeSqliteParameters(_parameters(record)),
        );
      }
    });
  }

  Future<bool> exists(SeenRecordDraft record) async {
    final row = await _db.customSelect(
      '''
      select 1
      from local_operational_bootstrap_seen_records
      where snapshot_id = ? and profile_id = ? and business_id = ?
        and branch_id = ? and bundle = ? and dataset = ? and entity_id = ?
      limit 1
      ''',
      variables: [
        Variable<String>(record.snapshotId),
        Variable<String>(record.profileId),
        Variable<String>(record.businessId),
        Variable<String>(record.branchId),
        Variable<String>(record.bundle),
        Variable<String>(record.dataset),
        Variable<String>(record.entityId),
      ],
      readsFrom: {_db.localOperationalBootstrapSeenRecords},
    ).getSingleOrNull();
    return row != null;
  }

  Future<List<String>> getEntityIds({
    required String snapshotId,
    required String profileId,
    required String businessId,
    required String branchId,
    required String bundle,
    required String dataset,
  }) async {
    final rows = await _db.customSelect(
      '''
      select entity_id
      from local_operational_bootstrap_seen_records
      where snapshot_id = ? and profile_id = ? and business_id = ?
        and branch_id = ? and bundle = ? and dataset = ?
      order by entity_id
      ''',
      variables: [
        Variable<String>(snapshotId),
        Variable<String>(profileId),
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(bundle),
        Variable<String>(dataset),
      ],
      readsFrom: {_db.localOperationalBootstrapSeenRecords},
    ).get();
    return rows
        .map((row) => row.read<String>('entity_id'))
        .toList(growable: false);
  }

  Future<int> deleteBySnapshot({
    required String snapshotId,
    required String profileId,
    required String businessId,
    required String branchId,
    required String bundle,
    required String dataset,
  }) {
    return _db.customUpdate(
      '''
      delete from local_operational_bootstrap_seen_records
      where snapshot_id = ? and profile_id = ? and business_id = ?
        and branch_id = ? and bundle = ? and dataset = ?
      ''',
      variables: [
        Variable<String>(snapshotId),
        Variable<String>(profileId),
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(bundle),
        Variable<String>(dataset),
      ],
      updates: {_db.localOperationalBootstrapSeenRecords},
    );
  }

  List<Object?> _parameters(SeenRecordDraft record) {
    return [
      AppUuid.v7(),
      record.snapshotId,
      record.profileId,
      record.businessId,
      record.branchId,
      record.bundle,
      record.dataset,
      record.entityId,
      DateTime.now().toUtc(),
    ];
  }

  static const _insertSql = '''
    insert into local_operational_bootstrap_seen_records (
      id, snapshot_id, profile_id, business_id, branch_id, bundle, dataset,
      entity_id, created_at
    ) values (?, ?, ?, ?, ?, ?, ?, ?, ?)
    on conflict(
      snapshot_id, profile_id, business_id, branch_id, bundle, dataset, entity_id
    ) do nothing
  ''';
}
