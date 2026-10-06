import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/models/product_sale_mode.dart';
import '../../../../core/money/cop_price_input.dart';
import '../../../../core/quantity/weight_quantity_input.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../../auth/application/authenticated_access_providers.dart';
import '../../../catalog/application/catalog_local_providers.dart';
import '../../../sync/application/operational_bootstrap_entry_providers.dart';
import '../../../sync/data/models/authorized_operational_context_models.dart';
import '../../application/business_product_creation_models.dart';
import '../../application/inventory_cost_visibility_provider.dart';
import '../../application/inventory_transfer_models.dart';
import '../../application/inventory_transfer_providers.dart';
import '../../application/inventory_valuation_models.dart';
import '../../application/inventory_product_providers.dart';
import '../../application/product_stock_balance_providers.dart';
import '../widgets/inventory_transfer_dialog.dart';
import '../widgets/product_creation_commercial_fields.dart';
import '../../application/inventory_adjustment_provider.dart';
import '../widgets/inventory_adjustment_dialog.dart';

typedef InventoryProductMovementsCallback = Future<void> Function({
  required String productId,
  required String productName,
  String? productBarcode,
});

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
    this.initialStockFilter = InventoryProductStockFilter.all,
    this.onOpenProductMovements,
  });

  final String businessId;
  final String branchId;
  final String branchName;
  final String? profileId;
  final String? appDeviceId;
  final String? deviceInstallationId;
  final Set<String> effectivePermissions;
  final InventoryProductStockFilter initialStockFilter;
  final InventoryProductMovementsCallback? onOpenProductMovements;

  @override
  ConsumerState<InventoryProductStockListScreen> createState() =>
      _InventoryProductStockListScreenState();
}

class _InventoryProductStockListScreenState
    extends ConsumerState<InventoryProductStockListScreen> {
  final _searchController = TextEditingController();
  final _minimumStockUpdates = <String>{};
  final _saleConfigurationUpdates = <String>{};
  bool _isCreatingProduct = false;
  bool _adjustmentOpen = false;
  String _searchTerm = '';
  late InventoryProductStockFilter _stockFilter;

  @override
  void initState() {
    super.initState();
    _stockFilter = widget.initialStockFilter;
  }

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

  Future<void> _openAdjustment(Map<String, dynamic> product) async {
    final profileId = widget.profileId?.trim();
    final productId = _string(product['product_id']);
    if (_adjustmentOpen || profileId == null || productId == null) {
      return;
    }
    final scope = (
      profileId: profileId,
      businessId: widget.businessId,
      branchId: widget.branchId
    );
    if (!widget.effectivePermissions.contains('inventory.adjust') ||
        ref.read(inventoryAdjustmentAllowedProvider(scope)).asData?.value !=
            true) {
      return;
    }
    _adjustmentOpen = true;
    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => InventoryAdjustmentDialog(
          key: ValueKey((scope, productId)),
          scope: scope,
          productId: productId,
          productName: _string(product['product_name']) ?? 'Producto',
          isScopeCurrent: () =>
              mounted &&
              widget.profileId?.trim() == scope.profileId &&
              widget.businessId == scope.businessId &&
              widget.branchId == scope.branchId &&
              widget.effectivePermissions.contains('inventory.adjust'),
        ),
      );
      if (mounted && saved == true) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ajuste registrado en el dispositivo.'),
        ));
      }
    } finally {
      _adjustmentOpen = false;
    }
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
    final isWeight = product['sale_mode'] == 'weight';
    var value = isWeight
        ? _formatKilograms(_minimumStock(product['minimum_stock']))
        : _minimumStock(product['minimum_stock']).toString();
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
            keyboardType: TextInputType.numberWithOptions(decimal: isWeight),
            decoration: InputDecoration(
              labelText: 'Stock mínimo',
              helperText: isWeight
                  ? 'Kilogramos; hasta 3 decimales.'
                  : 'Nivel deseado para este producto.',
              suffixText: isWeight ? 'kg' : null,
              border: const OutlineInputBorder(),
            ),
            validator: (raw) {
              final text = (raw ?? '').trim();
              final parsed = isWeight
                  ? (text == '0'
                      ? 0
                      : parseWeightQuantity(text, WeightInputUnit.kilogram))
                  : int.tryParse(text);
              return parsed == null || parsed < 0
                  ? (isWeight
                      ? 'Ingresa kilogramos con hasta 3 decimales.'
                      : 'Usa un entero igual o mayor a cero.')
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
              Navigator.of(dialogContext).pop(isWeight
                  ? (value.trim() == '0'
                      ? 0
                      : parseWeightQuantity(value, WeightInputUnit.kilogram)!)
                  : int.parse(value.trim()));
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

  Future<void> _editSaleConfiguration(Map<String, dynamic> product) async {
    final productId = _string(product['product_id']);
    final profileId = widget.profileId?.trim();
    final installationId = widget.deviceInstallationId?.trim();
    if (productId == null ||
        profileId == null ||
        profileId.isEmpty ||
        installationId == null ||
        installationId.isEmpty ||
        _saleConfigurationUpdates.contains(productId)) {
      return;
    }

    final draft = await showDialog<int>(
      context: context,
      builder: (_) => _InventorySaleConfigurationDialog(product: product),
    );
    if (!mounted || draft == null) return;
    setState(() => _saleConfigurationUpdates.add(productId));
    final result =
        await ref.read(businessProductSaleConfigurationUpdaterProvider)(
      BusinessProductSaleConfigurationUpdateInput(
        context: BusinessProductCreationContext(
          businessId: widget.businessId,
          branchId: widget.branchId,
          profileId: profileId,
          appDeviceId: widget.appDeviceId,
          deviceInstallationId: installationId,
          effectivePermissions: widget.effectivePermissions,
        ),
        productId: productId,
        saleMode: ProductSaleMode.parse(product['sale_mode'] ?? 'unit'),
        salePriceCents: draft,
      ),
    );
    if (!mounted) return;
    setState(() => _saleConfigurationUpdates.remove(productId));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
  }

  Future<void> _openAddProduct() async {
    final profileId = widget.profileId?.trim();
    final installationId = widget.deviceInstallationId?.trim();
    if (profileId == null ||
        profileId.isEmpty ||
        installationId == null ||
        installationId.isEmpty ||
        _isCreatingProduct) {
      return;
    }

    final selection = await showDialog<_InventoryProductSelection>(
      context: context,
      builder: (_) => _InventoryProductSelectionDialog(
        businessId: widget.businessId,
        branchId: widget.branchId,
      ),
    );
    if (!mounted || selection == null) return;

    final existingProduct = selection.existingProduct;
    if (existingProduct != null) {
      final name = _string(existingProduct['name']) ?? 'Producto existente';
      setState(() {
        _searchController.text = name;
        _searchTerm = name;
        _stockFilter = InventoryProductStockFilter.all;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El producto ya forma parte del catálogo del negocio.'),
        ),
      );
      return;
    }

    final draft = await showDialog<_InventoryProductDraft>(
      context: context,
      builder: (_) => _InventoryProductDraftDialog(
        masterProduct: selection.masterProduct,
        initialQuery: selection.manualQuery,
        initialBarcode: _string(selection.masterProduct?['barcode']),
      ),
    );
    if (!mounted || draft == null) return;

    setState(() => _isCreatingProduct = true);
    BusinessProductCreationResult result;
    try {
      result = await ref.read(businessProductCreateOrUseProvider)(
        context: BusinessProductCreationContext(
          businessId: widget.businessId,
          branchId: widget.branchId,
          profileId: profileId,
          appDeviceId: widget.appDeviceId,
          deviceInstallationId: installationId,
          effectivePermissions: widget.effectivePermissions,
        ),
        code: draft.barcode,
        fields: BusinessProductOwnedFields(
          name: draft.name,
          purchasePrice: draft.purchasePrice,
          salePrice: draft.salePrice,
          saleMode: draft.saleMode,
          salePriceCents: draft.salePriceCents,
          minimumStock: draft.minimumStock,
          unit: draft.unit,
        ),
      );
    } catch (_) {
      result = const BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.localPersistenceFailure,
        message: 'No fue posible crear el producto localmente.',
      );
    }
    if (!mounted) return;

    setState(() => _isCreatingProduct = false);
    if (result.succeeded) {
      final name = _string(result.product?['name']) ?? draft.name;
      _searchController.text = name;
      _searchTerm = name;
      _stockFilter = InventoryProductStockFilter.all;
      ref.invalidate(localProductsWithStockProvider);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.created
              ? '${result.message} El stock inicial es 0.'
              : result.message,
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
          stockFilter: _stockFilter,
          limit: null,
        ),
      ),
    );
    final profileId = widget.profileId?.trim();
    final hasCostCapability =
        widget.effectivePermissions.contains('inventory.view_costs');
    final canViewCosts = !hasCostCapability
        ? false
        : profileId == null || profileId.isEmpty
            ? true
            : ref
                .watch(
                  inventoryCostVisibilityProvider(
                    InventoryCostVisibilityKey(
                      profileId: profileId,
                      businessId: widget.businessId,
                      branchId: widget.branchId,
                    ),
                  ),
                )
                .when(
                  data: (allowed) => allowed,
                  loading: () => false,
                  error: (_, __) => false,
                );
    final valuationSummaryAsync = canViewCosts
        ? ref.watch(
            inventoryValuationSummaryProvider(
              InventoryValuationSummaryKey(
                businessId: widget.businessId,
                branchId: widget.branchId,
              ),
            ),
          )
        : null;
    final hasSearch = _searchTerm.trim().isNotEmpty;
    final canAdjust = profileId != null &&
        profileId.isNotEmpty &&
        widget.effectivePermissions.contains('inventory.adjust') &&
        ref
                .watch(inventoryAdjustmentAllowedProvider((
                  profileId: profileId,
                  businessId: widget.businessId,
                  branchId: widget.branchId
                )))
                .asData
                ?.value ==
            true;
    final canTransfer = widget.profileId != null &&
        widget.effectivePermissions.contains('inventory.transfer');
    final canEditMinimumStock = widget.profileId?.trim().isNotEmpty == true &&
        widget.deviceInstallationId?.trim().isNotEmpty == true &&
        widget.effectivePermissions.contains('products.update');
    final canCreateProduct = widget.profileId?.trim().isNotEmpty == true &&
        widget.deviceInstallationId?.trim().isNotEmpty == true &&
        widget.effectivePermissions.contains('products.create');
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
          child: CustomScrollView(
            key: const Key('inventory-content-scroll'),
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            slivers: [
              SliverToBoxAdapter(
                  child: Column(children: [
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
                        ChoiceChip(
                          key: const Key('inventory-filter-low-stock'),
                          label: const Text('Bajo stock'),
                          selected: _stockFilter ==
                              InventoryProductStockFilter.lowStock,
                          onSelected: (_) => _setStockFilter(
                            InventoryProductStockFilter.lowStock,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (canViewCosts)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      CronosSpacing.md,
                      CronosSpacing.sm,
                      CronosSpacing.md,
                      0,
                    ),
                    child: valuationSummaryAsync!.when(
                      loading: () => const _InventoryValuationLoading(),
                      error: (_, __) => const _InventoryValuationUnavailable(),
                      data: (summary) => _InventoryValuationSummaryCard(
                        summary: summary,
                      ),
                    ),
                  ),
              ])),
              productsAsync.when<Widget>(
                loading: () => const SliverToBoxAdapter(
                    child: SizedBox(
                        height: 320,
                        child: Center(
                          key: Key('inventory-loading'),
                          child: CircularProgressIndicator(),
                        ))),
                error: (error, _) => const SliverToBoxAdapter(
                    child: SizedBox(
                        height: 320,
                        child: _InventoryStateMessage(
                          key: Key('inventory-error'),
                          icon: Icons.error_outline,
                          title: 'No se pudo cargar el inventario',
                          message:
                              'Vuelve a intentarlo. Tus productos guardados no se perderán.',
                        ))),
                data: (products) {
                  if (products.isEmpty) {
                    if (hasSearch) {
                      return const SliverToBoxAdapter(
                          child: SizedBox(
                              height: 320,
                              child: _InventoryStateMessage(
                                key: Key('inventory-search-empty'),
                                icon: Icons.search_off,
                                title: 'No se encontraron productos',
                                message:
                                    'Prueba con otro nombre o código del producto.',
                              )));
                    }

                    if (_stockFilter ==
                        InventoryProductStockFilter.outOfStock) {
                      return const SliverToBoxAdapter(
                          child: SizedBox(
                              height: 320,
                              child: _InventoryStateMessage(
                                key: Key('inventory-out-of-stock-empty'),
                                icon: Icons.inventory_2_outlined,
                                title: 'Sin productos agotados',
                                message:
                                    'La sucursal seleccionada no tiene existencias agotadas.',
                              )));
                    }

                    if (_stockFilter == InventoryProductStockFilter.lowStock) {
                      return const SliverToBoxAdapter(
                          child: SizedBox(
                              height: 320,
                              child: _InventoryStateMessage(
                                key: Key('inventory-low-stock-empty'),
                                icon: Icons.inventory_2_outlined,
                                title: 'Sin productos con bajo stock',
                                message:
                                    'La sucursal seleccionada no tiene existencias bajo el mínimo.',
                              )));
                    }

                    return const SliverToBoxAdapter(
                        child: SizedBox(
                            height: 320,
                            child: _InventoryStateMessage(
                              key: Key('inventory-empty'),
                              icon: Icons.inventory_2_outlined,
                              title: 'Sin productos',
                              message:
                                  'No hay productos visibles para el negocio seleccionado.',
                            )));
                  }

                  Widget productCard(BuildContext context, int index,
                      {bool gridCard = false}) {
                    final product = products[index];
                    final actualProductId = _string(product['product_id']);
                    final productKey = actualProductId ?? '$index';

                    return _InventoryProductCard(
                      key: Key('inventory-product-$productKey'),
                      product: product,
                      gridCard: gridCard,
                      canViewCosts: canViewCosts,
                      isUpdatingMinimumStock:
                          _minimumStockUpdates.contains(productKey),
                      onOpenMovements: actualProductId != null &&
                              widget.onOpenProductMovements != null
                          ? () async {
                              await widget.onOpenProductMovements!(
                                productId: actualProductId,
                                productName: _string(product['product_name']) ??
                                    'Producto sin nombre',
                                productBarcode: _string(product['barcode']),
                              );
                            }
                          : null,
                      onEditMinimumStock: canEditMinimumStock
                          ? () => _editMinimumStock(product)
                          : null,
                      onEditSaleConfiguration: canEditMinimumStock
                          ? () => _editSaleConfiguration(product)
                          : null,
                      onAdjust: canAdjust &&
                              actualProductId != null &&
                              product['sale_mode'] != 'weight'
                          ? () => _openAdjustment(product)
                          : null,
                      onTransfer: product['sale_mode'] != 'weight' &&
                              sourceContext != null &&
                              destinationContexts.isNotEmpty &&
                              _int(product['quantity_available']) > 0
                          ? () => _openTransfer(
                                product: product,
                                sourceContext: sourceContext,
                                destinationContexts: destinationContexts,
                              )
                          : null,
                    );
                  }

                  return SliverLayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.crossAxisExtent >= 700) {
                        return SliverPadding(
                          padding: const EdgeInsets.all(CronosSpacing.md),
                          sliver: SliverGrid.builder(
                            key: const Key('inventory-product-grid'),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 460,
                              mainAxisExtent: 500,
                              crossAxisSpacing: CronosSpacing.md,
                              mainAxisSpacing: CronosSpacing.md,
                            ),
                            itemCount: products.length,
                            itemBuilder: (context, index) =>
                                productCard(context, index, gridCard: true),
                          ),
                        );
                      }
                      return SliverList.builder(
                        key: const Key('inventory-product-list'),
                        itemCount: products.length * 2 + 1,
                        itemBuilder: (context, index) {
                          if (index.isEven) {
                            return SizedBox(
                              height: index == 0 || index == products.length * 2
                                  ? CronosSpacing.md
                                  : CronosSpacing.sm,
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: CronosSpacing.md),
                            child: productCard(context, index ~/ 2),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
        floatingActionButton: canCreateProduct
            ? FloatingActionButton.extended(
                key: const Key('inventory-add-product'),
                onPressed: _isCreatingProduct ? null : _openAddProduct,
                icon: _isCreatingProduct
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: Text(
                  _isCreatingProduct ? 'Agregando…' : 'Agregar producto',
                ),
              )
            : null,
      ),
    );
  }
}

class _InventoryProductSelection {
  const _InventoryProductSelection.existing(this.existingProduct)
      : masterProduct = null,
        manualQuery = null;

  const _InventoryProductSelection.master(this.masterProduct)
      : existingProduct = null,
        manualQuery = null;

  const _InventoryProductSelection.manual(this.manualQuery)
      : existingProduct = null,
        masterProduct = null;

  final Map<String, dynamic>? existingProduct;
  final Map<String, dynamic>? masterProduct;
  final String? manualQuery;
}

class _InventoryProductSelectionDialog extends ConsumerStatefulWidget {
  const _InventoryProductSelectionDialog({
    required this.businessId,
    required this.branchId,
  });

  final String businessId;
  final String branchId;

  @override
  ConsumerState<_InventoryProductSelectionDialog> createState() =>
      _InventoryProductSelectionDialogState();
}

class _InventoryProductSelectionDialogState
    extends ConsumerState<_InventoryProductSelectionDialog> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final businessProductsAsync = ref.watch(
      localProductsWithStockProvider(
        ProductsWithLocalStockKey(
          businessId: widget.businessId,
          branchId: widget.branchId,
          searchTerm: _query,
          limit: 20,
        ),
      ),
    );
    final masterProductsAsync = ref.watch(
      localMasterProductSearchProvider(
        CatalogMasterSearchKey(
          businessId: widget.businessId,
          query: _query,
          limit: 20,
        ),
      ),
    );
    final businessProducts =
        businessProductsAsync.asData?.value ?? const <Map<String, dynamic>>[];
    final businessProductIds = businessProducts
        .map((product) => _string(product['product_id']))
        .whereType<String>()
        .toSet();
    final masterProducts = masterProductsAsync.asData?.value
            .where(
              (master) => !businessProductIds.contains(
                _string(master['existing_product_id']),
              ),
            )
            .toList(growable: false) ??
        const <Map<String, dynamic>>[];
    final loading =
        businessProductsAsync.isLoading || masterProductsAsync.isLoading;
    final hasError =
        businessProductsAsync.hasError || masterProductsAsync.hasError;

    final screenSize = MediaQuery.sizeOf(context);
    final targetHeight = screenSize.width >= 600
        ? (screenSize.height * 0.8).clamp(0.0, 640.0)
        : (screenSize.height * 0.9).clamp(0.0, 720.0);
    return Dialog(
      key: const Key('inventory-product-picker-dialog'),
      insetPadding: const EdgeInsets.symmetric(
        horizontal: CronosSpacing.md,
        vertical: CronosSpacing.sm,
      ),
      child: SizedBox(
        width: (screenSize.width - 64).clamp(0.0, 640.0),
        height: targetHeight,
        child: Padding(
          key: const Key('inventory-product-picker-scroll'),
          padding: const EdgeInsets.all(CronosSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  key: const Key('inventory-add-product-results'),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Agregar producto',
                          style: Theme.of(context).textTheme.titleLarge),
                    ),
                    const SizedBox(height: CronosSpacing.sm),
                    TextField(
                      key: const Key('inventory-add-product-search'),
                      controller: _controller,
                      autofocus: true,
                      onChanged: (value) =>
                          setState(() => _query = value.trim()),
                      decoration: const InputDecoration(
                        labelText: 'Nombre, marca o código',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: CronosSpacing.sm),
                    if (loading) const LinearProgressIndicator(),
                    if (hasError)
                      const _InventoryStateMessage(
                        icon: Icons.error_outline,
                        title: 'No se pudo consultar el catálogo local',
                        message:
                            'Cierra e intenta nuevamente. No se consultó la red.',
                      )
                    else ...[
                      if (businessProducts.isNotEmpty) ...[
                        const _ProductSearchSectionTitle(
                          title: 'Productos de mi negocio',
                        ),
                        for (final product in businessProducts)
                          ListTile(
                            key: Key(
                              'inventory-existing-product-${_string(product['product_id'])}',
                            ),
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: Text(
                              _string(product['product_name']) ??
                                  'Producto sin nombre',
                            ),
                            subtitle: const Text(
                              'Producto ya manejado por la tienda · Ya en mi catálogo',
                            ),
                            trailing: const Icon(Icons.check_circle_outline),
                            onTap: () => Navigator.of(context).pop(
                              _InventoryProductSelection.existing({
                                'id': product['product_id'],
                                'name': product['product_name'],
                                'barcode': product['barcode'],
                              }),
                            ),
                          ),
                      ],
                      if (masterProducts.isNotEmpty) ...[
                        const _ProductSearchSectionTitle(
                          title: 'Catálogo maestro',
                        ),
                        for (final master in masterProducts)
                          _MasterProductSearchTile(master: master),
                      ],
                      if (_query.isEmpty && businessProducts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(CronosSpacing.md),
                          child: Text(
                            'Escribe un nombre, marca o código para buscar en el catálogo maestro local.',
                          ),
                        )
                      else if (!loading &&
                          businessProducts.isEmpty &&
                          masterProducts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(CronosSpacing.md),
                          child: Text(
                            'No hay coincidencias en el negocio ni en el catálogo maestro local.',
                          ),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: CronosSpacing.xs),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: CronosSpacing.sm,
                runSpacing: CronosSpacing.xs,
                children: [
                  TextButton.icon(
                    key: const Key('inventory-create-product-manually'),
                    onPressed: () => Navigator.of(context).pop(
                      _InventoryProductSelection.manual(_query),
                    ),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Crear manualmente'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductSearchSectionTitle extends StatelessWidget {
  const _ProductSearchSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        CronosSpacing.sm,
        CronosSpacing.md,
        CronosSpacing.sm,
        CronosSpacing.xs,
      ),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _MasterProductSearchTile extends StatelessWidget {
  const _MasterProductSearchTile({required this.master});

  final Map<String, dynamic> master;

  @override
  Widget build(BuildContext context) {
    final masterId = _string(master['master_product_id']) ?? '';
    final name =
        _string(master['master_product_name']) ?? 'Producto sin nombre';
    final brand = _string(master['master_brand']);
    final barcode = _string(master['barcode']);
    final existingProductId = _string(master['existing_product_id']);
    final isExisting = existingProductId != null;

    return Card(
      key: Key('inventory-master-product-$masterId'),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: CronosSpacing.sm),
        leading: Icon(
          isExisting ? Icons.inventory_2_outlined : Icons.public_outlined,
        ),
        title: Text(name),
        subtitle: Text(
          [
            if (brand != null) brand,
            if (barcode != null) barcode,
            isExisting
                ? 'Producto ya manejado por la tienda · Ya en mi catálogo'
                : 'Referencia del catálogo maestro; aún no está en tu inventario',
          ].join(' · '),
        ),
        trailing: isExisting
            ? const Icon(Icons.check_circle_outline)
            : FilledButton(
                key: Key('inventory-add-master-$masterId'),
                onPressed: barcode == null
                    ? null
                    : () => Navigator.of(context).pop(
                          _InventoryProductSelection.master(master),
                        ),
                child: const Text('Agregar'),
              ),
        onTap: !isExisting
            ? null
            : () => Navigator.of(context).pop(
                  _InventoryProductSelection.existing({
                    'id': existingProductId,
                    'name': master['existing_product_name'],
                    'barcode': master['existing_product_barcode'],
                  }),
                ),
      ),
    );
  }
}

class _InventorySaleConfigurationDialog extends StatefulWidget {
  const _InventorySaleConfigurationDialog({required this.product});

  final Map<String, dynamic> product;

  @override
  State<_InventorySaleConfigurationDialog> createState() =>
      _InventorySaleConfigurationDialogState();
}

class _InventorySaleConfigurationDialogState
    extends State<_InventorySaleConfigurationDialog> {
  final _formKey = GlobalKey<FormState>();
  late ProductSaleMode _mode;
  late String _price;

  @override
  void initState() {
    super.initState();
    _mode = ProductSaleMode.parse(widget.product['sale_mode'] ?? 'unit');
    final cents = widget.product['sale_price_cents'];
    final legacy = widget.product['sale_price'];
    _price = cents is int
        ? exactPesosFromCents(cents).replaceAll('.', ',')
        : legacy is num
            ? legacy.toStringAsFixed(2).replaceAll('.', ',')
            : '0';
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Cambiar precio'),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: const Key('inventory-edit-sale-price'),
                initialValue: _price,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _mode == ProductSaleMode.weight
                      ? 'Precio por libra (500 g)'
                      : 'Precio por unidad',
                  border: const OutlineInputBorder(),
                ),
                validator: (value) => parseCopPriceCents(value ?? '') == null
                    ? 'Ingresa un precio válido en pesos.'
                    : null,
                onChanged: (value) => _price = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const Key('inventory-edit-sale-save'),
            onPressed: () {
              if (!(_formKey.currentState?.validate() ?? false)) return;
              Navigator.of(context).pop(parseCopPriceCents(_price)!);
            },
            child: const Text('Guardar'),
          ),
        ],
      );
}

class _InventoryProductDraft {
  const _InventoryProductDraft({
    required this.name,
    required this.purchasePrice,
    required this.salePrice,
    required this.saleMode,
    required this.salePriceCents,
    required this.minimumStock,
    required this.unit,
    this.barcode,
  });

  final String name;
  final String? barcode;
  final double purchasePrice;
  final double salePrice;
  final ProductSaleMode saleMode;
  final int salePriceCents;
  final int minimumStock;
  final String? unit;
}

class _InventoryProductDraftDialog extends StatefulWidget {
  const _InventoryProductDraftDialog({
    this.masterProduct,
    this.initialQuery,
    this.initialBarcode,
  });

  final Map<String, dynamic>? masterProduct;
  final String? initialQuery;
  final String? initialBarcode;

  @override
  State<_InventoryProductDraftDialog> createState() =>
      _InventoryProductDraftDialogState();
}

class _InventoryProductDraftDialogState
    extends State<_InventoryProductDraftDialog> {
  final _formKey = GlobalKey<FormState>();
  final _commercial = ProductCreationCommercialController();
  late String _name;
  String? _barcode;

  @override
  void initState() {
    super.initState();
    final master = widget.masterProduct;
    final query = widget.initialQuery?.trim() ?? '';
    final queryLooksLikeCode = RegExp(r'\d').hasMatch(query);
    _name = _string(
          master?['master_product_name'] ??
              master?['master_product_product_name'] ??
              master?['master_name'],
        ) ??
        (queryLooksLikeCode ? '' : query);
    _barcode = widget.initialBarcode ?? (queryLooksLikeCode ? query : null);
    _commercial.unit = _string(master?['master_package_unit']) ??
        _string(master?['master_unit_type']) ??
        'unidad';
  }

  @override
  void dispose() {
    _commercial.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fromMaster = widget.masterProduct != null;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: CronosSpacing.md,
        vertical: CronosSpacing.md,
      ),
      child: SizedBox(
        width: (MediaQuery.sizeOf(context).width - 64).clamp(0.0, 620.0),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(CronosSpacing.md),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  fromMaster
                      ? 'Agregar a mi catálogo'
                      : 'Crear producto manualmente',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: CronosSpacing.md),
                if (fromMaster)
                  const Padding(
                    padding: EdgeInsets.only(bottom: CronosSpacing.md),
                    child: Text(
                      'Los datos maestros son una referencia. Define los datos comerciales de este negocio.',
                    ),
                  ),
                TextFormField(
                  key: const Key('inventory-product-name-field'),
                  initialValue: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre en mi negocio',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().length < 2
                      ? 'El nombre es requerido.'
                      : null,
                  onChanged: (value) => _name = value,
                ),
                const SizedBox(height: CronosSpacing.sm),
                TextFormField(
                  key: const Key('inventory-product-barcode-field'),
                  initialValue: _barcode,
                  readOnly: fromMaster,
                  decoration: InputDecoration(
                    labelText: 'Código / barcode opcional',
                    border: const OutlineInputBorder(),
                    helperText: fromMaster
                        ? 'Código del catálogo maestro seleccionado.'
                        : null,
                  ),
                  onChanged: (value) => _barcode = value.trim(),
                ),
                const SizedBox(height: CronosSpacing.sm),
                ProductCreationCommercialFields(
                  controller: _commercial,
                  keyPrefix: 'inventory-product',
                ),
                const SizedBox(height: CronosSpacing.md),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: CronosSpacing.sm,
                  runSpacing: CronosSpacing.sm,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      key: const Key('inventory-product-create-confirm'),
                      onPressed: () {
                        if (!(_formKey.currentState?.validate() ?? false)) {
                          return;
                        }
                        Navigator.of(context).pop(
                          _InventoryProductDraft(
                            name: _name.trim(),
                            barcode: _string(_barcode),
                            purchasePrice: 0,
                            salePrice: _commercial.salePriceCents! / 100,
                            saleMode: _commercial.saleMode,
                            salePriceCents: _commercial.salePriceCents!,
                            minimumStock: _commercial.minimumStock!,
                            unit: _string(_commercial.unitForPersistence),
                          ),
                        );
                      },
                      child: const Text('Guardar producto'),
                    ),
                  ],
                ),
              ],
            ),
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
    this.gridCard = false,
    required this.canViewCosts,
    required this.isUpdatingMinimumStock,
    this.onOpenMovements,
    this.onEditMinimumStock,
    this.onEditSaleConfiguration,
    this.onAdjust,
    this.onTransfer,
  });

  final Map<String, dynamic> product;
  final bool gridCard;
  final bool canViewCosts;
  final bool isUpdatingMinimumStock;
  final VoidCallback? onOpenMovements;
  final VoidCallback? onEditMinimumStock;
  final VoidCallback? onEditSaleConfiguration;
  final VoidCallback? onAdjust;
  final VoidCallback? onTransfer;

  @override
  Widget build(BuildContext context) {
    final name = _string(product['product_name']) ?? 'Producto sin nombre';
    final barcode = _string(product['barcode']);
    final saleMode = ProductSaleMode.parse(product['sale_mode'] ?? 'unit');
    final stock = saleMode == ProductSaleMode.weight
        ? '${_formatKilograms(_int(product['quantity_on_hand']))} kg'
        : _formatQuantity(product['quantity_on_hand']);
    final exactPrice = product['sale_price_cents'];
    final minimumStock = _minimumStock(product['minimum_stock']);
    final productId = _string(product['product_id']) ?? '';
    final quantityOnHand = _int(product['quantity_on_hand']);
    final isOutOfStock = quantityOnHand <= 0;
    final isLowStock = quantityOnHand > 0 && quantityOnHand <= minimumStock;
    final valuation = canViewCosts ? product['inventory_valuation'] : null;
    final valuationLabel = valuation is InventoryProductValuation
        ? _formatProductValuation(valuation)
        : 'no disponible';

    return AppGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            ProductImage(
              key: Key('inventory-product-image-$productId'),
              barcode: barcode,
              semanticLabel: 'Imagen de $name',
              size: gridCard ? 80 : 48,
            ),
            const SizedBox(width: CronosSpacing.md),
            Expanded(
                child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (barcode != null) ...[
                  const SizedBox(height: CronosSpacing.xs),
                  Text(
                    barcode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: CronosSpacing.xs),
                Text(
                  exactPrice is int
                      ? '${formatCopPriceCents(exactPrice)} / ${saleMode == ProductSaleMode.weight ? "libra" : "unidad"}'
                      : 'Precio no disponible',
                  key: Key('inventory-weight-price-$productId'),
                ),
                if (isOutOfStock) ...[
                  const SizedBox(height: CronosSpacing.xs),
                  Chip(
                    key: Key('inventory-out-of-stock-$productId'),
                    avatar: const Icon(Icons.remove_shopping_cart_outlined),
                    label: const Text('Agotado'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ] else if (isLowStock) ...[
                  const SizedBox(height: CronosSpacing.xs),
                  Chip(
                    key: Key('inventory-low-stock-$productId'),
                    avatar: const Icon(Icons.warning_amber_rounded),
                    label: const Text('Bajo stock'),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ],
            )),
          ]),
          const SizedBox(height: CronosSpacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Stock: $stock',
                key: Key('inventory-stock-$productId'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: CronosColors.primaryDark,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (canViewCosts && saleMode == ProductSaleMode.unit) ...[
                const SizedBox(height: CronosSpacing.xs),
                Text(
                  'Costo prom.: ${_formatAverageCost(product['stock_average_cost'])}',
                  key: Key('inventory-average-cost-$productId'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: CronosSpacing.xs),
                Text(
                  'Valor: $valuationLabel',
                  key: Key('inventory-value-$productId'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: CronosSpacing.xs),
              Text(
                saleMode == ProductSaleMode.weight
                    ? 'Mínimo: ${_formatKilograms(minimumStock)} kg'
                    : 'Mínimo: $minimumStock',
                key: Key('inventory-minimum-stock-$productId'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (onOpenMovements != null)
                TextButton.icon(
                  key: Key('inventory-movements-$productId'),
                  onPressed: onOpenMovements,
                  icon: const Icon(Icons.timeline_outlined),
                  label: const Text('Movimientos'),
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
              if (onEditSaleConfiguration != null)
                TextButton.icon(
                  key: Key('inventory-edit-sale-config-$productId'),
                  onPressed: onEditSaleConfiguration,
                  icon: const Icon(Icons.sell_outlined),
                  label: const Text('Cambiar precio'),
                ),
              if (onAdjust != null)
                TextButton.icon(
                  key: Key('inventory-adjust-$productId'),
                  onPressed: onAdjust,
                  icon: const Icon(Icons.tune),
                  label: const Text('Ajustar inventario'),
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

class _InventoryValuationSummaryCard extends StatelessWidget {
  const _InventoryValuationSummaryCard({required this.summary});

  final InventoryValuationSummary summary;

  @override
  Widget build(BuildContext context) {
    final title = summary.isComplete ? 'Valor inventario' : 'Valor conocido';
    return AppGlassCard(
      key: const Key('inventory-valuation-summary'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.account_balance_wallet_outlined),
          const SizedBox(width: CronosSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.labelLarge),
                Text(
                  formatInventoryMoneyCents(summary.knownValueCents),
                  key: const Key('inventory-valuation-known-value'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: CronosColors.primaryDark,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (summary.unknownCostProductCount > 0)
                  Text(
                    'Sin costo conocido: '
                    '${summary.unknownCostProductCount} producto(s) / '
                    '${summary.unknownCostUnitCount} unidad(es)',
                    key: const Key('inventory-valuation-unknown-cost'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                if (summary.invalidStockProductCount > 0)
                  Text(
                    'Stock inválido: '
                    '${summary.invalidStockProductCount} producto(s)',
                    key: const Key('inventory-valuation-invalid-stock'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                if (summary.precisionAnomalyProductCount > 0)
                  Text(
                    'Valor no representable: '
                    '${summary.precisionAnomalyProductCount} producto(s)',
                    key: const Key('inventory-valuation-precision-anomaly'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InventoryValuationLoading extends StatelessWidget {
  const _InventoryValuationLoading();

  @override
  Widget build(BuildContext context) {
    return const AppGlassCard(
      key: Key('inventory-valuation-loading'),
      child: LinearProgressIndicator(),
    );
  }
}

class _InventoryValuationUnavailable extends StatelessWidget {
  const _InventoryValuationUnavailable();

  @override
  Widget build(BuildContext context) {
    return const AppGlassCard(
      key: Key('inventory-valuation-error'),
      child: Text('Valorización no disponible'),
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

String _formatKilograms(int grams) {
  final whole = grams ~/ 1000;
  final fraction = (grams % 1000).toString().padLeft(3, '0');
  if (fraction == '000') return '$whole';
  return '$whole,${fraction.replaceFirst(RegExp(r'0+$'), '')}';
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

String _formatProductValuation(InventoryProductValuation valuation) {
  return switch (valuation.status) {
    InventoryProductValuationStatus.known =>
      formatInventoryMoneyCents(valuation.valueCents!),
    InventoryProductValuationStatus.unknownCost => 'sin costo conocido',
    InventoryProductValuationStatus.invalidStock ||
    InventoryProductValuationStatus.precisionAnomaly =>
      'no disponible',
  };
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
