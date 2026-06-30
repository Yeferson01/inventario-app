import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/product_stock_balance_providers.dart';

class LocalProductStockBadge extends ConsumerWidget {
  const LocalProductStockBadge({
    super.key,
    required this.businessId,
    required this.branchId,
    required this.productId,
    this.compact = false,
  });

  final String businessId;
  final String branchId;
  final String productId;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockAsync = ref.watch(
      localProductStockBalanceProvider(
        ProductStockBalanceKey(
          businessId: businessId,
          branchId: branchId,
          productId: productId,
        ),
      ),
    );

    return stockAsync.when(
      data: (balance) {
        final quantityAvailable = _intValue(balance?['quantity_available']);
        final quantityOnHand = _intValue(balance?['quantity_on_hand']);

        if (balance == null) {
          return _StockText(
            label: compact ? 'Stock: —' : 'Stock disponible: —',
            muted: true,
          );
        }

        final label = compact
            ? 'Stock: $quantityAvailable'
            : 'Stock disponible: $quantityAvailable · Existencia: $quantityOnHand';

        return _StockText(
          label: label,
          muted: quantityAvailable <= 0,
        );
      },
      loading: () {
        return _StockText(
          label: compact ? 'Stock: ...' : 'Cargando stock...',
          muted: true,
        );
      },
      error: (error, stackTrace) {
        return _StockText(
          label: compact ? 'Stock: error' : 'No se pudo leer stock local',
          muted: true,
        );
      },
    );
  }

  int _intValue(Object? value) {
    if (value == null) {
      return 0;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }
}

class _StockText extends StatelessWidget {
  const _StockText({
    required this.label,
    required this.muted,
  });

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      label,
      style: theme.textTheme.bodySmall?.copyWith(
        color: muted
            ? theme.colorScheme.outline
            : theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
