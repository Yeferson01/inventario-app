import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import 'app_context_models.dart';
import 'app_runtime_context_store.dart';
import 'app_selected_sync_context_store.dart';

class AppContextService {
  AppContextService({
    required AppDatabase database,
    required AppSelectedSyncContextStore selectedContextStore,
    required AppRuntimeContextStore runtimeContextStore,
  })  : _db = database,
        _selectedContextStore = selectedContextStore,
        _runtimeContextStore = runtimeContextStore;

  final AppDatabase _db;
  final AppSelectedSyncContextStore _selectedContextStore;
  final AppRuntimeContextStore _runtimeContextStore;

  Future<void> selectBusinessContext({
    required String businessId,
    String? branchId,
    String? profileId,
  }) {
    return _selectedContextStore.saveSelectedContext(
      AppSelectedSyncContext(
        businessId: businessId,
        branchId: branchId,
        profileId: profileId,
      ),
    );
  }

  Future<AppCurrentContext?> loadCurrentContext({
    required String installationId,
    required bool isOnline,
    String? lastSyncStatus,
  }) async {
    final selectedContext = await _selectedContextStore.getSelectedContext();

    if (selectedContext == null) {
      return null;
    }

    final runtimeContext = await _runtimeContextStore.getContext(
      businessId: selectedContext.businessId,
      installationId: installationId,
    );

    final effectiveProfileId =
        selectedContext.profileId ?? runtimeContext?.profileId;

    final membership = await _loadBestMembership(
      businessId: selectedContext.businessId,
      branchId: selectedContext.branchId,
      profileId: effectiveProfileId,
    );

    final roleId = _string(membership?['role_id']);
    final roleName = _string(membership?['role_name']);

    final permissions = roleId == null
        ? const AppPermissionSet(<String>{})
        : await _loadPermissionsForRole(roleId);

    return AppCurrentContext(
      businessId: selectedContext.businessId,
      branchId: selectedContext.branchId ?? runtimeContext?.branchId,
      profileId: effectiveProfileId,
      installationId: installationId,
      appDeviceId: runtimeContext?.appDeviceId,
      roleId: roleId,
      roleName: roleName,
      permissions: permissions,
      isOnline: isOnline,
      cashRegisterId: runtimeContext?.cashRegisterId,
      cashSessionId: runtimeContext?.cashSessionId,
      receiptSequenceId: runtimeContext?.receiptSequenceId,
      lastSyncStatus: lastSyncStatus,
    );
  }

  Future<Map<String, dynamic>?> _loadBestMembership({
    required String businessId,
    required String? branchId,
    required String? profileId,
  }) async {
    if (profileId == null) {
      return null;
    }

    final rows = await _db.customSelect(
      '''
      select
        bm.id,
        bm.business_id,
        bm.profile_id,
        bm.branch_id,
        bm.role_id,
        bm.status,
        r.name as role_name
      from business_members bm
      left join roles r
        on r.id = bm.role_id
      where bm.business_id = ?
        and bm.profile_id = ?
        and bm.status = 'active'
        and bm.deleted_at is null
        and (
          bm.branch_id is null
          or bm.branch_id = ?
          or ? is null
        )
      order by
        case when bm.branch_id = ? then 0 else 1 end,
        bm.created_at desc
      limit 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(profileId),
        Variable<String>(branchId),
        Variable<String>(branchId),
        Variable<String>(branchId),
      ],
    ).get();

    if (rows.isEmpty) {
      return null;
    }

    return Map<String, dynamic>.from(rows.first.data);
  }

  Future<AppPermissionSet> _loadPermissionsForRole(String roleId) async {
    final rows = await _db.customSelect(
      '''
      select distinct p.key
      from permissions p
      join role_permissions rp
        on rp.permission_id = p.id
      where rp.role_id = ?
        and p.deleted_at is null
        and rp.deleted_at is null
      order by p.key asc
      ''',
      variables: [
        Variable<String>(roleId),
      ],
    ).get();

    return AppPermissionSet.fromIterable(
      rows.map((row) => row.data['key']).whereType<String>(),
    );
  }

  String? _string(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }
}
