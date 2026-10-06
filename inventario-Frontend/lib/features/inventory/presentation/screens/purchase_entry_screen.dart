import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../core/models/product_sale_mode.dart';
import '../../../../core/money/cop_price_input.dart';
import '../../../../core/quantity/weight_quantity_input.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../application/business_product_creation_models.dart';
import '../../application/inventory_product_providers.dart';
import '../../application/product_stock_balance_providers.dart';
import '../../application/purchase_local_models.dart';
import '../../application/purchase_money.dart';
import '../../application/purchase_local_provider.dart';
import '../widgets/product_creation_commercial_fields.dart';

class PurchaseEntryScreen extends ConsumerStatefulWidget {
  const PurchaseEntryScreen({
    super.key,
    required this.businessId,
    required this.branchId,
    required this.profileId,
    required this.appDeviceId,
    required this.deviceInstallationId,
    required this.effectivePermissions,
  });

  final String businessId;
  final String branchId;
  final String profileId;
  final String? appDeviceId;
  final String deviceInstallationId;
  final Set<String> effectivePermissions;

  @override
  ConsumerState<PurchaseEntryScreen> createState() =>
      _PurchaseEntryScreenState();
}

class _PurchaseEntryScreenState extends ConsumerState<PurchaseEntryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _supplierNameController = TextEditingController();

  final List<_PurchaseCartItem> _cartItems = [];

  String _query = '';
  bool _isSaving = false;
  bool _isCreatingQuickProduct = false;

  bool get _canViewInventoryCosts =>
      widget.effectivePermissions.contains('inventory.view_costs');

  double get _total {
    final cents = _cartItems.fold<BigInt>(
        BigInt.zero, (sum, item) => sum + (item.subtotalCents ?? BigInt.zero));
    return double.parse(formatPurchaseMoneyCents(cents));
  }

  int get _itemCount {
    return _cartItems.fold<int>(
      0,
      (sum, item) =>
          sum +
          (item.saleModeSnapshot == ProductSaleMode.unit ? item.quantity : 0),
    );
  }

  int get _weightLineCount => _cartItems
      .where((item) => item.saleModeSnapshot == ProductSaleMode.weight)
      .length;

  @override
  void dispose() {
    _searchController.dispose();
    _supplierNameController.dispose();
    super.dispose();
  }

  void _addProductToCart(Map<String, dynamic> product) {
    final productId = _string(product['product_id']);

    if (productId == null) {
      _showMessage('Producto inválido.');
      return;
    }

    final saleMode = ProductSaleMode.parse(product['sale_mode'] ?? 'unit');

    final existingIndex = _cartItems.indexWhere(
      (item) => item.productId == productId,
    );

    if (existingIndex >= 0) {
      setState(() {
        final existing = _cartItems[existingIndex];
        if (existing.saleModeSnapshot != saleMode) {
          _cartItems[existingIndex] = _newCartItem(product, saleMode);
        } else if (saleMode == ProductSaleMode.unit) {
          _cartItems[existingIndex] = existing.copyWith(
            quantity: existing.quantity + 1,
          );
        }
      });

      return;
    }

    setState(() => _cartItems.add(_newCartItem(product, saleMode)));
  }

  _PurchaseCartItem _newCartItem(
    Map<String, dynamic> product,
    ProductSaleMode saleMode,
  ) {
    final productId = _string(product['product_id'])!;
    final productName =
        _string(product['product_name']) ?? 'Producto sin nombre';
    final barcode = _string(product['barcode']);
    final currentStock = _int(product['quantity_available']);

    final purchasePrice = _double(product['purchase_price']);
    final suggestedCost = purchasePrice > 0 || !_canViewInventoryCosts
        ? purchasePrice
        : _double(product['stock_average_cost']);

    return _PurchaseCartItem(
      productId: productId,
      productName: productName,
      barcode: barcode,
      currentStock: currentStock,
      quantity: saleMode == ProductSaleMode.unit ? 1 : 0,
      unitCost: suggestedCost,
      unitCostCents: null,
      saleModeSnapshot: saleMode,
    );
  }

  void _updateWeightedItem(_PurchaseCartItem item) {
    setState(() {
      final index = _cartItems.indexWhere(
        (current) => current.productId == item.productId,
      );
      if (index >= 0 &&
          _cartItems[index].saleModeSnapshot == ProductSaleMode.weight) {
        _cartItems[index] = item;
      }
    });
  }

  void _removeItem(_PurchaseCartItem item) {
    setState(() {
      _cartItems
          .removeWhere((cartItem) => cartItem.productId == item.productId);
    });
  }

  void _incrementItem(_PurchaseCartItem item) {
    setState(() {
      final index = _cartItems.indexWhere(
        (cartItem) => cartItem.productId == item.productId,
      );

      if (index < 0) {
        return;
      }

      _cartItems[index] = _cartItems[index].copyWith(
        quantity: _cartItems[index].quantity + 1,
      );
    });
  }

  void _decrementItem(_PurchaseCartItem item) {
    setState(() {
      final index = _cartItems.indexWhere(
        (cartItem) => cartItem.productId == item.productId,
      );

      if (index < 0) {
        return;
      }

      final current = _cartItems[index];

      if (current.quantity <= 1) {
        _cartItems.removeAt(index);
      } else {
        _cartItems[index] = current.copyWith(quantity: current.quantity - 1);
      }
    });
  }

  Future<void> _editQuantity(_PurchaseCartItem item) async {
    final value = await _askNumber(
      title: 'Cantidad recibida',
      initialValue: item.quantity.toDouble(),
      decimal: false,
    );

    if (!mounted || value == null) {
      return;
    }

    final quantity = value.toInt();

    if (quantity <= 0) {
      _showMessage('La cantidad debe ser mayor a cero.');
      return;
    }

    setState(() {
      final index = _cartItems.indexWhere(
        (cartItem) => cartItem.productId == item.productId,
      );

      if (index >= 0) {
        _cartItems[index] = _cartItems[index].copyWith(quantity: quantity);
      }
    });
  }

  Future<void> _editUnitCost(_PurchaseCartItem item) async {
    var costText = item.unitCostCents == null
        ? ''
        : formatPurchaseMoneyCents(item.unitCostCents!);
    String? costError;
    final value = await showDialog<BigInt>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, updateDialog) {
          return AlertDialog(
            title: const Text('Costo unitario'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: costText,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Pesos, máximo 2 decimales',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (text) => costText = text,
                ),
                if (costError != null) Text(costError!),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = parsePurchaseMoneyCents(costText);
                  if (parsed == null || parsed <= BigInt.zero) {
                    updateDialog(() => costError =
                        'Ingresa un costo mayor que cero, sin más de 2 decimales.');
                    return;
                  }
                  Navigator.of(dialogContext).pop(parsed);
                },
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    if (!mounted || value == null) {
      return;
    }

    setState(() {
      final index = _cartItems.indexWhere(
        (cartItem) => cartItem.productId == item.productId,
      );

      if (index >= 0) {
        _cartItems[index] = _cartItems[index].copyWith(
          unitCost: double.parse(formatPurchaseMoneyCents(value)),
          unitCostCents: value,
        );
      }
    });
  }

  Future<double?> _askNumber({
    required String title,
    required double initialValue,
    required bool decimal,
  }) async {
    var currentText = decimal
        ? initialValue.toStringAsFixed(2)
        : initialValue.toInt().toString();

    return showDialog<double>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: TextFormField(
            initialValue: currentText,
            autofocus: true,
            keyboardType: TextInputType.numberWithOptions(decimal: decimal),
            decoration: InputDecoration(
              labelText: decimal ? 'Valor' : 'Cantidad',
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) {
              currentText = value;
            },
            onFieldSubmitted: (_) {
              Navigator.of(dialogContext).pop(_parseNumber(currentText));
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(_parseNumber(currentText));
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );
  }

  void _addBusinessProductToCart(BusinessProductCreationResult result) {
    final product = result.product;
    if (product == null || result.productId == null) {
      _showMessage('El producto local no pudo resolverse.');
      return;
    }

    _addProductToCart({
      'product_id': result.productId,
      'product_name': _string(product['name']) ?? 'Producto sin nombre',
      'barcode': result.barcode ?? _string(product['barcode']),
      'quantity_available': 0,
      'purchase_price': _double(product['purchase_price']),
      'stock_average_cost': 0,
      'sale_mode': product['sale_mode'] ?? 'unit',
    });
  }

  Future<void> _openQuickProductDialog() async {
    if (_isCreatingQuickProduct || _isSaving) {
      return;
    }

    final commercial = ProductCreationCommercialController();
    final draft = await showDialog<_QuickProductDraft>(
      context: context,
      builder: (dialogContext) {
        final formKey = GlobalKey<FormState>();

        var name = '';
        var barcode = '';

        return AlertDialog(
          scrollable: true,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: CronosSpacing.md,
            vertical: CronosSpacing.md,
          ),
          title: const Text('Crear producto rápido'),
          content: SizedBox(
            width:
                (MediaQuery.sizeOf(dialogContext).width - 64).clamp(0.0, 620.0),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del producto',
                      prefixIcon: Icon(Icons.inventory_2_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) {
                        return 'El nombre es requerido.';
                      }

                      if ((value ?? '').trim().length < 2) {
                        return 'El nombre es demasiado corto.';
                      }

                      return null;
                    },
                    onChanged: (value) {
                      name = value;
                    },
                  ),
                  const SizedBox(height: CronosSpacing.md),
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Código / barcode opcional',
                      prefixIcon: Icon(Icons.qr_code_2_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      barcode = value;
                    },
                  ),
                  const SizedBox(height: CronosSpacing.md),
                  ProductCreationCommercialFields(
                    controller: commercial,
                    keyPrefix: 'purchase-product',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () {
                final valid = formKey.currentState?.validate() ?? false;

                if (!valid) {
                  return;
                }

                Navigator.of(dialogContext).pop(
                  _QuickProductDraft(
                    name: name.trim(),
                    barcode: barcode.trim().isEmpty ? null : barcode.trim(),
                    saleMode: commercial.saleMode,
                    salePriceCents: commercial.salePriceCents!,
                    minimumStock: commercial.minimumStock!,
                    unit: commercial.unitForPersistence,
                  ),
                );
              },
              icon: const Icon(Icons.add_box_outlined),
              label: const Text('Continuar'),
            ),
          ],
        );
      },
    );
    commercial.dispose();

    if (!mounted || draft == null) {
      return;
    }

    setState(() {
      _isCreatingQuickProduct = true;
    });

    try {
      final service = ref.read(businessProductCreationServiceProvider);
      final productContext = BusinessProductCreationContext(
        businessId: widget.businessId,
        branchId: widget.branchId,
        profileId: widget.profileId,
        appDeviceId: widget.appDeviceId,
        deviceInstallationId: widget.deviceInstallationId,
        effectivePermissions: widget.effectivePermissions,
      );
      final resolution = await service.resolveCode(
        context: productContext,
        code: draft.barcode,
      );

      if (!mounted) {
        return;
      }
      if (resolution.type == BusinessProductCodeResolutionType.invalid) {
        _showMessage(resolution.message);
        return;
      }

      var confirmedDraft = draft;
      if (resolution.hasMasterSuggestion) {
        final confirmation = await _confirmMasterSuggestion(
          draft: draft,
          masterProduct: resolution.masterProduct,
        );
        if (!mounted || confirmation == null) {
          return;
        }
        confirmedDraft = confirmation;
      }

      final result = await service.createOrUse(
        context: productContext,
        code: confirmedDraft.barcode,
        fields: BusinessProductOwnedFields(
          name: confirmedDraft.name,
          purchasePrice: 0,
          salePrice: confirmedDraft.salePriceCents / 100,
          saleMode: confirmedDraft.saleMode,
          salePriceCents: confirmedDraft.salePriceCents,
          minimumStock: confirmedDraft.minimumStock,
          unit: confirmedDraft.unit,
        ),
      );

      if (!mounted) {
        return;
      }
      if (!result.succeeded) {
        _showMessage(result.message);
        return;
      }

      ref.invalidate(
        localProductsWithStockProvider(
          ProductsWithLocalStockKey(
            businessId: widget.businessId,
            branchId: widget.branchId,
            limit: 250,
          ),
        ),
      );

      final productName =
          _string(result.product?['name']) ?? confirmedDraft.name;
      setState(() {
        _searchController.text = productName;
        _query = productName;
      });

      _addBusinessProductToCart(result);

      _showMessage(
        '$productName se agregó a la compra. El stock se actualizará al registrarla.',
      );
    } catch (_) {
      _showMessage(
        'No se pudo completar la operación local del producto. Intenta nuevamente.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingQuickProduct = false;
        });
      }
    }
  }

  Future<_QuickProductDraft?> _confirmMasterSuggestion({
    required _QuickProductDraft draft,
    required Map<String, dynamic>? masterProduct,
  }) {
    var name = _string(
          masterProduct?['product_name'] ?? masterProduct?['name'],
        ) ??
        draft.name;
    final brand = _string(masterProduct?['brand']);
    final packageSize = _string(masterProduct?['package_size']);
    final packageUnit = _string(masterProduct?['package_unit']);

    return showDialog<_QuickProductDraft>(
      context: context,
      builder: (dialogContext) {
        final formKey = GlobalKey<FormState>();
        return AlertDialog(
          title: const Text('Coincidencia en catálogo local'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    if (brand != null) 'Marca: $brand',
                    if (packageSize != null || packageUnit != null)
                      'Presentación: ${[
                        packageSize,
                        packageUnit
                      ].whereType<String>().join(' ')}',
                  ].isEmpty
                      ? 'Encontramos información de este producto para el código.'
                      : [
                          if (brand != null) 'Marca: $brand',
                          if (packageSize != null || packageUnit != null)
                            'Presentación: ${[
                              packageSize,
                              packageUnit
                            ].whereType<String>().join(' ')}',
                        ].join('\n'),
                ),
                const SizedBox(height: CronosSpacing.md),
                TextFormField(
                  initialValue: name,
                  decoration: const InputDecoration(
                    labelText: 'Nombre para este negocio',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().length < 2
                      ? 'El nombre es requerido.'
                      : null,
                  onChanged: (value) => name = value,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) {
                  return;
                }
                Navigator.of(dialogContext).pop(
                  draft.copyWith(name: name.trim()),
                );
              },
              child: const Text('Usar sugerencia'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _savePurchase() async {
    if (_isSaving) {
      return;
    }

    if (_cartItems.isEmpty) {
      _showMessage('Agrega al menos un producto a la compra.');
      return;
    }

    final invalidWeight = _cartItems.where(
      (item) =>
          item.saleModeSnapshot == ProductSaleMode.weight &&
          (item.weightQuantityError != null ||
              item.weightCostError != null ||
              item.subtotalCents == null),
    );
    if (invalidWeight.isNotEmpty) {
      final item = invalidWeight.first;
      _showMessage(item.weightQuantityError ??
          item.weightCostError ??
          'El total de la compra supera el límite permitido.');
      return;
    }

    final invalidUnit = _cartItems.any((item) =>
        item.saleModeSnapshot == ProductSaleMode.unit &&
        (item.unitCostCents == null ||
            item.unitCostCents! <= BigInt.zero ||
            item.subtotalCents == null));
    if (invalidUnit) {
      _showMessage(
          'Ingresa un costo unitario mayor que cero para cada producto.');
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final service = ref.read(purchaseLocalServiceProvider);

      final result = await service.createLocalPurchase(
        CreatePurchaseLocalInput(
          businessId: widget.businessId,
          branchId: widget.branchId,
          profileId: widget.profileId,
          appDeviceId: widget.appDeviceId,
          deviceInstallationId: widget.deviceInstallationId,
          supplierName: _supplierNameController.text.trim().isEmpty
              ? null
              : _supplierNameController.text.trim(),
          items: _cartItems
              .map(
                (item) => PurchaseLocalItemInput(
                  productId: item.productId,
                  quantity: item.effectiveQuantity,
                  unitCostCents: item.effectiveCostCents!,
                  saleModeSnapshot: item.saleModeSnapshot,
                  costBasisQuantitySnapshot:
                      item.saleModeSnapshot == ProductSaleMode.unit
                          ? 1
                          : item.costBasisQuantitySnapshot,
                ),
              )
              .toList(),
          metadata: const {
            'ui': 'purchase_entry_screen',
            'source': 'purchase_ui',
          },
        ),
      );

      var weightedOutboxReady = true;
      if (_cartItems.any(
        (item) => item.saleModeSnapshot == ProductSaleMode.weight,
      )) {
        try {
          final queued = await ref
              .read(purchaseSyncOutboxServiceProvider)
              .enqueueCreatedPurchase(
                businessId: widget.businessId,
                branchId: widget.branchId,
                profileId: widget.profileId,
                purchaseId: result.purchaseId,
                appDeviceId: widget.appDeviceId,
                deviceInstallationId: widget.deviceInstallationId,
              );
          weightedOutboxReady = queued.purchasesEnqueued == 1;
        } catch (_) {
          // The local receipt is already committed. The normal manual or
          // scheduled sync path can prepare this dirty purchase later.
          weightedOutboxReady = false;
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _cartItems.clear();
        _supplierNameController.clear();
        _searchController.clear();
        _query = '';
      });

      _showMessage(weightedOutboxReady
          ? 'Compra de ${_money(result.total)} guardada. El stock ya se actualizó.'
          : 'Compra guardada y stock actualizado. La sincronización sigue pendiente.');
    } catch (_) {
      _showMessage(
          'No pudimos registrar la compra. Revisa los datos e inténtalo nuevamente.');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.maybeOf(context);

    if (messenger == null) {
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  List<Map<String, dynamic>> _filterProducts(List<Map<String, dynamic>> items) {
    final normalizedQuery = _query.trim().toLowerCase();

    if (normalizedQuery.isEmpty) {
      return items;
    }

    return items.where((product) {
      final name = (_string(product['product_name']) ?? '').toLowerCase();
      final barcode = (_string(product['barcode']) ?? '').toLowerCase();

      return name.contains(normalizedQuery) ||
          barcode.contains(normalizedQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(
      localProductsWithStockProvider(
        ProductsWithLocalStockKey(
          businessId: widget.businessId,
          branchId: widget.branchId,
          limit: 250,
        ),
      ),
    );

    return Theme(
      data: CronosTheme.light(),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Compras'),
          actions: [
            IconButton(
              onPressed: _isSaving
                  ? null
                  : () {
                      ref.invalidate(
                        localProductsWithStockProvider(
                          ProductsWithLocalStockKey(
                            businessId: widget.businessId,
                            branchId: widget.branchId,
                            limit: 250,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.refresh_outlined),
              tooltip: 'Actualizar',
            ),
          ],
        ),
        body: AppGradientBackground(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 900;

              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _ProductsPanel(
                        scrollablePanel: true,
                        searchController: _searchController,
                        query: _query,
                        canViewInventoryCosts: _canViewInventoryCosts,
                        productsAsync: productsAsync,
                        filterProducts: _filterProducts,
                        onQueryChanged: (value) {
                          setState(() {
                            _query = value;
                          });
                        },
                        onProductTap: _addProductToCart,
                        onCreateQuickProduct: _openQuickProductDialog,
                      ),
                    ),
                    Expanded(
                      flex: 4,
                      child: _PurchaseCartPanel(
                        scrollablePanel: true,
                        supplierNameController: _supplierNameController,
                        items: _cartItems,
                        total: _total,
                        itemCount: _itemCount,
                        weightLineCount: _weightLineCount,
                        isSaving: _isSaving,
                        onIncrement: _incrementItem,
                        onDecrement: _decrementItem,
                        onRemove: _removeItem,
                        onEditQuantity: _editQuantity,
                        onEditUnitCost: _editUnitCost,
                        onUpdateWeight: _updateWeightedItem,
                        onSave: _savePurchase,
                      ),
                    ),
                  ],
                );
              }

              return ListView(
                padding: const EdgeInsets.all(CronosSpacing.md),
                children: [
                  _PurchaseCartPanel(
                    supplierNameController: _supplierNameController,
                    items: _cartItems,
                    total: _total,
                    itemCount: _itemCount,
                    weightLineCount: _weightLineCount,
                    isSaving: _isSaving,
                    onIncrement: _incrementItem,
                    onDecrement: _decrementItem,
                    onRemove: _removeItem,
                    onEditQuantity: _editQuantity,
                    onEditUnitCost: _editUnitCost,
                    onUpdateWeight: _updateWeightedItem,
                    onSave: _savePurchase,
                  ),
                  const SizedBox(height: CronosSpacing.md),
                  _ProductsPanel(
                    searchController: _searchController,
                    query: _query,
                    canViewInventoryCosts: _canViewInventoryCosts,
                    productsAsync: productsAsync,
                    filterProducts: _filterProducts,
                    onQueryChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                    onProductTap: _addProductToCart,
                    onCreateQuickProduct: _openQuickProductDialog,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String? _string(Object? value) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) {
      return null;
    }

    return text;
  }

  static int _int(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _double(Object? value) {
    if (value is double) {
      return value;
    }

    if (value is int) {
      return value.toDouble();
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _parseNumber(String value) {
    final normalized = value.trim().replaceAll(',', '.');

    if (normalized.isEmpty) {
      return null;
    }

    return double.tryParse(normalized);
  }

  static String _money(double value) {
    return '\$${value.toStringAsFixed(0)}';
  }
}

class _ProductsPanel extends StatelessWidget {
  const _ProductsPanel({
    this.scrollablePanel = false,
    required this.searchController,
    required this.query,
    required this.canViewInventoryCosts,
    required this.productsAsync,
    required this.filterProducts,
    required this.onQueryChanged,
    required this.onProductTap,
    required this.onCreateQuickProduct,
  });

  final bool scrollablePanel;
  final TextEditingController searchController;
  final String query;
  final bool canViewInventoryCosts;
  final AsyncValue<List<Map<String, dynamic>>> productsAsync;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)
      filterProducts;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Map<String, dynamic>> onProductTap;
  final VoidCallback onCreateQuickProduct;

  @override
  Widget build(BuildContext context) {
    final results = productsAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(CronosSpacing.lg),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (error, _) => const AppEmptyState(
        icon: Icons.error_outline,
        title: 'No se pudieron cargar productos',
        message: 'No pudimos cargar los productos. Vuelve a intentarlo.',
      ),
      data: (products) {
        final filtered = filterProducts(products);
        if (filtered.isEmpty) {
          return const AppEmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Sin productos',
            message:
                'Sincroniza catálogo o crea productos antes de registrar compras.',
          );
        }
        final list = ListView.separated(
          key: const Key('purchase-products-scroll'),
          primary: false,
          padding: EdgeInsets.zero,
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const SizedBox(height: CronosSpacing.sm),
          itemBuilder: (context, index) {
            final product = filtered[index];
            return _ProductPurchaseTile(
              product: product,
              canViewInventoryCosts: canViewInventoryCosts,
              onTap: () => onProductTap(product),
            );
          },
        );
        if (scrollablePanel) return list;
        final listHeight = (MediaQuery.sizeOf(context).height * 0.52)
            .clamp(280.0, 620.0)
            .toDouble();
        return SizedBox(height: listHeight, child: list);
      },
    );
    return Padding(
      padding: const EdgeInsets.all(CronosSpacing.md),
      child: AppGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Productos',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: CronosSpacing.sm),
            TextField(
              controller: searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar por nombre o código',
                prefixIcon: Icon(Icons.search_outlined),
                border: OutlineInputBorder(),
              ),
              onChanged: onQueryChanged,
            ),
            const SizedBox(height: CronosSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onCreateQuickProduct,
                icon: const Icon(Icons.add_box_outlined),
                label: const Text('Crear producto rápido'),
              ),
            ),
            const SizedBox(height: CronosSpacing.md),
            if (scrollablePanel) Expanded(child: results) else results,
          ],
        ),
      ),
    );
  }
}

class _ProductPurchaseTile extends StatelessWidget {
  const _ProductPurchaseTile({
    required this.product,
    required this.canViewInventoryCosts,
    required this.onTap,
  });

  final Map<String, dynamic> product;
  final bool canViewInventoryCosts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = _PurchaseEntryScreenState._string(product['product_name']) ??
        'Producto sin nombre';
    final barcode = _PurchaseEntryScreenState._string(product['barcode']);
    final stock = _PurchaseEntryScreenState._int(product['quantity_available']);
    final purchasePrice =
        _PurchaseEntryScreenState._double(product['purchase_price']);
    final isWeight = product['sale_mode'] == ProductSaleMode.weight.wireValue;
    final suggestedCost = purchasePrice > 0 || !canViewInventoryCosts
        ? purchasePrice
        : _PurchaseEntryScreenState._double(product['stock_average_cost']);

    return Material(
      color: Colors.white.withValues(alpha: 0.78),
      borderRadius: BorderRadius.circular(CronosRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(CronosRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(CronosSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ProductImage(
                    key: ValueKey(
                      'purchase-product-image-${product['product_id']}',
                    ),
                    barcode: barcode,
                    size: 48,
                    semanticLabel: 'Imagen de $name',
                  ),
                  const SizedBox(width: CronosSpacing.sm),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      softWrap: true,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(width: CronosSpacing.sm),
                  const Icon(Icons.add_circle_outline),
                ],
              ),
              const SizedBox(height: CronosSpacing.sm),
              Wrap(
                spacing: CronosSpacing.sm,
                runSpacing: CronosSpacing.xs,
                children: [
                  _PurchaseMetricPill(
                    icon: Icons.warehouse_outlined,
                    label: isWeight ? 'Stock $stock g' : 'Stock $stock',
                  ),
                  _PurchaseMetricPill(
                    icon: Icons.sell_outlined,
                    label: isWeight
                        ? 'Costo: confirmar base al comprar'
                        : 'Costo ${_PurchaseEntryScreenState._money(suggestedCost)}',
                  ),
                  if (barcode != null)
                    _PurchaseMetricPill(
                      icon: Icons.qr_code_2_outlined,
                      label: barcode,
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

class _PurchaseCartPanel extends StatelessWidget {
  const _PurchaseCartPanel({
    this.scrollablePanel = false,
    required this.supplierNameController,
    required this.items,
    required this.total,
    required this.itemCount,
    required this.weightLineCount,
    required this.isSaving,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onEditQuantity,
    required this.onEditUnitCost,
    required this.onUpdateWeight,
    required this.onSave,
  });

  final bool scrollablePanel;
  final TextEditingController supplierNameController;
  final List<_PurchaseCartItem> items;
  final double total;
  final int itemCount;
  final int weightLineCount;
  final bool isSaving;
  final ValueChanged<_PurchaseCartItem> onIncrement;
  final ValueChanged<_PurchaseCartItem> onDecrement;
  final ValueChanged<_PurchaseCartItem> onRemove;
  final ValueChanged<_PurchaseCartItem> onEditQuantity;
  final ValueChanged<_PurchaseCartItem> onEditUnitCost;
  final ValueChanged<_PurchaseCartItem> onUpdateWeight;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      Text('Compra actual', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: CronosSpacing.sm),
      TextField(
        controller: supplierNameController,
        decoration: const InputDecoration(
          labelText: 'Proveedor opcional',
          prefixIcon: Icon(Icons.local_shipping_outlined),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: CronosSpacing.md),
      if (items.isEmpty)
        const AppEmptyState(
          icon: Icons.add_shopping_cart_outlined,
          title: 'Sin productos',
          message: 'Agrega productos desde el listado para reponer stock.',
        )
      else
        for (final item in items) ...[
          _PurchaseCartTile(
            key: ValueKey(
                'purchase-cart-${item.productId}-${item.saleModeSnapshot.wireValue}'),
            item: item,
            onIncrement: () => onIncrement(item),
            onDecrement: () => onDecrement(item),
            onRemove: () => onRemove(item),
            onEditQuantity: () => onEditQuantity(item),
            onEditUnitCost: () => onEditUnitCost(item),
            onUpdateWeight: onUpdateWeight,
          ),
          const SizedBox(height: CronosSpacing.sm),
        ],
      const SizedBox(height: CronosSpacing.md),
      Wrap(
        spacing: CronosSpacing.sm,
        runSpacing: CronosSpacing.sm,
        children: [
          _PurchaseMetricPill(
            icon: Icons.format_list_numbered_outlined,
            label: weightLineCount == 0
                ? '$itemCount uds.'
                : itemCount == 0
                    ? '$weightLineCount por peso'
                    : '$itemCount uds. · $weightLineCount por peso',
          ),
          _PurchaseMetricPill(
            icon: Icons.payments_outlined,
            label: _PurchaseEntryScreenState._money(total),
          ),
        ],
      ),
      const SizedBox(height: CronosSpacing.md),
      SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: isSaving ? null : onSave,
          icon: isSaving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(isSaving ? 'Guardando compra...' : 'Registrar compra'),
        ),
      ),
    ];
    return Padding(
      padding: const EdgeInsets.all(CronosSpacing.md),
      child: AppGlassCard(
        child: scrollablePanel
            ? ListView(
                key: const Key('purchase-cart-scroll'),
                primary: false,
                children: children,
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
      ),
    );
  }
}

class _PurchaseCartTile extends StatelessWidget {
  const _PurchaseCartTile({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onEditQuantity,
    required this.onEditUnitCost,
    required this.onUpdateWeight,
  });

  final _PurchaseCartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final VoidCallback onEditQuantity;
  final VoidCallback onEditUnitCost;
  final ValueChanged<_PurchaseCartItem> onUpdateWeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(CronosSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(CronosRadius.md),
        border: Border.all(
          color: CronosColors.textMuted.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_outlined),
              const SizedBox(width: CronosSpacing.sm),
              Expanded(
                child: Text(
                  item.productName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Quitar',
              ),
            ],
          ),
          if (item.barcode != null)
            Text(
              item.barcode!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const SizedBox(height: CronosSpacing.sm),
          Wrap(
            spacing: CronosSpacing.sm,
            runSpacing: CronosSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _PurchaseMetricPill(
                icon: Icons.warehouse_outlined,
                label: item.saleModeSnapshot == ProductSaleMode.weight
                    ? 'Stock ${item.currentStock} g'
                    : 'Stock ${item.currentStock}',
              ),
              if (item.saleModeSnapshot == ProductSaleMode.unit)
                _PurchaseMetricPill(
                  icon: Icons.receipt_long_outlined,
                  label:
                      'Subt. ${_PurchaseEntryScreenState._money(item.subtotal)}',
                ),
            ],
          ),
          const SizedBox(height: CronosSpacing.sm),
          if (item.saleModeSnapshot == ProductSaleMode.weight) ...[
            _WeightPurchaseInputs(item: item, onChanged: onUpdateWeight),
            const SizedBox(height: CronosSpacing.sm),
            Text(
              'Total: ${item.subtotalCents == null ? "—" : formatCopPriceCents(item.subtotalCents!.toInt())}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: ValueKey('purchase-unit-cost-${item.productId}'),
                onPressed: onEditUnitCost,
                icon: const Icon(Icons.edit_outlined),
                label: Text(
                  'Costo unitario: '
                  '${item.unitCostCents == null ? "Confirmar costo" : _PurchaseEntryScreenState._money(item.unitCost)} · Editar',
                ),
              ),
            ),
            const SizedBox(height: CronosSpacing.sm),
            Wrap(
              spacing: CronosSpacing.sm,
              runSpacing: CronosSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton.outlined(
                  onPressed: onDecrement,
                  icon: const Icon(Icons.remove),
                ),
                TextButton(
                  onPressed: onEditQuantity,
                  child: Text('Cantidad: ${item.quantity}'),
                ),
                IconButton.outlined(
                  onPressed: onIncrement,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WeightPurchaseInputs extends StatelessWidget {
  const _WeightPurchaseInputs({required this.item, required this.onChanged});

  final _PurchaseCartItem item;
  final ValueChanged<_PurchaseCartItem> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('purchase-weight-quantity-${item.productId}'),
                initialValue: item.weightQuantityText,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Cantidad',
                  errorText: item.weightQuantityText.isEmpty
                      ? null
                      : item.weightQuantityError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (text) => onChanged(item.withWeightDraft(
                  quantityText: text,
                )),
              ),
            ),
            const SizedBox(width: CronosSpacing.sm),
            SizedBox(
              width: 155,
              child: DropdownButtonFormField<WeightInputUnit>(
                key: ValueKey('purchase-weight-unit-${item.productId}'),
                initialValue: item.weightQuantityUnit,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(
                      value: WeightInputUnit.kilogram, child: Text('kg')),
                  DropdownMenuItem(
                      value: WeightInputUnit.commercialPound,
                      child: Text('libra (500 g)',
                          overflow: TextOverflow.ellipsis)),
                  DropdownMenuItem(
                      value: WeightInputUnit.gram, child: Text('g')),
                ],
                onChanged: (unit) {
                  if (unit != null) {
                    onChanged(item.withWeightDraft(quantityUnit: unit));
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: CronosSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: ValueKey('purchase-weight-cost-${item.productId}'),
                initialValue: item.weightCostText,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Costo',
                  errorText:
                      item.weightCostText.isEmpty ? null : item.weightCostError,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (text) =>
                    onChanged(item.withWeightDraft(costText: text)),
              ),
            ),
            const SizedBox(width: CronosSpacing.sm),
            SizedBox(
              width: 155,
              child: DropdownButtonFormField<int>(
                key: ValueKey('purchase-weight-basis-${item.productId}'),
                initialValue: item.costBasisQuantitySnapshot,
                isExpanded: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 500, child: Text('por libra')),
                  DropdownMenuItem(value: 1000, child: Text('por kg')),
                ],
                onChanged: (basis) {
                  if (basis != null) {
                    onChanged(item.withWeightDraft(costBasis: basis));
                  }
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickProductDraft {
  const _QuickProductDraft({
    required this.name,
    required this.saleMode,
    required this.salePriceCents,
    required this.minimumStock,
    required this.unit,
    this.barcode,
  });

  final String name;
  final String? barcode;
  final ProductSaleMode saleMode;
  final int salePriceCents;
  final int minimumStock;
  final String? unit;

  _QuickProductDraft copyWith({String? name}) {
    return _QuickProductDraft(
      name: name ?? this.name,
      saleMode: saleMode,
      salePriceCents: salePriceCents,
      minimumStock: minimumStock,
      unit: unit,
      barcode: barcode,
    );
  }
}

class _PurchaseMetricPill extends StatelessWidget {
  const _PurchaseMetricPill({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(
        horizontal: CronosSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: CronosColors.textMuted.withValues(alpha: 0.16),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseCartItem {
  const _PurchaseCartItem({
    required this.productId,
    required this.productName,
    required this.barcode,
    required this.currentStock,
    required this.quantity,
    required this.unitCost,
    required this.unitCostCents,
    this.saleModeSnapshot = ProductSaleMode.unit,
    this.weightQuantityText = '',
    this.weightQuantityUnit = WeightInputUnit.kilogram,
    this.weightCostText = '',
    this.costBasisQuantitySnapshot = 500,
  });

  final String productId;
  final String productName;
  final String? barcode;
  final int currentStock;
  final int quantity;
  final double unitCost;
  final BigInt? unitCostCents;
  final ProductSaleMode saleModeSnapshot;
  final String weightQuantityText;
  final WeightInputUnit weightQuantityUnit;
  final String weightCostText;
  final int costBasisQuantitySnapshot;

  int get effectiveQuantity => saleModeSnapshot == ProductSaleMode.weight
      ? parseWeightQuantity(weightQuantityText, weightQuantityUnit) ?? 0
      : quantity;

  BigInt? get effectiveCostCents {
    if (saleModeSnapshot == ProductSaleMode.unit) return unitCostCents;
    final cents = parseCopPriceCents(weightCostText);
    return cents == null ? null : BigInt.from(cents);
  }

  String? get weightQuantityError {
    if (effectiveQuantity > 0) return null;
    if (weightQuantityText.trim().isEmpty) {
      return 'Ingresa una cantidad válida.';
    }
    if (RegExp(r'^0+(?:[.,]0+)?$').hasMatch(weightQuantityText.trim())) {
      return 'La cantidad debe ser mayor que cero.';
    }
    return switch (weightQuantityUnit) {
      WeightInputUnit.kilogram => 'Los kilogramos admiten hasta 3 decimales.',
      WeightInputUnit.commercialPound =>
        'Las libras admiten hasta 2 decimales.',
      WeightInputUnit.gram => 'Ingresa gramos enteros.',
    };
  }

  String? get weightCostError {
    final cents = effectiveCostCents;
    return cents != null && cents > BigInt.zero
        ? null
        : 'Ingresa un costo válido mayor que cero.';
  }

  BigInt? get subtotalCents {
    final cost = effectiveCostCents;
    final count = effectiveQuantity;
    if (cost == null || cost <= BigInt.zero || count <= 0) return null;
    try {
      return purchaseBasisLineTotalCents(
        quotedCostCents: cost,
        quantity: count,
        costBasisQuantity: saleModeSnapshot == ProductSaleMode.unit
            ? 1
            : costBasisQuantitySnapshot,
      );
    } on ArgumentError {
      return null;
    }
  }

  _PurchaseCartItem withWeightDraft({
    String? quantityText,
    WeightInputUnit? quantityUnit,
    String? costText,
    int? costBasis,
  }) =>
      _PurchaseCartItem(
        productId: productId,
        productName: productName,
        barcode: barcode,
        currentStock: currentStock,
        quantity: 0,
        unitCost: 0,
        unitCostCents: null,
        saleModeSnapshot: ProductSaleMode.weight,
        weightQuantityText: quantityText ?? weightQuantityText,
        weightQuantityUnit: quantityUnit ?? weightQuantityUnit,
        weightCostText: costText ?? weightCostText,
        costBasisQuantitySnapshot: costBasis ?? costBasisQuantitySnapshot,
      );

  double get subtotal => subtotalCents == null
      ? 0
      : double.parse(formatPurchaseMoneyCents(subtotalCents!));

  _PurchaseCartItem copyWith({
    int? currentStock,
    int? quantity,
    double? unitCost,
    BigInt? unitCostCents,
  }) {
    return _PurchaseCartItem(
      productId: productId,
      productName: productName,
      barcode: barcode,
      currentStock: currentStock ?? this.currentStock,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
      unitCostCents: unitCostCents ?? this.unitCostCents,
      saleModeSnapshot: saleModeSnapshot,
      weightQuantityText: weightQuantityText,
      weightQuantityUnit: weightQuantityUnit,
      weightCostText: weightCostText,
      costBasisQuantitySnapshot: costBasisQuantitySnapshot,
    );
  }
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    this.icon,
    required this.title,
    this.message,
    this.description,
    this.subtitle,
    this.body,
    this.action,
    this.actions,
  });

  final IconData? icon;
  final String title;
  final String? message;
  final String? description;
  final String? subtitle;
  final String? body;
  final Widget? action;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final detail = description ?? subtitle ?? message ?? body;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon ?? Icons.inventory_2_outlined,
                size: 48,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (detail != null && detail.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  detail,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: 16),
                action!,
              ],
              if (actions != null && actions!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
