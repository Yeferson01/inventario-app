import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/application/authenticated_access_providers.dart';
import '../../../sync/application/authorized_operational_context_providers.dart';
import '../../application/business_administration_providers.dart';
import '../../application/business_administration_submission_controllers.dart';
import '../../data/models/business_administration_models.dart';

class BusinessBranchesScreen extends ConsumerWidget {
  const BusinessBranchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(administrationCurrentContextProvider);
    return current.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _BranchesStatus(
        message: 'No fue posible cargar el contexto administrativo.',
        onRetry: () => ref.invalidate(administrationCurrentContextProvider),
      ),
      data: (appContext) {
        if (appContext == null ||
            !appContext.hasPermission('settings.branches') ||
            appContext.profileId == null) {
          return const _BranchesStatus(
            message:
                'No tienes acceso a la administración general de sucursales.',
          );
        }
        final request = BusinessBranchAdministrationRequest.fromContext(
          appContext,
        );
        final availability =
            ref.watch(businessBranchAdministrationProvider(request));
        return availability.when(
          loading: () => const _BranchesStatus(
            message: 'Verificando acceso a sucursales…',
            loading: true,
          ),
          error: (_, __) => _BranchesStatus(
            message: 'No fue posible verificar el acceso a sucursales.',
            onRetry: () => ref.invalidate(
              businessBranchAdministrationProvider(request),
            ),
          ),
          data: (result) {
            return switch (result.kind) {
              BusinessBranchAdministrationAvailabilityKind.available =>
                _buildAvailable(
                  context,
                  ref,
                  request,
                  result.branches,
                ),
              BusinessBranchAdministrationAvailabilityKind.unauthorizedScope =>
                const _BranchesStatus(
                  message:
                      'No tienes acceso a la administración general de sucursales.',
                ),
              BusinessBranchAdministrationAvailabilityKind.retryableFailure =>
                _BranchesStatus(
                  message: 'No fue posible verificar el acceso a sucursales.',
                  onRetry: () => ref.invalidate(
                    businessBranchAdministrationProvider(request),
                  ),
                ),
              BusinessBranchAdministrationAvailabilityKind.notApplicable =>
                const _BranchesStatus(
                  message:
                      'No tienes acceso a la administración general de sucursales.',
                ),
            };
          },
        );
      },
    );
  }

  Widget _buildAvailable(
    BuildContext context,
    WidgetRef ref,
    BusinessBranchAdministrationRequest request,
    List<BusinessBranchSummary> branches,
  ) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sucursales')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await showDialog<BusinessBranchCreationResult>(
            context: context,
            builder: (_) => _CreateBranchDialog(
              businessId: request.businessId,
            ),
          );
          if (created == null) return;
          ref.invalidate(businessBranchAdministrationProvider(request));
          var contextsRefreshed = true;
          try {
            await ref
                .read(authorizedOperationalContextServiceProvider)
                .listAuthorizedContexts();
            ref.invalidate(
              authenticatedAccessResolverProvider(request.profileId),
            );
          } catch (_) {
            contextsRefreshed = false;
          }
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                contextsRefreshed
                    ? 'Sucursal creada y contextos actualizados.'
                    : 'Sucursal creada. Los contextos se actualizarán al reintentar.',
              ),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('Nueva sucursal'),
      ),
      body: branches.isEmpty
          ? const Center(child: Text('No hay sucursales disponibles.'))
          : RefreshIndicator(
              onRefresh: () async => ref.refresh(
                businessBranchAdministrationProvider(request).future,
              ),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: branches.length,
                itemBuilder: (context, index) {
                  final branch = branches[index];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        branch.isPrimary
                            ? Icons.star_outline
                            : Icons.store_outlined,
                      ),
                      title: Text(branch.name),
                      subtitle: Text([
                        branch.isPrimary ? 'Principal' : null,
                        branch.status,
                        branch.address,
                        branch.runtimeReady
                            ? 'Runtime listo'
                            : 'Runtime pendiente',
                      ].whereType<String>().join(' · ')),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _CreateBranchDialog extends ConsumerStatefulWidget {
  const _CreateBranchDialog({required this.businessId});
  final String businessId;

  @override
  ConsumerState<_CreateBranchDialog> createState() =>
      _CreateBranchDialogState();
}

class _CreateBranchDialogState extends ConsumerState<_CreateBranchDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  late BranchCreationController _controller;
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = ref.read(branchCreationControllerProvider);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await _controller.submit(
        CreateBusinessBranchRequest(
          businessId: widget.businessId,
          name: _name.text,
          address: _address.text,
          phone: _phone.text,
        ),
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva sucursal'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Escribe el nombre de la sucursal.'
                    : null,
              ),
              TextFormField(
                controller: _address,
                decoration:
                    const InputDecoration(labelText: 'Dirección (opcional)'),
              ),
              TextFormField(
                controller: _phone,
                decoration:
                    const InputDecoration(labelText: 'Teléfono (opcional)'),
                keyboardType: TextInputType.phone,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Crear'),
        ),
      ],
    );
  }
}

class _BranchesStatus extends StatelessWidget {
  const _BranchesStatus({
    required this.message,
    this.loading = false,
    this.onRetry,
  });
  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Sucursales')),
        body: _InlineError(
          message: message,
          loading: loading,
          onRetry: onRetry,
        ),
      );
}

class _InlineError extends StatelessWidget {
  const _InlineError({
    required this.message,
    this.loading = false,
    this.onRetry,
  });
  final String message;
  final bool loading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              if (loading) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: onRetry, child: const Text('Reintentar')),
              ],
            ],
          ),
        ),
      );
}
