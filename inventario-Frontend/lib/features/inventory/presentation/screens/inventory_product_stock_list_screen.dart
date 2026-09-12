import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../../auth/application/authenticated_access_providers.dart';
import '../../../catalog/application/catalog_local_providers.dart';
import '../../../sync/application/operational_bootstrap_entry_providers.dart';
import '../../../sync/data/models/authorized_operational_context_models.dart';
import '../../application/business_product_creation_models.dart';
import '../../application/inventory_transfer_models.dart';
import '../../application/inventory_transfer_providers.dart';
import '../../application/inventory_valuation_models.dart';
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
    this.initialStockFilter = InventoryProductStockFilter.all,
  });

  final String businessId;
  final String branchId;
  final String branchName;
  final String? profileId;
  final String? appDeviceId;
  final String? deviceInstallationId;
  final Set<String> effectivePermissions;
  final InventoryProductStockFilter initialStockFilter;

  @override
  ConsumerState<InventoryProductStockListScreen> createState() =>
      _InventoryProductStockListScreenState();
}

class _InventoryProductStockListScreenState
    extends ConsumerState<InventoryProductStockListScreen> {
  final _searchController = TextEditingController();
  final _minimumStockUpdates = <String>{};
  bool _isCreatingProduct = false;
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
    final valuationSummaryAsync = ref.watch(
      inventoryValuationSummaryProvider(
        InventoryValuationSummaryKey(
          businessId: widget.businessId,
          branchId: widget.branchId,
        ),
      ),
    );
    final hasSearch = _searchTerm.trim().isNotEmpty;
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
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  CronosSpacing.md,
                  CronosSpacing.sm,
                  CronosSpacing.md,
                  0,
                ),
                child: valuationSummaryAsync.when(
                  loading: () => const _InventoryValuationLoading(),
                  error: (_, __) => const _InventoryValuationUnavailable(),
                  data: (summary) => _InventoryValuationSummaryCard(
                    summary: summary,
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

                      if (_stockFilter ==
                          InventoryProductStockFilter.lowStock) {
                        return const _InventoryStateMessage(
                          key: Key('inventory-low-stock-empty'),
                          icon: Icons.inventory_2_outlined,
                          title: 'Sin productos con bajo stock',
                          message:
                              'La sucursal seleccionada no tiene existencias bajo el mínimo.',
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

    return AlertDialog(
      title: const Text('Agregar producto'),
      content: SizedBox(
        width: 640,
        height: 500,
        child: Column(
          children: [
            TextField(
              key: const Key('inventory-add-product-search'),
              controller: _controller,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: const InputDecoration(
                labelText: 'Nombre, marca o código',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: CronosSpacing.md),
            if (loading) const LinearProgressIndicator(),
            Expanded(
              child: hasError
                  ? const _InventoryStateMessage(
                      icon: Icons.error_outline,
                      title: 'No se pudo consultar el catálogo local',
                      message:
                          'Cierra e intenta nuevamente. No se consultó la red.',
                    )
                  : ListView(
                      key: const Key('inventory-add-product-results'),
                      children: [
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
                    ),
            ),
            const SizedBox(height: CronosSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('inventory-create-product-manually'),
                onPressed: () => Navigator.of(context).pop(
                  _InventoryProductSelection.manual(_query),
                ),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Crear manualmente'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
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
      child: Padding(
        padding: const EdgeInsets.all(CronosSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
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
              trailing:
                  isExisting ? const Icon(Icons.check_circle_outline) : null,
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
            if (!isExisting)
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  key: Key('inventory-add-master-$masterId'),
                  onPressed: barcode == null
                      ? null
                      : () => Navigator.of(context).pop(
                            _InventoryProductSelection.master(master),
                          ),
                  child: const Text('Agregar a mi catálogo'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _InventoryProductDraft {
  const _InventoryProductDraft({
    required this.name,
    required this.purchasePrice,
    required this.salePrice,
    required this.minimumStock,
    required this.unit,
    this.barcode,
  });

  final String name;
  final String? barcode;
  final double purchasePrice;
  final double salePrice;
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
  late String _name;
  String? _barcode;
  String _purchasePrice = '0';
  String _salePrice = '0';
  String _minimumStock = '0';
  String _unit = 'unidad';

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
    _unit = _string(master?['master_package_unit']) ??
        _string(master?['master_unit_type']) ??
        'unidad';
  }

  @override
  Widget build(BuildContext context) {
    final fromMaster = widget.masterProduct != null;
    return AlertDialog(
      title: Text(
        fromMaster ? 'Agregar a mi catálogo' : 'Crear producto manualmente',
      ),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                Row(
                  children: [
                    Expanded(
                      child: _DecimalField(
                        fieldKey: const Key('inventory-purchase-price-field'),
                        label: 'Costo',
                        initialValue: _purchasePrice,
                        onChanged: (value) => _purchasePrice = value,
                      ),
                    ),
                    const SizedBox(width: CronosSpacing.sm),
                    Expanded(
                      child: _DecimalField(
                        fieldKey: const Key('inventory-sale-price-field'),
                        label: 'Precio de venta',
                        initialValue: _salePrice,
                        onChanged: (value) => _salePrice = value,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: CronosSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: const Key('inventory-minimum-stock-create-field'),
                        initialValue: _minimumStock,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Stock mínimo',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final parsed = int.tryParse((value ?? '').trim());
                          return parsed == null || parsed < 0
                              ? 'Usa un entero >= 0.'
                              : null;
                        },
                        onChanged: (value) => _minimumStock = value,
                      ),
                    ),
                    const SizedBox(width: CronosSpacing.sm),
                    Expanded(
                      child: TextFormField(
                        key: const Key('inventory-product-unit-field'),
                        initialValue: _unit,
                        decoration: const InputDecoration(
                          labelText: 'Unidad',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (value) => _unit = value,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const Key('inventory-product-create-confirm'),
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) return;
            Navigator.of(context).pop(
              _InventoryProductDraft(
                name: _name.trim(),
                barcode: _string(_barcode),
                purchasePrice: _parseDecimal(_purchasePrice)!,
                salePrice: _parseDecimal(_salePrice)!,
                minimumStock: int.parse(_minimumStock.trim()),
                unit: _string(_unit),
              ),
            );
          },
          child: const Text('Guardar producto'),
        ),
      ],
    );
  }
}

class _DecimalField extends StatelessWidget {
  const _DecimalField({
    required this.fieldKey,
    required this.label,
    required this.initialValue,
    required this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final String initialValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      key: fieldKey,
      initialValue: initialValue,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: (value) {
        final parsed = _parseDecimal(value);
        return parsed == null || parsed < 0 ? 'Usa un valor >= 0.' : null;
      },
      onChanged: onChanged,
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
    final quantityOnHand = _int(product['quantity_on_hand']);
    final isOutOfStock = quantityOnHand <= 0;
    final isLowStock = quantityOnHand > 0 && quantityOnHand <= minimumStock;
    final valuation = product['inventory_valuation'];
    final valuationLabel = valuation is InventoryProductValuation
        ? _formatProductValuation(valuation)
        : 'no disponible';

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
                'Valor: $valuationLabel',
                key: Key('inventory-value-$productId'),
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

double? _parseDecimal(Object? value) {
  final normalized = value?.toString().trim().replaceAll(',', '.');
  if (normalized == null || normalized.isEmpty) return null;
  final parsed = double.tryParse(normalized);
  return parsed != null && parsed.isFinite ? parsed : null;
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
