import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/logging/app_logger.dart';
import '../../application/self_service_business_creation_providers.dart';
import '../../application/self_service_business_creation_service.dart';
import '../../data/datasources/self_service_business_creation_remote_datasource.dart';

typedef SelfServiceBusinessCreated = Future<void> Function(
  SelfServiceBusinessCreationResult result,
);

class CreateBusinessScreen extends ConsumerStatefulWidget {
  const CreateBusinessScreen({
    required this.onCreated,
    required this.onCancel,
    required this.onSessionInvalid,
    super.key,
  });

  final SelfServiceBusinessCreated onCreated;
  final VoidCallback onCancel;
  final Future<void> Function() onSessionInvalid;

  @override
  ConsumerState<CreateBusinessScreen> createState() =>
      _CreateBusinessScreenState();
}

class _CreateBusinessScreenState extends ConsumerState<CreateBusinessScreen> {
  final _businessNameController = TextEditingController();
  final _branchNameController = TextEditingController(
    text: SelfServiceBusinessCreationService.defaultBranchName,
  );
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _attemptFingerprint;
  String? _idempotencyKey;

  @override
  void dispose() {
    _businessNameController.dispose();
    _branchNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final businessName = _businessNameController.text.trim();
    final branchName = _branchNameController.text.trim().isEmpty
        ? SelfServiceBusinessCreationService.defaultBranchName
        : _branchNameController.text.trim();
    if (businessName.isEmpty) {
      setState(() => _errorMessage = 'Ingresa el nombre del negocio.');
      return;
    }
    final fingerprint = '$businessName\u0000$branchName';
    if (_attemptFingerprint != fingerprint || _idempotencyKey == null) {
      _attemptFingerprint = fingerprint;
      _idempotencyKey =
          ref.read(selfServiceBusinessCreationIdempotencyKeyProvider)();
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final result = await ref.read(selfServiceBusinessCreatorProvider)(
        businessName: businessName,
        branchName: branchName,
        idempotencyKey: _idempotencyKey!,
      );
      if (!mounted) return;
      await widget.onCreated(result);
    } on SelfServiceBusinessCreationException catch (error, stackTrace) {
      AppLogger.error(
        'Self-service business creation failed',
        error: error.cause ?? error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      if (error.kind == SelfServiceBusinessCreationFailureKind.unauthorized) {
        await widget.onSessionInvalid();
        return;
      }
      setState(() {
        _isSubmitting = false;
        _errorMessage = error.message;
      });
    } catch (error, stackTrace) {
      AppLogger.error(
        'Self-service business creation failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'No fue posible crear el negocio. Intenta nuevamente.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear negocio'),
        leading: IconButton(
          key: const Key('create-business-back'),
          onPressed: _isSubmitting ? null : widget.onCancel,
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Configura tu primer negocio',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Crearemos la sucursal y la configuración operativa inicial.',
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('create-business-name'),
                    controller: _businessNameController,
                    enabled: !_isSubmitting,
                    maxLength: 255,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del negocio',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('create-business-branch-name'),
                    controller: _branchNameController,
                    enabled: !_isSubmitting,
                    maxLength: 255,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Nombre de la sucursal (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage!,
                      key: const Key('create-business-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('create-business-submit'),
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              SizedBox(width: 12),
                              Text('Creando negocio…'),
                            ],
                          )
                        : const Text('Crear negocio'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
