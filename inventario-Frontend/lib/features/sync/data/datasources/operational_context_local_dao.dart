import '../../../../core/database/app_database.dart';
import '../models/operational_context_pull_models.dart';

class OperationalContextLocalDao {
  OperationalContextLocalDao(this._db);

  final AppDatabase _db;

  Future<OperationalContextPullResult> applySnapshot({
    required String businessId,
    required String profileId,
    required OperationalContextSnapshot snapshot,
  }) async {
    var appliedBusinesses = 0;
    var appliedProfiles = 0;
    var appliedBranches = 0;
    var appliedBusinessMembers = 0;
    var appliedRoles = 0;
    var appliedPermissions = 0;
    var appliedRolePermissions = 0;

    await _db.transaction(() async {
      appliedBusinesses = await _upsertMany(
        tableName: 'businesses',
        records: snapshot.businesses,
      );

      appliedProfiles = await _upsertMany(
        tableName: 'profiles',
        records: snapshot.profiles,
      );

      appliedBranches = await _upsertMany(
        tableName: 'branches',
        records: snapshot.branches,
      );

      appliedRoles = await _upsertMany(
        tableName: 'roles',
        records: snapshot.roles,
      );

      appliedPermissions = await _upsertMany(
        tableName: 'permissions',
        records: snapshot.permissions,
      );

      appliedBusinessMembers = await _upsertMany(
        tableName: 'business_members',
        records: snapshot.businessMembers
            .where(
              (record) =>
                  record['business_id']?.toString() == businessId &&
                  record['profile_id']?.toString() == profileId,
            )
            .toList(growable: false),
      );

      appliedRolePermissions = await _upsertMany(
        tableName: 'role_permissions',
        records: snapshot.rolePermissions,
        conflictColumns: const ['role_id', 'permission_id'],
      );
    });

    return OperationalContextPullResult(
      businessId: businessId,
      profileId: profileId,
      appliedBusinesses: appliedBusinesses,
      appliedProfiles: appliedProfiles,
      appliedBranches: appliedBranches,
      appliedBusinessMembers: appliedBusinessMembers,
      appliedRoles: appliedRoles,
      appliedPermissions: appliedPermissions,
      appliedRolePermissions: appliedRolePermissions,
    );
  }

  Future<int> _upsertMany({
    required String tableName,
    required List<Map<String, dynamic>> records,
    List<String> conflictColumns = const ['id'],
  }) async {
    var count = 0;

    for (final record in records) {
      final didApply = await _upsertExistingColumns(
        tableName: tableName,
        values: record,
        conflictColumns: conflictColumns,
      );

      if (didApply) {
        count++;
      }
    }

    return count;
  }

  Future<bool> _upsertExistingColumns({
    required String tableName,
    required Map<String, dynamic> values,
    required List<String> conflictColumns,
  }) async {
    final columns = await _getTableColumns(tableName);

    final filtered = <String, Object?>{};

    for (final entry in values.entries) {
      if (columns.contains(entry.key)) {
        filtered[entry.key] = _normalizeSqlValue(entry.value);
      }
    }

    final hasConflictColumns = conflictColumns.every(filtered.containsKey);

    if (!hasConflictColumns) {
      return false;
    }

    if (filtered.isEmpty) {
      return false;
    }

    final columnNames = filtered.keys.toList();
    final placeholders = List.filled(columnNames.length, '?').join(', ');

    final updateColumns = columnNames
        .where((column) => !conflictColumns.contains(column))
        .toList();

    final conflictTarget = conflictColumns.join(', ');

    final updateSet = updateColumns.isEmpty
        ? conflictColumns
            .map((column) => '$column = excluded.$column')
            .join(', ')
        : updateColumns.map((column) {
            return '$column = excluded.$column';
          }).join(', ');

    final sql = '''
      insert into $tableName (${columnNames.join(', ')})
      values ($placeholders)
      on conflict($conflictTarget) do update set
        $updateSet
    ''';

    final parameters = columnNames
        .map<Object?>((column) => filtered[column])
        .toList(growable: false);

    await _db.customStatement(
      sql,
      parameters,
    );

    return true;
  }

  Object? _normalizeSqlValue(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }

    if (value is Map || value is List) {
      return value.toString();
    }

    return value;
  }

  Future<Set<String>> _getTableColumns(String tableName) async {
    final rows = await _db.customSelect('pragma table_info($tableName)').get();

    return rows.map((row) => row.data['name']).whereType<String>().toSet();
  }
}
