import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../../auth/application/authenticated_access_providers.dart';
import '../../../sync/application/operational_bootstrap_entry_providers.dart';
import '../../../sync/data/models/authorized_operational_context_models.dart';
import '../../application/business_product_creation_models.dart';
import '../../application/inventory_transfer_models.dart';
import '../../application/inventory_transfer_providers.dart';
import '../../application/inventory_product_providers.dart';
import '../../application/product_stock_balance_providers.dart';
import '../widgets/inventory_transfer_dialog.dart';

class InventoryProductStockListScreen extends ConsumerStatefulWidget {
  const InventoryProductStockListScreen({
    super.key,
    required this.businessId,
    required this.branchId,
    required this.branchName,
    this.profileId,
    this.appDeviceId,
    this.deviceInstallationId,
    this.effectivePermissions = const {},
  });

  final String businessId;
  final String branchId;
  final String branchName;
  final String? profileId;
  final String? appDeviceId;
  final String? deviceInstallationId;
  final Set<String> effectivePermissions;

  @override
  ConsumerState<InventoryProductStockListScreen> createState() =>
      _InventoryProductStockListScreenState();
}

class _InventoryProductStockListScreenState
    extends ConsumerState<InventoryProductStockListScreen> {
  final _searchController = TextEditingController();
  final _minimumStockUpdates = <String>{};
  String _searchTerm = '';
  InventoryProductStockFilter _stockFilter = InventoryProductStockFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchTerm = value;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  void _setStockFilter(InventoryProductStockFilter filter) {
    if (_stockFilter == filter) return;
    setState(() => _stockFilter = filter);
  }

  Future<void> _openTransfer({
    required Map<String, dynamic> product,
    required AuthorizedOperationalContext sourceContext,
    required List<AuthorizedOperationalContext> destinationContexts,
  }) async {
    final productId = _string(product['product_id']);
    final productName = _string(product['product_name']);
    final available = _int(product['quantity_available']);
    if (productId == null || productName == null || available <= 0) return;

    final result = await showDialog<InventoryTransferResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InventoryTransferDialog(
        businessId: widget.businessId,
        productId: productId,
        productName: productName,
        availableQuantity: available,
        sourceContext: sourceContext,
        destinationContexts: destinationContexts,
        onSubmit: ref.read(inventoryTransferServiceProvider).transfer,
      ),
    );
    if (!mounted || result == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${result.quantity} unidad(es) transferidas correctamente.',
        ),
      ),
    );
  }

  Future<void> _editMinimumStock(Map<String, dynamic> product) async {
    final productId = _string(product['product_id']);
    final profileId = widget.profileId?.trim();
    final installationId = widget.deviceInstallationId?.trim();
    if (productId == null ||
        profileId == null ||
        profileId.isEmpty ||
        installationId == null ||
        installationId.isEmpty ||
        _minimumStockUpdates.contains(productId)) {
      return;
    }

    final formKey = GlobalKey<FormState>();
    var value = _minimumStock(product['minimum_stock']).toString();
    final minimumStock = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar stock mínimo'),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: const Key('inventory-minimum-stock-field'),
            initialValue: value,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Stock mínimo',
              helperText: 'Nivel deseado para este producto.',
              border: OutlineInputBorder(),
            ),
            validator: (raw) {
              final parsed = int.tryParse((raw ?? '').trim());
              return parsed == null || parsed < 0
                  ? 'Usa un entero igual o mayor a cero.'
                  : null;
            },
            onChanged: (raw) => value = raw,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('inventory-minimum-stock-save'),
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.of(dialogContext).pop(int.parse(value.trim()));
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (!mounted || minimumStock == null) return;

    setState(() => _minimumStockUpdates.add(productId));
    BusinessProductMinimumStockUpdateResult result;
    try {
      result = await ref.read(businessProductMinimumStockUpdaterProvider)(
        BusinessProductMinimumStockUpdateInput(
          context: BusinessProductCreationContext(
            businessId: widget.businessId,
            branchId: widget.branchId,
            profileId: profileId,
            appDeviceId: widget.appDeviceId,
            deviceInstallationId: installationId,
            effectivePermissions: widget.effectivePermissions,
          ),
          productId: productId,
          minimumStock: minimumStock,
        ),
      );
    } catch (_) {
      result = const BusinessProductMinimumStockUpdateResult(
        outcome:
            BusinessProductMinimumStockUpdateOutcome.localPersistenceFailure,
        message: 'No fue posible actualizar el stock mínimo localmente.',
      );
    }
    if (!mounted) return;

    setState(() => _minimumStockUpdates.remove(productId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(
      localProductsWithStockProvider(
        ProductsWithLocalStockKey(
          businessId: widget.businessId,
          branchId: widget.branchId,
          searchTerm: _searchTerm,
          stockFilter: _stockFilter,
          limit: null,
        ),
      ),
    );
    final hasSearch = _searchTerm.trim().isNotEmpty;
    final canTransfer = widget.profileId != null &&
        widget.effectivePermissions.contains('inventory.transfer');
    final canEditMinimumStock = widget.profileId?.trim().isNotEmpty == true &&
        widget.deviceInstallationId?.trim().isNotEmpty == true &&
        widget.effectivePermissions.contains('products.update');
    final authorizedContexts = !canTransfer
        ? const <AuthorizedOperationalContext>[]
        : ref
                .watch(
                  authenticatedAccessResolverProvider(widget.profileId!),
                )
                .value
                ?.contexts ??
            const <AuthorizedOperationalContext>[];
    final branchContexts = widget.profileId == null
        ? const <AuthorizedOperationalContext>[]
        : scopedOperationalBranchContexts(
            contexts: authorizedContexts,
            profileId: widget.profileId!,
            businessId: widget.businessId,
          );
    final sourceContext = _findContext(branchContexts, widget.branchId);
    final destinationContexts = sourceContext == null ||
            !sourceContext.effectivePermissions.contains('inventory.transfer')
        ? const <AuthorizedOperationalContext>[]
        : branchContexts
            .where(
              (item) =>
                  item.branchId != sourceContext.branchId &&
                  item.effectivePermissions.contains('inventory.transfer'),
            )
            .toList(growable: false);

    return Theme(
      data: CronosTheme.light(),
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Inventario'),
              Text(
                'Sucursal: ${widget.branchName}',
                key: const Key('inventory-branch-context'),
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
        body: AppGradientBackground(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CronosSpacing.md,
                  CronosSpacing.md,
                  CronosSpacing.md,
                  0,
                ),
                child: TextField(
                  key: const Key('inventory-search-field'),
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Buscar por nombre o código',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: hasSearch
                        ? IconButton(
                            key: const Key('inventory-search-clear'),
                            tooltip: 'Limpiar búsqueda',
                            onPressed: _clearSearch,
                            icon: const Icon(Icons.clear),
                          )
                        : null,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CronosSpacing.md,
                  CronosSpacing.sm,
                  CronosSpacing.md,
                  0,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: CronosSpacing.sm,
                    children: [
                      ChoiceChip(
                        key: const Key('inventory-filter-all'),
                        label: const Text('Todos'),
                        selected:
                            _stockFilter == InventoryProductStockFilter.all,
                        onSelected: (_) => _setStockFilter(
                          InventoryProductStockFilter.all,
                        ),
                      ),
                      ChoiceChip(
                        key: const Key('inventory-filter-out-of-stock'),
                        label: const Text('Agotados'),
                        selected: _stockFilter ==
                            InventoryProductStockFilter.outOfStock,
                        onSelected: (_) => _setStockFilter(
                          InventoryProductStockFilter.outOfStock,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: productsAsync.when(
                  loading: () => const Center(
                    key: Key('inventory-loading'),
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, _) => _InventoryStateMessage(
                    key: const Key('inventory-error'),
                    icon: Icons.error_outline,
                    title: 'No se pudo cargar el inventario',
                    message: error.toString(),
                  ),
                  data: (products) {
                    if (products.isEmpty) {
                      if (hasSearch) {
                        return const _InventoryStateMessage(
                          key: Key('inventory-search-empty'),
                          icon: Icons.search_off,
                          title: 'No se encontraron productos',
                          message:
                              'Prueba con otro nombre o código del producto.',
                        );
                      }

                      if (_stockFilter ==
                          InventoryProductStockFilter.outOfStock) {
                        return const _InventoryStateMessage(
                          key: Key('inventory-out-of-stock-empty'),
                          icon: Icons.inventory_2_outlined,
                          title: 'Sin productos agotados',
                          message:
                              'La sucursal seleccionada no tiene existencias agotadas.',
                        );
                      }

                      return const _InventoryStateMessage(
                        key: Key('inventory-empty'),
                        icon: Icons.inventory_2_outlined,
                        title: 'Sin productos',
                        message:
                            'No hay productos visibles para el negocio seleccionado.',
                      );
                    }

                    return ListView.separated(
                      key: const Key('inventory-product-list'),
                      padding: const EdgeInsets.all(CronosSpacing.md),
                      itemCount: products.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: CronosSpacing.sm),
                      itemBuilder: (context, index) {
                        final product = products[index];
                        final productId =
                            _string(product['product_id']) ?? '$index';

                        return _InventoryProductCard(
                          key: Key('inventory-product-$productId'),
                          product: product,
                          isUpdatingMinimumStock:
                              _minimumStockUpdates.contains(productId),
                          onEditMinimumStock: canEditMinimumStock
                              ? () => _editMinimumStock(product)
                              : null,
                          onTransfer: sourceContext != null &&
                                  destinationContexts.isNotEmpty &&
                                  _int(product['quantity_available']) > 0
                              ? () => _openTransfer(
                                    product: product,
                                    sourceContext: sourceContext,
                                    destinationContexts: destinationContexts,
                                  )
                              : null,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InventoryProductCard extends StatelessWidget {
  const _InventoryProductCard({
    super.key,
    required this.product,
    required this.isUpdatingMinimumStock,
    this.onEditMinimumStock,
    this.onTransfer,
  });

  final Map<String, dynamic> product;
  final bool isUpdatingMinimumStock;
  final VoidCallback? onEditMinimumStock;
  final VoidCallback? onTransfer;

  @override
  Widget build(BuildContext context) {
    final name = _string(product['product_name']) ?? 'Producto sin nombre';
    final barcode = _string(product['barcode']);
    final stock = _formatQuantity(product['quantity_on_hand']);
    final averageCost = _formatAverageCost(product['stock_average_cost']);
    final minimumStock = _minimumStock(product['minimum_stock']);
    final productId = _string(product['product_id']) ?? '';
    final isOutOfStock = _int(product['quantity_on_hand']) <= 0;

    return AppGlassCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: CronosColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(CronosRadius.md),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: CronosColors.primary,
            ),
          ),
          const SizedBox(width: CronosSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (barcode != null) ...[
                  const SizedBox(height: CronosSpacing.xs),
                  Text(
                    barcode,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (isOutOfStock) ...[
                  const SizedBox(height: CronosSpacing.xs),
                  Chip(
                    key: Key('inventory-out-of-stock-$productId'),
                    avatar: const Icon(Icons.remove_shopping_cart_outlined),
                    label: const Text('Agotado'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: CronosSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Stock: $stock',
                key: Key('inventory-stock-$productId'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: CronosColors.primaryDark,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: CronosSpacing.xs),
              Text(
                'Costo prom.: $averageCost',
                key: Key('inventory-average-cost-$productId'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: CronosSpacing.xs),
              Text(
                'Mínimo: $minimumStock',
                key: Key('inventory-minimum-stock-$productId'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (onEditMinimumStock != null)
                TextButton.icon(
                  key: Key('inventory-edit-minimum-stock-$productId'),
                  onPressed: isUpdatingMinimumStock ? null : onEditMinimumStock,
                  icon: isUpdatingMinimumStock
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.edit_outlined),
                  label: Text(
                    isUpdatingMinimumStock ? 'Guardando…' : 'Editar mínimo',
                  ),
                ),
              if (onTransfer != null)
                TextButton.icon(
                  key: Key('inventory-transfer-$productId'),
                  onPressed: onTransfer,
                  icon: const Icon(Icons.swap_horiz_outlined),
                  label: const Text('Transferir'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

AuthorizedOperationalContext? _findContext(
  Iterable<AuthorizedOperationalContext> contexts,
  String branchId,
) {
  for (final context in contexts) {
    if (context.branchId == branchId) return context;
  }
  return null;
}

class _InventoryStateMessage extends StatelessWidget {
  const _InventoryStateMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(CronosSpacing.md),
        child: AppGlassCard(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: CronosSpacing.md),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: CronosSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String? _string(Object? value) {
  if (value == null) {
    return null;
  }

  final text = value.toString().trim();

  return text.isEmpty ? null : text;
}

String _formatQuantity(Object? value) {
  final quantity = value is num ? value : num.tryParse(value?.toString() ?? '');

  if (quantity == null) {
    return '0';
  }

  if (quantity == quantity.truncateToDouble()) {
    return quantity.toInt().toString();
  }

  return quantity.toString();
}

String _formatAverageCost(Object? value) {
  if (value == null) {
    return '—';
  }

  final cost = value is num ? value.toDouble() : double.tryParse('$value');

  if (cost == null || !cost.isFinite) {
    return '—';
  }

  return '\$${cost.toStringAsFixed(2)}';
}

int _minimumStock(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
