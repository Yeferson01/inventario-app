import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/app_current_context_provider.dart';

class AppPermissionGate extends ConsumerWidget {
  const AppPermissionGate({
    required this.contextRequest,
    required this.permission,
    required this.child,
    this.loading,
    this.fallback,
    super.key,
  });

  final AppCurrentContextRequest contextRequest;
  final String permission;
  final Widget child;
  final Widget? loading;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(
      appHasPermissionProvider(
        AppPermissionCheckRequest(
          contextRequest: contextRequest,
          permission: permission,
        ),
      ),
    );

    return allowed.when(
      data: (hasPermission) {
        if (hasPermission) {
          return child;
        }

        return fallback ?? const SizedBox.shrink();
      },
      loading: () => loading ?? const SizedBox.shrink(),
      error: (_, __) => fallback ?? const SizedBox.shrink(),
    );
  }
}

class AppAnyPermissionGate extends ConsumerWidget {
  const AppAnyPermissionGate({
    required this.contextRequest,
    required this.permissions,
    required this.child,
    this.loading,
    this.fallback,
    super.key,
  });

  final AppCurrentContextRequest contextRequest;
  final List<String> permissions;
  final Widget child;
  final Widget? loading;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(
      appHasAnyPermissionProvider(
        AppAnyPermissionCheckRequest(
          contextRequest: contextRequest,
          permissions: permissions,
        ),
      ),
    );

    return allowed.when(
      data: (hasPermission) {
        if (hasPermission) {
          return child;
        }

        return fallback ?? const SizedBox.shrink();
      },
      loading: () => loading ?? const SizedBox.shrink(),
      error: (_, __) => fallback ?? const SizedBox.shrink(),
    );
  }
}

class AppAllPermissionsGate extends ConsumerWidget {
  const AppAllPermissionsGate({
    required this.contextRequest,
    required this.permissions,
    required this.child,
    this.loading,
    this.fallback,
    super.key,
  });

  final AppCurrentContextRequest contextRequest;
  final List<String> permissions;
  final Widget child;
  final Widget? loading;
  final Widget? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allowed = ref.watch(
      appHasAllPermissionsProvider(
        AppAllPermissionsCheckRequest(
          contextRequest: contextRequest,
          permissions: permissions,
        ),
      ),
    );

    return allowed.when(
      data: (hasPermission) {
        if (hasPermission) {
          return child;
        }

        return fallback ?? const SizedBox.shrink();
      },
      loading: () => loading ?? const SizedBox.shrink(),
      error: (_, __) => fallback ?? const SizedBox.shrink(),
    );
  }
}
