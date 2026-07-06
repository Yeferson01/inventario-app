import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';

class PosSaleScreen extends StatefulWidget {
  const PosSaleScreen({
    super.key,
    required this.businessId,
    required this.branchId,
    required this.profileId,
    required this.deviceInstallationId,
    this.appDeviceId,
    this.cashRegisterId,
    this.cashSessionId,
    this.cashRegisterName,
  });

  final String businessId;
  final String branchId;
  final String profileId;
  final String deviceInstallationId;
  final String? appDeviceId;
  final String? cashRegisterId;
  final String? cashSessionId;
  final String? cashRegisterName;

  @override
  State<PosSaleScreen> createState() => _PosSaleScreenState();
}

class _PosSaleScreenState extends State<PosSaleScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _paymentMethod = 'cash';

  @override
  void dispose() {
    _searchController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: CronosTheme.light(),
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Nueva venta'),
              actions: [
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                  tooltip: 'Escanear código',
                ),
                IconButton(
                  onPressed: () {},
                  icon: const Icon(Icons.more_vert_outlined),
                  tooltip: 'Más opciones',
                ),
              ],
            ),
            body: AppGradientBackground(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 900;

                  if (isWide) {
                    return Padding(
                      padding: const EdgeInsets.all(CronosSpacing.md),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 7,
                            child: _ProductsSection(
                              searchController: _searchController,
                              onSearchChanged: (_) {
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: CronosSpacing.md),
                          SizedBox(
                            width: 390,
                            child: _CartSection(
                              paymentMethod: _paymentMethod,
                              onPaymentMethodChanged: (value) {
                                if (value == null) {
                                  return;
                                }

                                setState(() {
                                  _paymentMethod = value;
                                });
                              },
                              cashRegisterName: widget.cashRegisterName,
                              cashSessionId: widget.cashSessionId,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.all(CronosSpacing.md),
                    children: [
                      _ProductsSection(
                        searchController: _searchController,
                        onSearchChanged: (_) {
                          setState(() {});
                        },
                      ),
                      const SizedBox(height: CronosSpacing.md),
                      _CartSection(
                        paymentMethod: _paymentMethod,
                        onPaymentMethodChanged: (value) {
                          if (value == null) {
                            return;
                          }

                          setState(() {
                            _paymentMethod = value;
                          });
                        },
                        cashRegisterName: widget.cashRegisterName,
                        cashSessionId: widget.cashSessionId,
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProductsSection extends StatelessWidget {
  const _ProductsSection({
    required this.searchController,
    required this.onSearchChanged,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppAnimatedEntrance(
          child: _PosHeaderCard(),
        ),
        const SizedBox(height: CronosSpacing.md),
        AppGlassCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Buscar productos',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: CronosSpacing.sm),
              TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_outlined),
                  suffixIcon: Icon(Icons.qr_code_2_outlined),
                  labelText: 'Nombre, referencia o código de barras',
                  helperText: 'La búsqueda local se conecta en la fase 40C.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CronosSpacing.md),
        AppGlassCard(
          child: query.isEmpty
              ? const _EmptyProductsState()
              : _SearchPreviewState(query: query),
        ),
      ],
    );
  }
}

class _PosHeaderCard extends StatelessWidget {
  const _PosHeaderCard();

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      padding: EdgeInsets.zero,
      child: Container(
        padding: const EdgeInsets.all(CronosSpacing.lg),
        decoration: const BoxDecoration(
          gradient: CronosColors.primaryGradient,
          borderRadius: BorderRadius.all(
            Radius.circular(CronosRadius.lg),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(CronosRadius.lg),
              ),
              child: const Icon(
                Icons.shopping_cart_checkout_outlined,
                color: Colors.white,
                size: 34,
              ),
            ),
            const SizedBox(width: CronosSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Punto de venta',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: CronosSpacing.xs),
                  Text(
                    'Busca productos, arma el carrito y registra ventas offline-first.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyProductsState extends StatelessWidget {
  const _EmptyProductsState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: CronosSpacing.md),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: CronosColors.primarySoft,
            borderRadius: BorderRadius.circular(CronosRadius.xl),
          ),
          child: const Icon(
            Icons.manage_search_outlined,
            color: CronosColors.primary,
            size: 38,
          ),
        ),
        const SizedBox(height: CronosSpacing.md),
        Text(
          'Busca un producto para empezar',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: CronosSpacing.xs),
        Text(
          'En la siguiente fase conectamos productos locales, stock disponible y selección por código de barras.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: CronosSpacing.md),
      ],
    );
  }
}

class _SearchPreviewState extends StatelessWidget {
  const _SearchPreviewState({
    required this.query,
  });

  final String query;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.search_outlined,
          color: CronosColors.primary,
        ),
        const SizedBox(width: CronosSpacing.sm),
        Expanded(
          child: Text(
            'Buscar “$query” se conectará en 40C.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _CartSection extends StatelessWidget {
  const _CartSection({
    required this.paymentMethod,
    required this.onPaymentMethodChanged,
    required this.cashRegisterName,
    required this.cashSessionId,
  });

  final String paymentMethod;
  final ValueChanged<String?> onPaymentMethodChanged;
  final String? cashRegisterName;
  final String? cashSessionId;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Carrito',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const AppStatusChip(
                label: '0 ítems',
                tone: AppStatusTone.neutral,
                icon: Icons.shopping_bag_outlined,
              ),
            ],
          ),
          const SizedBox(height: CronosSpacing.sm),
          AppStatusChip(
            label: cashRegisterName == null || cashRegisterName!.trim().isEmpty
                ? 'Caja activa'
                : cashRegisterName!,
            tone: AppStatusTone.success,
            icon: Icons.point_of_sale_outlined,
          ),
          const SizedBox(height: CronosSpacing.md),
          Container(
            padding: const EdgeInsets.all(CronosSpacing.lg),
            decoration: BoxDecoration(
              color: CronosColors.surfaceMuted,
              borderRadius: BorderRadius.circular(CronosRadius.lg),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.add_shopping_cart_outlined,
                  color: CronosColors.textMuted,
                  size: 42,
                ),
                const SizedBox(height: CronosSpacing.sm),
                Text(
                  'Carrito vacío',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: CronosSpacing.xs),
                Text(
                  'Agrega productos desde la búsqueda para calcular el total.',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: CronosSpacing.md),
          DropdownButtonFormField<String>(
            value: paymentMethod,
            decoration: const InputDecoration(
              labelText: 'Método de pago',
            ),
            items: const [
              DropdownMenuItem(
                value: 'cash',
                child: Text('Efectivo'),
              ),
              DropdownMenuItem(
                value: 'card',
                child: Text('Tarjeta'),
              ),
              DropdownMenuItem(
                value: 'transfer',
                child: Text('Transferencia'),
              ),
            ],
            onChanged: onPaymentMethodChanged,
          ),
          const SizedBox(height: CronosSpacing.md),
          const _TotalRow(label: 'Subtotal', value: '\$0.00'),
          const _TotalRow(label: 'Descuentos', value: '\$0.00'),
          const _TotalRow(label: 'Impuestos', value: '\$0.00'),
          const Divider(height: CronosSpacing.lg),
          const _TotalRow(
            label: 'Total',
            value: '\$0.00',
            emphasized: true,
          ),
          const SizedBox(height: CronosSpacing.md),
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Cobrar venta'),
          ),
          const SizedBox(height: CronosSpacing.sm),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.sync_outlined),
            label: const Text('Sincronizar POS'),
          ),
          if (cashSessionId != null && cashSessionId!.trim().isNotEmpty) ...[
            const SizedBox(height: CronosSpacing.sm),
            Text(
              'Sesión: $cashSessionId',
              style: Theme.of(context).textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleLarge
        : Theme.of(context).textTheme.bodyLarge;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label),
          ),
          Text(
            value,
            style: style?.copyWith(
              fontWeight: emphasized ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
