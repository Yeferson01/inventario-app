import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../../auth/application/authenticated_access_providers.dart';
import '../../../sync/application/operational_bootstrap_entry_providers.dart';
import '../../../sync/data/models/authorized_operational_context_models.dart';
import '../../application/inventory_transfer_models.dart';
import '../../application/inventory_transfer_providers.dart';
import '../../application/product_stock_balance_providers.dart';
import '../widgets/inventory_transfer_dialog.dart';

class InventoryProductStockListScreen extends ConsumerStatefulWidget {
  const InventoryProductStockListScreen({
    super.key,
    required this.businessId,
    required this.branchId,
    required this.branchName,
    this.profileId,
    this.effectivePermissions = const {},
  });

  final String businessId;
  final String branchId;
  final String branchName;
  final String? profileId;
  final Set<String> effectivePermissions;

  @override
  ConsumerState<InventoryProductStockListScreen> createState() =>
      _InventoryProductStockListScreenState();
}

class _InventoryProductStockListScreenState
    extends ConsumerState<InventoryProductStockListScreen> {
  final _searchController = TextEditingController();
  String _searchTerm = '';

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

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(
      localProductsWithStockProvider(
        ProductsWithLocalStockKey(
          businessId: widget.businessId,
          branchId: widget.branchId,
          searchTerm: _searchTerm,
          limit: null,
        ),
      ),
    );
    final hasSearch = _searchTerm.trim().isNotEmpty;
    final canTransfer = widget.profileId != null &&
        widget.effectivePermissions.contains('inventory.transfer');
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
    this.onTransfer,
  });

  final Map<String, dynamic> product;
  final VoidCallback? onTransfer;

  @override
  Widget build(BuildContext context) {
    final name = _string(product['product_name']) ?? 'Producto sin nombre';
    final barcode = _string(product['barcode']);
    final stock = _formatQuantity(product['quantity_on_hand']);
    final averageCost = _formatAverageCost(product['stock_average_cost']);
    final productId = _string(product['product_id']) ?? '';

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

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
