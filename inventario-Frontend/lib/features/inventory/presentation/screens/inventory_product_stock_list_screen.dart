import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../application/product_stock_balance_providers.dart';

class InventoryProductStockListScreen extends ConsumerWidget {
  const InventoryProductStockListScreen({
    super.key,
    required this.businessId,
    required this.branchId,
  });

  final String businessId;
  final String branchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(
      localProductsWithStockProvider(
        ProductsWithLocalStockKey(
          businessId: businessId,
          branchId: branchId,
          limit: null,
        ),
      ),
    );

    return Theme(
      data: CronosTheme.light(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Inventario'),
        ),
        body: AppGradientBackground(
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
                  final productId = _string(product['product_id']) ?? '$index';

                  return _InventoryProductCard(
                    key: Key('inventory-product-$productId'),
                    product: product,
                  );
                },
              );
            },
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
  });

  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final name = _string(product['product_name']) ?? 'Producto sin nombre';
    final barcode = _string(product['barcode']);
    final stock = _formatQuantity(product['quantity_on_hand']);

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
          Text(
            'Stock: $stock',
            key: Key('inventory-stock-${_string(product['product_id']) ?? ''}'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: CronosColors.primaryDark,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
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
