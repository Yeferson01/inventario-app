import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/supabase/supabase_client_provider.dart';
import '../../application/app_e2e_local_flow_models.dart';
import '../../application/app_e2e_local_flow_provider.dart';

class AppE2ERealControlledTestScreen extends ConsumerStatefulWidget {
  const AppE2ERealControlledTestScreen({
    super.key,
  });

  @override
  ConsumerState<AppE2ERealControlledTestScreen> createState() =>
      _AppE2ERealControlledTestScreenState();
}

class _AppE2ERealControlledTestScreenState
    extends ConsumerState<AppE2ERealControlledTestScreen> {
  final _businessIdController = TextEditingController(
    text: 'e56ea013-c8e1-4d38-86d0-ef5bc67b072b',
  );
  final _branchIdController = TextEditingController(
    text: 'a2115ea1-9104-419f-910f-30682993e6a3',
  );

  bool _isRunning = false;
  Map<String, dynamic>? _lastResult;
  Object? _lastError;

  Future<void> _run({
    required bool runManualSync,
  }) async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final supabase = ref.read(supabaseClientProvider);
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw StateError(
          'No hay usuario autenticado. Inicia sesión antes de ejecutar la prueba.',
        );
      }

      final connectivity = await Connectivity().checkConnectivity();
      final isOnline = connectivity.any(
        (item) => item != ConnectivityResult.none,
      );

      final packageInfo = await PackageInfo.fromPlatform();

      final service = ref.read(appE2ELocalFlowServiceProvider);

      final result = await service.run(
        AppE2ELocalFlowInput(
          profileId: user.id,
          preferredBusinessId: _businessIdController.text.trim().isEmpty
              ? null
              : _businessIdController.text.trim(),
          preferredBranchId: _branchIdController.text.trim().isEmpty
              ? null
              : _branchIdController.text.trim(),
          isOnline: isOnline,
          runManualSync: runManualSync,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'run_manual_sync': runManualSync,
          },
        ),
      );

      setState(() {
        _lastResult = result.toJson();
      });
    } catch (error) {
      setState(() {
        _lastError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRunning = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _businessIdController.dispose();
    _branchIdController.dispose();
    super.dispose();
  }

  String _deviceName() {
    if (kIsWeb) {
      return 'Web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android device';
      case TargetPlatform.iOS:
        return 'iOS device';
      case TargetPlatform.macOS:
        return 'macOS device';
      case TargetPlatform.windows:
        return 'Windows device';
      case TargetPlatform.linux:
        return 'Linux device';
      case TargetPlatform.fuchsia:
        return 'Fuchsia device';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(supabaseClientProvider).auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prueba real controlada'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            '6.18C.25 — E2E real controlado',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Esta pantalla valida login real, contexto operativo, permisos y sync manual controlado.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),
          _InfoTile(
            title: 'Usuario autenticado',
            value: user?.id ?? 'No autenticado',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _businessIdController,
            decoration: const InputDecoration(
              labelText: 'Business ID para pull operativo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _branchIdController,
            decoration: const InputDecoration(
              labelText: 'Branch ID preferida',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _isRunning
                ? null
                : () {
                    _run(runManualSync: false);
                  },
            child: const Text('1. Validar contexto local sin sync manual'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _isRunning
                ? null
                : () {
                    _run(runManualSync: true);
                  },
            child: const Text('2. Ejecutar sync manual controlado'),
          ),
          if (_isRunning) ...[
            const SizedBox(height: 24),
            const LinearProgressIndicator(),
          ],
          if (_lastError != null) ...[
            const SizedBox(height: 24),
            Text(
              'Error',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _lastError.toString(),
              style: const TextStyle(color: Colors.red),
            ),
          ],
          if (_lastResult != null) ...[
            const SizedBox(height: 24),
            Text(
              'Resultado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SelectableText(
              _lastResult.toString(),
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
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
