import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/operational_context_pull_models.dart';

class OperationalContextRemoteDataSource {
  OperationalContextRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<OperationalContextSnapshot> pullOperationalContext({
    required String businessId,
    required String profileId,
  }) async {
    final businesses = await _selectList(
      _client.from('businesses').select().eq('id', businessId),
    );

    final profiles = await _selectList(
      _client.from('profiles').select().eq('id', profileId),
    );

    final branches = await _selectList(
      _client
          .from('branches')
          .select()
          .eq('business_id', businessId)
          .isFilter('deleted_at', null),
    );

    final businessMembers = await _selectList(
      _client
          .from('business_members')
          .select()
          .eq('business_id', businessId)
          .eq('profile_id', profileId)
          .isFilter('deleted_at', null),
    );

    final roles = await _selectList(
      _client
          .from('roles')
          .select()
          .or('business_id.eq.$businessId,business_id.is.null')
          .isFilter('deleted_at', null),
    );

    final permissions = await _selectList(
      _client.from('permissions').select(),
    );

    final rolePermissions = await _selectList(
      _client.from('role_permissions').select(),
    );

    return OperationalContextSnapshot(
      businesses: businesses,
      profiles: profiles,
      branches: branches,
      businessMembers: businessMembers,
      roles: roles,
      permissions: permissions,
      rolePermissions: rolePermissions,
    );
  }

  Future<List<Map<String, dynamic>>> _selectList(
    PostgrestFilterBuilder<dynamic> query,
  ) async {
    final result = await query;

    if (result is List) {
      return result
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    if (result is Map) {
      return [Map<String, dynamic>.from(result)];
    }

    return <Map<String, dynamic>>[];
  }
}
