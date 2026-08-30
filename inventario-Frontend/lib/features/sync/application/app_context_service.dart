import 'package:drift/drift.dart';
import '../../../core/database/app_database.dart';
import '../data/datasources/authorized_operational_context_local_dao.dart';
import 'app_context_models.dart';
import 'app_runtime_context_store.dart';
import 'app_selected_sync_context_store.dart';

class AppContextService {
  AppContextService({
    required AppDatabase database,
    required AppSelectedSyncContextStore selectedContextStore,
    required AppRuntimeContextStore runtimeContextStore,
    required AuthorizedOperationalContextLocalDao authorizationContextDao,
  })  : _db = database,
        _selectedContextStore = selectedContextStore,
        _runtimeContextStore = runtimeContextStore,
        _authorizationContextDao = authorizationContextDao;

  final AppDatabase _db;
  final AppSelectedSyncContextStore _selectedContextStore;
  final AppRuntimeContextStore _runtimeContextStore;
  final AuthorizedOperationalContextLocalDao _authorizationContextDao;

  Future<void> selectBusinessContext({
    required String businessId,
    required String profileId,
    String? branchId,
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
    required String profileId,
    required bool isOnline,
    String? lastSyncStatus,
  }) async {
    final selectedContext = await _selectedContextStore.getSelectedContext(
      profileId: profileId,
    );

    if (selectedContext == null) {
      return null;
    }

    final branchId = _string(selectedContext.branchId);
    final runtimeContext = branchId == null
        ? null
        : await _runtimeContextStore.getContext(
            businessId: selectedContext.businessId,
            branchId: branchId,
            installationId: installationId,
          );

    final matchingRuntimeContext = runtimeContext?.profileId == profileId &&
            runtimeContext?.branchId == branchId
        ? runtimeContext
        : null;

    final authorizationContext = branchId == null
        ? null
        : await _authorizationContextDao.getContextRecord(
            profileId: profileId,
            businessId: selectedContext.businessId,
            branchId: branchId,
          );

    if (authorizationContext != null) {
      final isAuthorized = authorizationContext.isActive;
      final roles =
          isAuthorized ? authorizationContext.effectiveRoles : const <String>[];
      return AppCurrentContext(
        businessId: selectedContext.businessId,
        branchId: branchId,
        profileId: profileId,
        installationId: installationId,
        appDeviceId: matchingRuntimeContext?.appDeviceId,
        roleName: roles.isEmpty ? null : roles.join(', '),
        effectiveRoles: roles,
        applicableMembershipIds: isAuthorized
            ? authorizationContext.applicableMembershipIds
            : const <String>[],
        authorizationContextReady: isAuthorized,
        authorizationValidatedAt: authorizationContext.authorizationValidatedAt,
        permissions: AppPermissionSet.fromIterable(
          isAuthorized
              ? authorizationContext.effectivePermissions
              : const <String>[],
        ),
        isOnline: isOnline,
        cashRegisterId: matchingRuntimeContext?.cashRegisterId,
        cashSessionId: matchingRuntimeContext?.cashSessionId,
        receiptSequenceId: matchingRuntimeContext?.receiptSequenceId,
        lastSyncStatus: lastSyncStatus,
      );
    }

    final membership = await _loadBestMembership(
      businessId: selectedContext.businessId,
      branchId: branchId,
      profileId: profileId,
    );

    final roleId = _string(membership?['role_id']);
    final roleName = _string(membership?['role_name']);

    final permissions = roleId == null
        ? const AppPermissionSet(<String>{})
        : await _loadPermissionsForRole(roleId);

    return AppCurrentContext(
      businessId: selectedContext.businessId,
      branchId: branchId,
      profileId: profileId,
      installationId: installationId,
      appDeviceId: matchingRuntimeContext?.appDeviceId,
      roleId: roleId,
      roleName: roleName,
      effectiveRoles: roleName == null ? const [] : [roleName],
      permissions: permissions,
      isOnline: isOnline,
      cashRegisterId: matchingRuntimeContext?.cashRegisterId,
      cashSessionId: matchingRuntimeContext?.cashSessionId,
      receiptSequenceId: matchingRuntimeContext?.receiptSequenceId,
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
