import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../application/business_product_creation_models.dart';
import '../../application/inventory_product_providers.dart';
import '../../application/product_stock_balance_providers.dart';
import '../../application/purchase_local_models.dart';
import '../../application/purchase_local_provider.dart';
import '../../application/purchase_sync_repair_provider.dart';
import '../../../sync/application/local_sync_outbox_providers.dart';
import '../../../sync/application/purchases_sync_upload_provider.dart';

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
  bool _isSyncingPurchases = false;
  bool _isCreatingQuickProduct = false;

  double get _total {
    return _cartItems.fold<double>(
      0,
      (sum, item) => sum + item.subtotal,
    );
  }

  int get _itemCount {
    return _cartItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );
  }

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

    final existingIndex = _cartItems.indexWhere(
      (item) => item.productId == productId,
    );

    if (existingIndex >= 0) {
      setState(() {
        final existing = _cartItems[existingIndex];
        _cartItems[existingIndex] = existing.copyWith(
          quantity: existing.quantity + 1,
        );
      });

      return;
    }

    final productName =
        _string(product['product_name']) ?? 'Producto sin nombre';
    final barcode = _string(product['barcode']);
    final currentStock = _int(product['quantity_available']);

    final purchasePrice = _double(product['purchase_price']);
    final averageCost = _double(product['stock_average_cost']);
    final suggestedCost = purchasePrice > 0 ? purchasePrice : averageCost;

    setState(() {
      _cartItems.add(
        _PurchaseCartItem(
          productId: productId,
          productName: productName,
          barcode: barcode,
          currentStock: currentStock,
          quantity: 1,
          unitCost: suggestedCost,
        ),
      );
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
    final value = await _askNumber(
      title: 'Costo unitario',
      initialValue: item.unitCost,
      decimal: true,
    );

    if (!mounted || value == null) {
      return;
    }

    if (value < 0) {
      _showMessage('El costo unitario no puede ser negativo.');
      return;
    }

    setState(() {
      final index = _cartItems.indexWhere(
        (cartItem) => cartItem.productId == item.productId,
      );

      if (index >= 0) {
        _cartItems[index] = _cartItems[index].copyWith(unitCost: value);
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
    });
  }

  Future<void> _openQuickProductDialog() async {
    if (_isCreatingQuickProduct || _isSaving || _isSyncingPurchases) {
      return;
    }

    final draft = await showDialog<_QuickProductDraft>(
      context: context,
      builder: (dialogContext) {
        final formKey = GlobalKey<FormState>();

        var name = '';
        var barcode = '';
        var purchaseCostText = '';
        var salePriceText = '';
        var minimumStockText = '0';
        var unit = 'unidad';

        return AlertDialog(
          title: const Text('Crear producto rápido'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
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
                  TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Costo de compra',
                      prefixIcon: Icon(Icons.sell_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final parsed = _parseNumber(value ?? '');

                      if (parsed == null || parsed <= 0) {
                        return 'El costo debe ser mayor a cero.';
                      }

                      return null;
                    },
                    onChanged: (value) {
                      purchaseCostText = value;
                    },
                  ),
                  const SizedBox(height: CronosSpacing.md),
                  TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Precio de venta opcional',
                      prefixIcon: Icon(Icons.point_of_sale_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final raw = (value ?? '').trim();

                      if (raw.isEmpty) {
                        return null;
                      }

                      final parsed = _parseNumber(raw);

                      if (parsed == null || parsed < 0) {
                        return 'El precio de venta no puede ser negativo.';
                      }

                      return null;
                    },
                    onChanged: (value) {
                      salePriceText = value;
                    },
                  ),
                  const SizedBox(height: CronosSpacing.md),
                  TextFormField(
                    initialValue: '0',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stock mínimo',
                      prefixIcon: Icon(Icons.notification_important_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      final parsed = int.tryParse((value ?? '').trim());
                      if (parsed == null || parsed < 0) {
                        return 'Usa un entero igual o mayor a cero.';
                      }
                      return null;
                    },
                    onChanged: (value) {
                      minimumStockText = value;
                    },
                  ),
                  const SizedBox(height: CronosSpacing.md),
                  TextFormField(
                    initialValue: 'unidad',
                    decoration: const InputDecoration(
                      labelText: 'Unidad',
                      prefixIcon: Icon(Icons.straighten_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? 'La unidad es requerida.'
                        : null,
                    onChanged: (value) {
                      unit = value;
                    },
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

                final purchaseCost = _parseNumber(purchaseCostText) ?? 0;
                final salePrice = _parseNumber(salePriceText);

                Navigator.of(dialogContext).pop(
                  _QuickProductDraft(
                    name: name.trim(),
                    barcode: barcode.trim().isEmpty ? null : barcode.trim(),
                    purchaseCost: purchaseCost,
                    salePrice: salePrice,
                    minimumStock: int.parse(minimumStockText.trim()),
                    unit: unit.trim(),
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
          purchasePrice: confirmedDraft.purchaseCost,
          salePrice: confirmedDraft.salePrice ?? 0,
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

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(
              result.outcome == BusinessProductCreationOutcome.existing
                  ? 'Producto existente agregado'
                  : 'Producto creado y agregado',
            ),
            content: Text(
              '${result.message}\n\n'
              'Nombre: $productName\n'
              'Código: ${result.barcode ?? 'sin código'}\n'
              'Costo: ${_money(_double(result.product?['purchase_price']))}\n'
              'Estado catálogo: ${result.masterProductId == null ? 'manual sin vincular' : 'vinculado a master'}\n'
              'Sync catálogo: ${result.created ? 'en cola local' : 'sin cambios'}\n\n'
              'Cuando registres la compra, el stock local subirá con la cantidad recibida.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
            ],
          );
        },
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
                      ? 'Se encontró metadata maestra para este código.'
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

  Future<void> _syncPendingPurchases() async {
    if (_isSyncingPurchases || _isSaving) {
      return;
    }

    setState(() {
      _isSyncingPurchases = true;
    });

    try {
      final repairService = ref.read(purchaseSyncRepairServiceProvider);
      final repairResult = await repairService.repairPartialOrFailedPurchases(
        businessId: widget.businessId,
        branchId: widget.branchId,
      );

      final productSyncService =
          ref.read(inventoryProductFromMasterSyncServiceProvider);
      final catalogUploadService = ref.read(catalogSyncUploadServiceProvider);
      final outboxService = ref.read(purchaseSyncOutboxServiceProvider);
      final uploadService = ref.read(purchasesSyncUploadServiceProvider);

      final catalogBackfillCount = await productSyncService
          .enqueueManualProductsUsedByUnsyncedPurchasesForCatalogSync(
        businessId: widget.businessId,
        branchId: widget.branchId,
        profileId: widget.profileId,
        appDeviceId: widget.appDeviceId,
        deviceInstallationId: widget.deviceInstallationId,
      );

      final catalogUploadResult =
          await catalogUploadService.uploadPendingCatalogBatches(
        businessId: widget.businessId,
        batchLimit: 250,
      );

      final enqueueResult = await outboxService.enqueuePendingPurchases(
        businessId: widget.businessId,
        branchId: widget.branchId,
        profileId: widget.profileId,
        appDeviceId: widget.appDeviceId,
        deviceInstallationId: widget.deviceInstallationId,
        limit: 250,
      );

      final uploadResult = await uploadService.uploadPendingPurchasesBatches(
        businessId: widget.businessId,
        branchId: widget.branchId,
        batchLimit: 250,
      );

      if (!mounted) {
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

      await showDialog<void>(
        context: context,
        builder: (context) {
          final hasIssues = catalogUploadResult.batchesPartial > 0 ||
              catalogUploadResult.batchesFailed > 0 ||
              uploadResult.batchesPartial > 0 ||
              uploadResult.batchesFailed > 0 ||
              uploadResult.batchesWaitingForDependencies > 0 ||
              uploadResult.batchesBlockedByDependencies > 0;

          return AlertDialog(
            title: Text(
              hasIssues
                  ? 'Sync de compras con observaciones'
                  : 'Sync de compras completado',
            ),
            content: Text(
              'Reparación local\n'
              'Compras reparadas: ${repairResult.purchaseCount}\n'
              'Batches reemplazados: ${repairResult.supersededBatches}\n\n'
              'Catálogo\n'
              'Productos manuales encolados: $catalogBackfillCount\n'
              'Batches revisados: ${catalogUploadResult.batchesChecked}\n'
              'Batches subidos: ${catalogUploadResult.batchesUploaded}\n'
              'Completados: ${catalogUploadResult.batchesCompleted}\n'
              'Parciales: ${catalogUploadResult.batchesPartial}\n'
              'Fallidos: ${catalogUploadResult.batchesFailed}\n'
              'Mutaciones subidas: ${catalogUploadResult.mutationsUploaded}\n\n'
              'Preparación local\n'
              'Compras revisadas: ${enqueueResult.purchasesChecked}\n'
              'Compras preparadas: ${enqueueResult.purchasesEnqueued}\n'
              'Batches creados: ${enqueueResult.batchesCreated}\n'
              'Mutaciones preparadas: ${enqueueResult.mutationsEnqueued}\n\n'
              'Subida remota\n'
              'Batches revisados: ${uploadResult.batchesChecked}\n'
              'Batches subidos: ${uploadResult.batchesUploaded}\n'
              'Completados: ${uploadResult.batchesCompleted}\n'
              'Parciales: ${uploadResult.batchesPartial}\n'
              'Fallidos: ${uploadResult.batchesFailed}\n'
              'Esperando Products: ${uploadResult.batchesWaitingForDependencies}\n'
              'Bloqueados por Product: ${uploadResult.batchesBlockedByDependencies}\n'
              'Mutaciones subidas: ${uploadResult.mutationsUploaded}',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      _showMessage('No se pudo sincronizar compras: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isSyncingPurchases = false;
        });
      }
    }
  }

  Future<void> _savePurchase() async {
    if (_isSaving) {
      return;
    }

    if (_cartItems.isEmpty) {
      _showMessage('Agrega al menos un producto a la compra.');
      return;
    }

    final invalidCost = _cartItems.any((item) => item.unitCost <= 0);

    if (invalidCost) {
      _showMessage(
          'Todos los productos deben tener costo unitario mayor a cero.');
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
                  quantity: item.quantity,
                  unitCost: item.unitCost,
                ),
              )
              .toList(),
          metadata: const {
            'ui': 'purchase_entry_screen',
            'source': 'purchase_ui',
          },
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _cartItems.clear();
        _supplierNameController.clear();
        _searchController.clear();
        _query = '';
      });

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Compra registrada'),
            content: Text(
              'Se registró la compra localmente.\n\n'
              'Productos: ${result.itemCount}\n'
              'Total: ${_money(result.total)}\n\n'
              'El stock local ya fue actualizado. La compra queda pendiente de sincronización.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entendido'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      _showMessage('No se pudo registrar la compra: $error');
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
              onPressed: _isSaving || _isSyncingPurchases
                  ? null
                  : _syncPendingPurchases,
              icon: _isSyncingPurchases
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_sync_outlined),
              tooltip: 'Sincronizar compras',
            ),
            IconButton(
              onPressed: _isSaving || _isSyncingPurchases
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 6,
                      child: _ProductsPanel(
                        searchController: _searchController,
                        query: _query,
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
                        supplierNameController: _supplierNameController,
                        items: _cartItems,
                        total: _total,
                        itemCount: _itemCount,
                        isSaving: _isSaving,
                        onIncrement: _incrementItem,
                        onDecrement: _decrementItem,
                        onRemove: _removeItem,
                        onEditQuantity: _editQuantity,
                        onEditUnitCost: _editUnitCost,
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
                    isSaving: _isSaving,
                    onIncrement: _incrementItem,
                    onDecrement: _decrementItem,
                    onRemove: _removeItem,
                    onEditQuantity: _editQuantity,
                    onEditUnitCost: _editUnitCost,
                    onSave: _savePurchase,
                  ),
                  const SizedBox(height: CronosSpacing.md),
                  _ProductsPanel(
                    searchController: _searchController,
                    query: _query,
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
    required this.searchController,
    required this.query,
    required this.productsAsync,
    required this.filterProducts,
    required this.onQueryChanged,
    required this.onProductTap,
    required this.onCreateQuickProduct,
  });

  final TextEditingController searchController;
  final String query;
  final AsyncValue<List<Map<String, dynamic>>> productsAsync;
  final List<Map<String, dynamic>> Function(List<Map<String, dynamic>>)
      filterProducts;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<Map<String, dynamic>> onProductTap;
  final VoidCallback onCreateQuickProduct;

  @override
  Widget build(BuildContext context) {
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
            productsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(CronosSpacing.lg),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (error, _) => AppEmptyState(
                icon: Icons.error_outline,
                title: 'No se pudieron cargar productos',
                message: error.toString(),
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

                final listHeight = (MediaQuery.sizeOf(context).height * 0.52)
                    .clamp(280.0, 620.0)
                    .toDouble();

                return SizedBox(
                  height: listHeight,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: CronosSpacing.sm),
                    itemBuilder: (context, index) {
                      final product = filtered[index];

                      return _ProductPurchaseTile(
                        product: product,
                        onTap: () => onProductTap(product),
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductPurchaseTile extends StatelessWidget {
  const _ProductPurchaseTile({
    required this.product,
    required this.onTap,
  });

  final Map<String, dynamic> product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = _PurchaseEntryScreenState._string(product['product_name']) ??
        'Producto sin nombre';
    final barcode = _PurchaseEntryScreenState._string(product['barcode']);
    final stock = _PurchaseEntryScreenState._int(product['quantity_available']);
    final purchasePrice =
        _PurchaseEntryScreenState._double(product['purchase_price']);
    final averageCost =
        _PurchaseEntryScreenState._double(product['stock_average_cost']);
    final suggestedCost = purchasePrice > 0 ? purchasePrice : averageCost;

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
                  const Icon(Icons.inventory_2_outlined),
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
                    label: 'Stock $stock',
                  ),
                  _PurchaseMetricPill(
                    icon: Icons.sell_outlined,
                    label:
                        'Costo ${_PurchaseEntryScreenState._money(suggestedCost)}',
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
    required this.supplierNameController,
    required this.items,
    required this.total,
    required this.itemCount,
    required this.isSaving,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onEditQuantity,
    required this.onEditUnitCost,
    required this.onSave,
  });

  final TextEditingController supplierNameController;
  final List<_PurchaseCartItem> items;
  final double total;
  final int itemCount;
  final bool isSaving;
  final ValueChanged<_PurchaseCartItem> onIncrement;
  final ValueChanged<_PurchaseCartItem> onDecrement;
  final ValueChanged<_PurchaseCartItem> onRemove;
  final ValueChanged<_PurchaseCartItem> onEditQuantity;
  final ValueChanged<_PurchaseCartItem> onEditUnitCost;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(CronosSpacing.md),
      child: AppGlassCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compra actual',
              style: Theme.of(context).textTheme.titleLarge,
            ),
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
                message:
                    'Agrega productos desde el listado para reponer stock.',
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: CronosSpacing.sm),
                itemBuilder: (context, index) {
                  final item = items[index];

                  return _PurchaseCartTile(
                    item: item,
                    onIncrement: () => onIncrement(item),
                    onDecrement: () => onDecrement(item),
                    onRemove: () => onRemove(item),
                    onEditQuantity: () => onEditQuantity(item),
                    onEditUnitCost: () => onEditUnitCost(item),
                  );
                },
              ),
            const SizedBox(height: CronosSpacing.md),
            Wrap(
              spacing: CronosSpacing.sm,
              runSpacing: CronosSpacing.sm,
              children: [
                _PurchaseMetricPill(
                  icon: Icons.format_list_numbered_outlined,
                  label: '$itemCount uds.',
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
                label: Text(
                  isSaving ? 'Guardando compra...' : 'Registrar compra',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PurchaseCartTile extends StatelessWidget {
  const _PurchaseCartTile({
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
    required this.onRemove,
    required this.onEditQuantity,
    required this.onEditUnitCost,
  });

  final _PurchaseCartItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onRemove;
  final VoidCallback onEditQuantity;
  final VoidCallback onEditUnitCost;

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
                label: 'Stock ${item.currentStock}',
              ),
              _PurchaseMetricPill(
                icon: Icons.sell_outlined,
                label:
                    'Costo ${_PurchaseEntryScreenState._money(item.unitCost)}',
              ),
              _PurchaseMetricPill(
                icon: Icons.receipt_long_outlined,
                label:
                    'Subt. ${_PurchaseEntryScreenState._money(item.subtotal)}',
              ),
            ],
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
              TextButton.icon(
                onPressed: onEditUnitCost,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Costo'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickProductDraft {
  const _QuickProductDraft({
    required this.name,
    required this.purchaseCost,
    required this.minimumStock,
    required this.unit,
    this.barcode,
    this.salePrice,
  });

  final String name;
  final String? barcode;
  final double purchaseCost;
  final double? salePrice;
  final int minimumStock;
  final String unit;

  _QuickProductDraft copyWith({String? name}) {
    return _QuickProductDraft(
      name: name ?? this.name,
      purchaseCost: purchaseCost,
      minimumStock: minimumStock,
      unit: unit,
      barcode: barcode,
      salePrice: salePrice,
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
  });

  final String productId;
  final String productName;
  final String? barcode;
  final int currentStock;
  final int quantity;
  final double unitCost;

  double get subtotal => quantity * unitCost;

  _PurchaseCartItem copyWith({
    int? currentStock,
    int? quantity,
    double? unitCost,
  }) {
    return _PurchaseCartItem(
      productId: productId,
      productName: productName,
      barcode: barcode,
      currentStock: currentStock ?? this.currentStock,
      quantity: quantity ?? this.quantity,
      unitCost: unitCost ?? this.unitCost,
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
