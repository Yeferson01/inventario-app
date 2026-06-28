import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/supabase/supabase_client_provider.dart';
import '../../application/app_e2e_local_flow_models.dart';
import '../../application/app_e2e_local_flow_provider.dart';
import '../../application/app_e2e_product_from_catalog_flow_models.dart';
import '../../application/app_e2e_product_from_catalog_flow_provider.dart';

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
  final _salePriceController = TextEditingController(text: '3500');
  final _purchasePriceController = TextEditingController(text: '0');

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
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final service = ref.read(appE2ELocalFlowServiceProvider);

      final result = await service.run(
        AppE2ELocalFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
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

  Future<void> _createProductFromCatalog({
    required bool runManualSyncAfterCreate,
  }) async {
    setState(() {
      _isRunning = true;
      _lastError = null;
    });

    try {
      final user = _requireCurrentUserId();
      final isOnline = await _isOnline();
      final packageInfo = await PackageInfo.fromPlatform();

      final service = ref.read(appE2EProductFromCatalogFlowServiceProvider);

      final result = await service.run(
        AppE2EProductFromCatalogFlowInput(
          profileId: user,
          preferredBusinessId: _optionalText(_businessIdController),
          preferredBranchId: _optionalText(_branchIdController),
          isOnline: isOnline,
          salePrice: _doubleFromController(_salePriceController),
          purchasePrice: _doubleFromController(_purchasePriceController),
          runManualSyncAfterCreate: runManualSyncAfterCreate,
          deviceName: _deviceName(),
          platform: defaultTargetPlatform.name,
          appVersion: packageInfo.version,
          osVersion: null,
          metadata: {
            'source': 'app_e2e_real_controlled_test_screen',
            'flow': 'product_from_catalog',
            'run_manual_sync_after_create': runManualSyncAfterCreate,
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
    _salePriceController.dispose();
    _purchasePriceController.dispose();
    super.dispose();
  }

  String _requireCurrentUserId() {
    final supabase = ref.read(supabaseClientProvider);
    final user = supabase.auth.currentUser;

    if (user == null) {
      throw StateError(
        'No hay usuario autenticado. Inicia sesión antes de ejecutar la prueba.',
      );
    }

    return user.id;
  }

  Future<bool> _isOnline() async {
    final connectivity = await Connectivity().checkConnectivity();

    return connectivity.any(
      (item) => item != ConnectivityResult.none,
    );
  }

  String? _optionalText(TextEditingController controller) {
    final value = controller.text.trim();

    if (value.isEmpty) {
      return null;
    }

    return value;
  }

  double _doubleFromController(TextEditingController controller) {
    final value = double.tryParse(
      controller.text.trim().replaceAll(',', '.'),
    );

    if (value == null || value < 0) {
      throw ArgumentError('Precio inválido: ${controller.text}');
    }

    return value;
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
            '6.18C.26 — Producto real desde catálogo',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Esta pantalla valida login real, contexto operativo, sync manual '
            'y creación de producto local desde catálogo con outbox.',
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
          const SizedBox(height: 12),
          TextField(
            controller: _salePriceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Precio de venta para producto de prueba',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _purchasePriceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Precio de compra para producto de prueba',
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
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: _isRunning
                ? null
                : () {
                    _createProductFromCatalog(
                      runManualSyncAfterCreate: false,
                    );
                  },
            child: const Text(
              '3. Crear producto desde catálogo + encolar outbox',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _isRunning
                ? null
                : () {
                    _createProductFromCatalog(
                      runManualSyncAfterCreate: true,
                    );
                  },
            child: const Text(
              '4. Crear producto desde catálogo + sync manual',
            ),
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
            SelectableText(
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
