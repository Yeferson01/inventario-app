import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase/supabase_client_provider.dart';
import 'app_context_models.dart';
import 'local_sync_outbox_providers.dart';

class AppCurrentContextRequest {
  const AppCurrentContextRequest({
    required this.installationId,
    required this.isOnline,
    this.lastSyncStatus,
  });

  final String installationId;
  final bool isOnline;
  final String? lastSyncStatus;

  Map<String, dynamic> toJson() {
    return {
      'installation_id': installationId,
      'is_online': isOnline,
      'last_sync_status': lastSyncStatus,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppCurrentContextRequest &&
            runtimeType == other.runtimeType &&
            installationId == other.installationId &&
            isOnline == other.isOnline &&
            lastSyncStatus == other.lastSyncStatus;
  }

  @override
  int get hashCode {
    return Object.hash(
      installationId,
      isOnline,
      lastSyncStatus,
    );
  }
}

final appCurrentContextProvider = FutureProvider.autoDispose
    .family<AppCurrentContext?, AppCurrentContextRequest>(
  (ref, request) async {
    final profileId = ref.watch(currentSupabaseUserProvider)?.id;
    if (profileId == null) {
      return null;
    }
    final service = ref.watch(appContextServiceProvider);

    return service.loadCurrentContext(
      installationId: request.installationId,
      profileId: profileId,
      isOnline: request.isOnline,
      lastSyncStatus: request.lastSyncStatus,
    );
  },
);

class AppPermissionCheckRequest {
  const AppPermissionCheckRequest({
    required this.contextRequest,
    required this.permission,
  });

  final AppCurrentContextRequest contextRequest;
  final String permission;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppPermissionCheckRequest &&
            runtimeType == other.runtimeType &&
            contextRequest == other.contextRequest &&
            permission == other.permission;
  }

  @override
  int get hashCode {
    return Object.hash(
      contextRequest,
      permission,
    );
  }
}

final appHasPermissionProvider =
    FutureProvider.family<bool, AppPermissionCheckRequest>(
  (ref, request) async {
    final context = await ref.watch(
      appCurrentContextProvider(request.contextRequest).future,
    );

    return context?.hasPermission(request.permission) ?? false;
  },
);

class AppAnyPermissionCheckRequest {
  const AppAnyPermissionCheckRequest({
    required this.contextRequest,
    required this.permissions,
  });

  final AppCurrentContextRequest contextRequest;
  final List<String> permissions;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppAnyPermissionCheckRequest &&
            runtimeType == other.runtimeType &&
            contextRequest == other.contextRequest &&
            _listEquals(permissions, other.permissions);
  }

  @override
  int get hashCode {
    return Object.hash(
      contextRequest,
      Object.hashAll(permissions),
    );
  }
}

final appHasAnyPermissionProvider =
    FutureProvider.family<bool, AppAnyPermissionCheckRequest>(
  (ref, request) async {
    final context = await ref.watch(
      appCurrentContextProvider(request.contextRequest).future,
    );

    return context?.hasAnyPermission(request.permissions) ?? false;
  },
);

class AppAllPermissionsCheckRequest {
  const AppAllPermissionsCheckRequest({
    required this.contextRequest,
    required this.permissions,
  });

  final AppCurrentContextRequest contextRequest;
  final List<String> permissions;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AppAllPermissionsCheckRequest &&
            runtimeType == other.runtimeType &&
            contextRequest == other.contextRequest &&
            _listEquals(permissions, other.permissions);
  }

  @override
  int get hashCode {
    return Object.hash(
      contextRequest,
      Object.hashAll(permissions),
    );
  }
}

final appHasAllPermissionsProvider =
    FutureProvider.family<bool, AppAllPermissionsCheckRequest>(
  (ref, request) async {
    final context = await ref.watch(
      appCurrentContextProvider(request.contextRequest).future,
    );

    return context?.hasAllPermissions(request.permissions) ?? false;
  },
);

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }

  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) {
      return false;
    }
  }

  return true;
}
