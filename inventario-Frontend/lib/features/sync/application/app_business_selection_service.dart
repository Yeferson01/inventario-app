import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import 'app_business_selection_models.dart';
import 'app_selected_sync_context_store.dart';

class AppBusinessSelectionService {
  AppBusinessSelectionService({
    required AppDatabase database,
    required AppSelectedSyncContextStore selectedContextStore,
  })  : _db = database,
        _selectedContextStore = selectedContextStore;

  final AppDatabase _db;
  final AppSelectedSyncContextStore _selectedContextStore;

  Future<List<AppBusinessSelectionOption>> getAvailableContexts({
    required String profileId,
  }) async {
    final rows = await _db.customSelect(
      '''
      select
        bm.id as membership_id,
        bm.business_id,
        coalesce(b.name, 'Negocio sin nombre') as business_name,
        bm.branch_id,
        coalesce(br.name, 'Sucursal principal') as branch_name,
        bm.profile_id,
        bm.role_id,
        coalesce(r.name, 'sin_rol') as role_name
      from business_members bm
      left join businesses b
        on b.id = bm.business_id
      left join branches br
        on br.id = bm.branch_id
      left join roles r
        on r.id = bm.role_id
      where bm.profile_id = ?
        and bm.status = 'active'
        and bm.deleted_at is null
        and b.deleted_at is null
        and (
          br.deleted_at is null
          or bm.branch_id is null
        )
      order by
        business_name asc,
        branch_name asc,
        role_name asc
      ''',
      variables: [
        Variable<String>(profileId),
      ],
    ).get();

    return rows
        .map((row) => AppBusinessSelectionOption.fromRow(row.data))
        .toList();
  }

  Future<AppBusinessSelectionResult> selectContext({
    required String profileId,
    required String businessId,
    String? branchId,
  }) async {
    final options = await getAvailableContexts(profileId: profileId);

    final selected = _findMatchingOption(
      options: options,
      businessId: businessId,
      branchId: branchId,
    );

    await _selectedContextStore.saveSelectedContext(
      AppSelectedSyncContext(
        businessId: selected.businessId,
        branchId: branchId ?? selected.branchId,
        profileId: selected.profileId,
      ),
    );

    return AppBusinessSelectionResult(
      selected: selected,
      savedBusinessId: selected.businessId,
      savedBranchId: branchId ?? selected.branchId,
      savedProfileId: selected.profileId,
    );
  }

  Future<AppBusinessSelectionOption?> getSelectedOption({
    required String profileId,
  }) async {
    final selectedContext = await _selectedContextStore.getSelectedContext(
      profileId: profileId,
    );

    if (selectedContext == null) {
      return null;
    }

    final options = await getAvailableContexts(profileId: profileId);

    try {
      return _findMatchingOption(
        options: options,
        businessId: selectedContext.businessId,
        branchId: selectedContext.branchId,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> clearSelectedContext({required String profileId}) {
    return _selectedContextStore.clearSelectedContext(profileId: profileId);
  }

  AppBusinessSelectionOption _findMatchingOption({
    required List<AppBusinessSelectionOption> options,
    required String businessId,
    required String? branchId,
  }) {
    final normalizedBusinessId = businessId.trim();
    final normalizedBranchId = branchId?.trim();

    if (normalizedBusinessId.isEmpty) {
      throw ArgumentError('businessId no puede estar vacío.');
    }

    final businessOptions = options
        .where((option) => option.businessId == normalizedBusinessId)
        .toList();

    if (businessOptions.isEmpty) {
      throw StateError(
        'El perfil actual no tiene membresía activa para este negocio.',
      );
    }

    if (normalizedBranchId != null && normalizedBranchId.isNotEmpty) {
      final branchMatches = businessOptions
          .where((option) => option.branchId == normalizedBranchId)
          .toList();

      if (branchMatches.isEmpty) {
        throw StateError(
          'El perfil actual no tiene acceso activo a esta sucursal.',
        );
      }

      return branchMatches.first;
    }

    return businessOptions.first;
  }
}
