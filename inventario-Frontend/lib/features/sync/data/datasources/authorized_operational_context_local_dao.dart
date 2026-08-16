import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../../../../core/utils/app_uuid.dart';
import '../models/local_recovery_models.dart';

class AuthorizedOperationalContextLocalDao {
  AuthorizedOperationalContextLocalDao(this._db);

  final AppDatabase _db;

  Future<void> replaceContext(
    AuthorizedOperationalContextProjection projection,
  ) async {
    final now = DateTime.now().toUtc();

    await _db.transaction(() async {
      await _db.customStatement(
        '''
        insert into local_authorized_operational_contexts (
          id, profile_id, business_id, branch_id, effective_permissions,
          effective_roles, applicable_membership_ids,
          authorization_validated_at, snapshot_id, status, created_at,
          updated_at
        ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        on conflict(profile_id, business_id, branch_id) do update set
          effective_permissions = excluded.effective_permissions,
          effective_roles = excluded.effective_roles,
          applicable_membership_ids = excluded.applicable_membership_ids,
          authorization_validated_at = excluded.authorization_validated_at,
          snapshot_id = excluded.snapshot_id,
          status = excluded.status,
          updated_at = excluded.updated_at
        ''',
        normalizeSqliteParameters([
          AppUuid.v7(),
          projection.profileId,
          projection.businessId,
          projection.branchId,
          jsonEncode(projection.effectivePermissions),
          jsonEncode(projection.effectiveRoles),
          jsonEncode(projection.applicableMembershipIds),
          projection.authorizationValidatedAt,
          projection.snapshotId,
          projection.status,
          now,
          now,
        ]),
      );
    });
  }

  Future<Map<String, dynamic>?> getContext({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async {
    final rows = await _db
        .customSelect(
          '''
      select *
      from local_authorized_operational_contexts
      where profile_id = ? and business_id = ? and branch_id = ?
      limit 1
      ''',
          variables: _contextVariables(profileId, businessId, branchId),
          readsFrom: {_db.localAuthorizedOperationalContexts},
        )
        .get();
    return rows.isEmpty ? null : Map<String, dynamic>.from(rows.first.data);
  }

  Future<List<String>> getEffectivePermissions({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async {
    final context = await getContext(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
    );
    return _decodeStrings(context?['effective_permissions']);
  }

  Future<List<String>> getEffectiveRoles({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async {
    final context = await getContext(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
    );
    return _decodeStrings(context?['effective_roles']);
  }

  Future<bool> exists({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async {
    final context = await getContext(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
    );
    return context != null;
  }

  Future<void> invalidateContext({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async {
    final now = DateTime.now().toUtc();
    await _db.customStatement(
      '''
      update local_authorized_operational_contexts
      set status = 'invalid', updated_at = ?
      where profile_id = ? and business_id = ? and branch_id = ?
      ''',
      normalizeSqliteParameters([
        now,
        profileId,
        businessId,
        branchId,
      ]),
    );
  }

  List<Variable<String>> _contextVariables(
    String profileId,
    String businessId,
    String branchId,
  ) =>
      [
        Variable<String>(profileId),
        Variable<String>(businessId),
        Variable<String>(branchId),
      ];

  List<String> _decodeStrings(Object? value) {
    if (value is! String || value.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(value);
    if (decoded is! List) {
      return const [];
    }
    return decoded.map((item) => item.toString()).toList(growable: false);
  }
}
