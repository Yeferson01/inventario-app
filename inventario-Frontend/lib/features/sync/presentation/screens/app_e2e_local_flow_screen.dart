import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/app_e2e_local_flow_models.dart';
import '../../application/app_e2e_local_flow_provider.dart';

class AppE2ELocalFlowScreen extends ConsumerWidget {
  const AppE2ELocalFlowScreen({
    required this.profileId,
    required this.isOnline,
    this.runManualSync = false,
    super.key,
  });

  final String profileId;
  final bool isOnline;
  final bool runManualSync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final input = AppE2ELocalFlowInput(
      profileId: profileId,
      isOnline: isOnline,
      runManualSync: runManualSync,
      metadata: const {
        'source': 'app_e2e_local_flow_screen',
      },
    );

    final resultAsync = ref.watch(
      appE2ELocalFlowResultProvider(input),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Validación E2E local'),
      ),
      body: resultAsync.when(
        data: (result) {
          return _ResultView(result: result);
        },
        loading: () {
          return const Center(
            child: CircularProgressIndicator(),
          );
        },
        error: (error, _) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error ejecutando validación: $error',
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.result,
  });

  final AppE2ELocalFlowResult result;

  @override
  Widget build(BuildContext context) {
    final currentContext = result.currentContext;

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        _StatusTile(
          title: 'Validación local',
          value: result.successfulLocalValidation ? 'OK' : 'Pendiente',
        ),
        _StatusTile(
          title: 'Installation ID',
          value: result.installationId,
        ),
        _StatusTile(
          title: 'Contextos disponibles',
          value: result.availableContextCount.toString(),
        ),
        _StatusTile(
          title: 'Contexto seleccionado',
          value: result.didSelectContext ? 'Sí' : 'No',
        ),
        _StatusTile(
          title: 'AppCurrentContext resuelto',
          value: result.didResolveCurrentContext ? 'Sí' : 'No',
        ),
        if (currentContext != null) ...[
          const Divider(),
          _StatusTile(
            title: 'Negocio',
            value: currentContext.businessId,
          ),
          _StatusTile(
            title: 'Sucursal',
            value: currentContext.branchId ?? 'Sin sucursal',
          ),
          _StatusTile(
            title: 'Perfil',
            value: currentContext.profileId ?? 'Sin perfil',
          ),
          _StatusTile(
            title: 'Rol',
            value: currentContext.roleName ?? 'Sin rol',
          ),
          _StatusTile(
            title: 'Permisos',
            value: result.permissions.length.toString(),
          ),
        ],
        const Divider(),
        _StatusTile(
          title: 'Sync manual solicitado',
          value: result.didAttemptManualSync ? 'Sí' : 'No',
        ),
        _StatusTile(
          title: 'Sync manual ejecutado',
          value: result.didRunManualSync ? 'Sí' : 'No',
        ),
        const SizedBox(height: 16),
        Text(
          result.reason,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(title),
      subtitle: Text(value),
    );
  }
}
