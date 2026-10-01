import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';

/// Reads the materialized local profile; no network is needed on offline entry.
final dashboardUserNameProvider = FutureProvider.family<String, String>(
  (ref, profileId) async {
    final profile = await ref
        .watch(appDatabaseProvider)
        .profileDao
        .getProfileById(profileId);
    final name = profile?.fullName?.trim();
    return name == null || name.isEmpty ? 'Usuario' : name;
  },
);

String dashboardRoleLabel(Iterable<String> roles) {
  const labels = {
    'owner': 'Dueño',
    'admin': 'Administrador',
    'cashier': 'Cajero',
    'warehouse': 'Almacenista',
    'inventory': 'Inventarista',
    'viewer': 'Consulta',
    'superadmin': 'Administrador de plataforma',
    'technician': 'Técnico',
  };
  final translated = roles
      .map((role) => labels[role.trim().toLowerCase()])
      .whereType<String>()
      .toSet()
      .toList(growable: false);
  return translated.isEmpty ? 'Usuario' : translated.join(' · ');
}
