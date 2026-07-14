import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/shared_widgets.dart';
import '../../../inventory/application/product_stock_balance_providers.dart';
import '../../application/pos_local_sale_models.dart';
import '../../application/pos_local_sale_provider.dart';

class PosSaleScreen extends ConsumerStatefulWidget {
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
  ConsumerState<PosSaleScreen> createState() => _PosSaleScreenState();
}

class _PosSaleScreenState extends ConsumerState<PosSaleScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  final List<_PosCartItem> _cartItems = [];
  final List<_PosPaymentDraft> _paymentDrafts = [
    const _PosPaymentDraft(id: 'payment-1', method: 'cash', amount: 0),
  ];

  final Map<String, TextEditingController> _paymentAmountControllers = {};

  List<_PosCartItem>? _parkedCartItems;
  List<_PosPaymentDraft>? _parkedPaymentDrafts;
  int? _parkedPaymentSequence;

  int _paymentSequence = 1;
  bool _isCharging = false;
  bool _isEnqueueing = false;
  bool _isQuickSaleMode = false;

  bool get _hasParkedSale {
    return _parkedCartItems != null && _parkedCartItems!.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 350), () {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();

    for (final controller in _paymentAmountControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  double get _subtotal {
    return _cartItems.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );
  }

  double get _paidTotal {
    return _paymentDrafts.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );
  }

  TextEditingController _paymentControllerFor(_PosPaymentDraft payment) {
    return _paymentAmountControllers.putIfAbsent(
      payment.id,
      () => TextEditingController(
        text: payment.amount > 0 ? payment.amount.toStringAsFixed(2) : '',
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _addProductToCart(Map<String, dynamic> product) {
    final productId = _string(product['product_id']);

    if (productId == null) {
      _showMessage('Producto inválido.');
      return;
    }

    final available = _int(product['quantity_available']);
    final unitPrice = _num(product['sale_price']);

    if (available <= 0) {
      _showMessage('Producto sin stock disponible.');
      return;
    }

    if (unitPrice <= 0) {
      _showMessage('Producto sin precio de venta válido.');
      return;
    }

    final existingIndex = _cartItems.indexWhere(
      (item) => item.productId == productId,
    );

    if (existingIndex >= 0) {
      final existing = _cartItems[existingIndex];

      if (existing.quantity >= existing.quantityAvailable) {
        _showMessage('No hay más stock disponible para este producto.');
        return;
      }

      setState(() {
        _cartItems[existingIndex] = existing.copyWith(
          quantity: existing.quantity + 1,
        );
        _searchController.clear();
      });
    } else {
      setState(() {
        _cartItems.add(
          _PosCartItem(
            productId: productId,
            name: _string(product['product_name']) ?? 'Producto sin nombre',
            barcode: _string(product['barcode']),
            unitPrice: unitPrice,
            quantityAvailable: available,
            quantity: 1,
          ),
        );
        _searchController.clear();
      });
    }

    _searchFocusNode.requestFocus();
  }

  void _increaseCartItem(String productId) {
    final index = _cartItems.indexWhere((item) => item.productId == productId);

    if (index < 0) {
      return;
    }

    final item = _cartItems[index];

    if (item.quantity >= item.quantityAvailable) {
      _showMessage('No hay más stock disponible.');
      return;
    }

    setState(() {
      _cartItems[index] = item.copyWith(quantity: item.quantity + 1);
    });
  }

  void _decreaseCartItem(String productId) {
    final index = _cartItems.indexWhere((item) => item.productId == productId);

    if (index < 0) {
      return;
    }

    final item = _cartItems[index];

    setState(() {
      if (item.quantity <= 1) {
        _cartItems.removeAt(index);
      } else {
        _cartItems[index] = item.copyWith(quantity: item.quantity - 1);
      }
    });
  }

  Future<void> _editCartItemQuantity(String productId) async {
    final index = _cartItems.indexWhere((item) => item.productId == productId);

    if (index < 0) {
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();

    final item = _cartItems[index];

    final quantity = await showDialog<int>(
      context: context,
      builder: (context) {
        return _QuantityEditDialog(
          initialQuantity: item.quantity,
          maxQuantity: item.quantityAvailable,
        );
      },
    );

    if (!mounted || quantity == null) {
      return;
    }

    final freshIndex = _cartItems.indexWhere(
      (cartItem) => cartItem.productId == productId,
    );

    if (freshIndex < 0) {
      return;
    }

    final freshItem = _cartItems[freshIndex];

    if (quantity <= 0) {
      setState(() {
        _cartItems.removeAt(freshIndex);
      });
      return;
    }

    if (quantity > freshItem.quantityAvailable) {
      _showMessage(
        'La cantidad supera el stock disponible (${freshItem.quantityAvailable}).',
      );
      return;
    }

    setState(() {
      _cartItems[freshIndex] = freshItem.copyWith(quantity: quantity);
    });
  }

  void _removeCartItem(String productId) {
    setState(() {
      _cartItems.removeWhere((item) => item.productId == productId);
    });
  }

  void _addPaymentLine() {
    setState(() {
      _paymentSequence++;
      _paymentDrafts.add(
        _PosPaymentDraft(
          id: 'payment-$_paymentSequence',
          method:
              _paymentDrafts.any((payment) => payment.method == 'bank_transfer')
                  ? 'cash'
                  : 'bank_transfer',
          amount: 0,
        ),
      );
    });
  }

  void _removePaymentLine(String paymentId) {
    if (_paymentDrafts.length <= 1) {
      _showMessage('Debe existir al menos un método de pago.');
      return;
    }

    setState(() {
      _paymentDrafts.removeWhere((payment) => payment.id == paymentId);
      _paymentAmountControllers.remove(paymentId)?.dispose();
    });
  }

  void _updatePaymentMethod(String paymentId, String? method) {
    if (method == null || method.trim().isEmpty) {
      return;
    }

    final index =
        _paymentDrafts.indexWhere((payment) => payment.id == paymentId);

    if (index < 0) {
      return;
    }

    setState(() {
      _paymentDrafts[index] = _paymentDrafts[index].copyWith(method: method);
    });
  }

  void _updatePaymentAmount(String paymentId, String rawValue) {
    final index =
        _paymentDrafts.indexWhere((payment) => payment.id == paymentId);

    if (index < 0) {
      return;
    }

    final amount = _parseMoney(rawValue);

    setState(() {
      _paymentDrafts[index] = _paymentDrafts[index].copyWith(amount: amount);
    });
  }

  void _fillCashPaymentWithTotal() {
    if (_cartItems.isEmpty) {
      _showMessage('Agrega productos antes de autocompletar el pago.');
      return;
    }

    final total = _subtotal;
    final cashIndex = _paymentDrafts.indexWhere(
      (payment) => payment.method == 'cash',
    );

    setState(() {
      if (cashIndex >= 0) {
        final payment = _paymentDrafts[cashIndex];
        _paymentDrafts[cashIndex] = payment.copyWith(amount: total);
        _paymentControllerFor(payment).text = total.toStringAsFixed(2);
      } else {
        _paymentSequence++;
        final payment = _PosPaymentDraft(
          id: 'payment-$_paymentSequence',
          method: 'cash',
          amount: total,
        );
        _paymentDrafts.add(payment);
        _paymentControllerFor(payment).text = total.toStringAsFixed(2);
      }
    });
  }

  void _handleSubmittedSearch(
    String rawValue,
    List<Map<String, dynamic>> products,
  ) {
    final value = rawValue.trim();

    if (value.isEmpty) {
      return;
    }

    final exactBarcodeMatches = products.where((product) {
      return (_string(product['barcode']) ?? '') == value;
    }).toList();

    if (exactBarcodeMatches.length == 1) {
      _addProductToCart(exactBarcodeMatches.first);
      return;
    }

    if (exactBarcodeMatches.length > 1) {
      _showMessage('Hay más de un producto con ese código.');
      return;
    }

    final filtered = _filterProducts(products, value);

    if (filtered.length == 1) {
      _addProductToCart(filtered.first);
      return;
    }

    if (filtered.isEmpty) {
      _showMessage('Producto no encontrado: $value');
      return;
    }

    _showMessage('Selecciona el producto en la lista.');
  }

  void _showScannerInfo() {
    _searchFocusNode.requestFocus();

    _showMessage(
      'Escanea con el lector Bluetooth sobre el campo de búsqueda. '
      'Si el lector envía Enter, se agregará automáticamente.',
    );
  }

  void _showQrPending() {
    _showMessage(
      'QR por cámara se conecta en una fase posterior. '
      'Para lector Bluetooth usa el campo de búsqueda.',
    );
  }

  void _disposePaymentControllers() {
    for (final controller in _paymentAmountControllers.values) {
      controller.dispose();
    }

    _paymentAmountControllers.clear();
  }

  void _resetPaymentDraftsToCash() {
    _disposePaymentControllers();

    _paymentDrafts
      ..clear()
      ..add(
        const _PosPaymentDraft(
          id: 'payment-1',
          method: 'cash',
          amount: 0,
        ),
      );

    _paymentSequence = 1;
  }

  Future<void> _startQuickSale() async {
    if (_isQuickSaleMode) {
      _showMessage('La venta rápida ya está activa.');
      return;
    }

    if (_cartItems.isEmpty) {
      _showMessage(
        'El carrito está vacío. Puedes usarlo directamente para una venta rápida.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Iniciar venta rápida'),
          content: const Text(
            'Guardaremos temporalmente el carrito actual y abriremos '
            'un carrito vacío para atender una venta corta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Iniciar'),
            ),
          ],
        );
      },
    );

    if (!mounted || confirmed != true) {
      return;
    }

    setState(() {
      _parkedCartItems = List<_PosCartItem>.from(_cartItems);
      _parkedPaymentDrafts = List<_PosPaymentDraft>.from(_paymentDrafts);
      _parkedPaymentSequence = _paymentSequence;

      _cartItems.clear();
      _resetPaymentDraftsToCash();
      _searchController.clear();
      _isQuickSaleMode = true;
    });

    _searchFocusNode.requestFocus();

    _showMessage('Venta rápida activa. El carrito anterior quedó en espera.');
  }

  Future<void> _restoreParkedSale() async {
    if (!_isQuickSaleMode || !_hasParkedSale) {
      _showMessage('No hay un carrito anterior para restaurar.');
      return;
    }

    if (_cartItems.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Volver al carrito anterior'),
            content: const Text(
              'La venta rápida actual todavía tiene productos. '
              'Si vuelves ahora, se descartará este carrito rápido.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Descartar y volver'),
              ),
            ],
          );
        },
      );

      if (!mounted || confirmed != true) {
        return;
      }
    }

    final restoreMessage = await _restoreParkedSaleDraft();

    _showMessage(restoreMessage ?? 'Carrito anterior restaurado.');
  }

  Future<_CartStockRefreshResult> _refreshParkedCartAgainstCurrentStock(
    List<_PosCartItem> parkedCart,
  ) async {
    final adjustedItems = <_PosCartItem>[];
    var reducedCount = 0;
    var removedCount = 0;

    for (final item in parkedCart) {
      var available = item.quantityAvailable;

      try {
        final stockDao = ref.read(productStockBalanceLocalDaoProvider);

        final stockBalance = await stockDao
            .getProductBalance(
              businessId: widget.businessId,
              branchId: widget.branchId,
              productId: item.productId,
            )
            .timeout(
              const Duration(seconds: 2),
              onTimeout: () => null,
            );

        if (stockBalance != null) {
          available = _int(stockBalance['quantity_available']);
        }
      } catch (_) {
        // Si por alguna razón no logramos refrescar el stock, usamos el snapshot
        // del carrito. El servicio de venta sigue siendo la última defensa.
      }

      if (available <= 0) {
        removedCount++;
        continue;
      }

      final adjustedQuantity = math.min(item.quantity, available);

      if (adjustedQuantity < item.quantity ||
          available != item.quantityAvailable) {
        reducedCount++;
      }

      adjustedItems.add(
        item.copyWith(
          quantity: adjustedQuantity,
          quantityAvailable: available,
        ),
      );
    }

    String? message;

    if (removedCount > 0 && reducedCount > 0) {
      message =
          'Carrito restaurado con ajustes: $removedCount producto(s) removido(s) y $reducedCount cantidad(es) reducida(s) por stock disponible.';
    } else if (removedCount > 0) {
      message =
          'Carrito restaurado: $removedCount producto(s) fueron removidos por falta de stock.';
    } else if (reducedCount > 0) {
      message =
          'Carrito restaurado: $reducedCount producto(s) fueron ajustados al stock disponible.';
    }

    return _CartStockRefreshResult(
      items: adjustedItems,
      message: message,
      wasAdjusted: removedCount > 0 || reducedCount > 0,
    );
  }

  Future<String?> _restoreParkedSaleDraft() async {
    final parkedCart = _parkedCartItems;
    final parkedPayments = _parkedPaymentDrafts;

    if (parkedCart == null || parkedPayments == null) {
      return null;
    }

    final stockRefresh = await _refreshParkedCartAgainstCurrentStock(
      parkedCart,
    );

    if (!mounted) {
      return stockRefresh.message;
    }

    setState(() {
      _disposePaymentControllers();

      _cartItems
        ..clear()
        ..addAll(stockRefresh.items);

      _paymentDrafts.clear();

      if (stockRefresh.wasAdjusted) {
        _paymentDrafts.add(
          const _PosPaymentDraft(
            id: 'payment-1',
            method: 'cash',
            amount: 0,
          ),
        );
        _paymentSequence = 1;
      } else {
        _paymentDrafts.addAll(parkedPayments);
        _paymentSequence = _parkedPaymentSequence ?? parkedPayments.length;
      }

      _parkedCartItems = null;
      _parkedPaymentDrafts = null;
      _parkedPaymentSequence = null;
      _isQuickSaleMode = false;
      _searchController.clear();
    });

    _searchFocusNode.requestFocus();

    return stockRefresh.message;
  }

  Future<dynamic> _enqueuePendingPosSales({
    int limit = 25,
  }) async {
    if (_isEnqueueing) {
      return null;
    }

    setState(() {
      _isEnqueueing = true;
    });

    try {
      return await ref
          .read(posSyncOutboxServiceProvider)
          .enqueuePendingPosSales(
            businessId: widget.businessId,
            branchId: widget.branchId,
            profileId: widget.profileId,
            appDeviceId: widget.appDeviceId,
            deviceInstallationId: widget.deviceInstallationId,
            limit: limit,
          );
    } finally {
      if (mounted) {
        setState(() {
          _isEnqueueing = false;
        });
      }
    }
  }

  Future<void> _preparePendingPosSync() async {
    try {
      final result = await _enqueuePendingPosSales(limit: 50);

      if (!mounted || result == null) {
        return;
      }

      _showMessage(
        result.salesEnqueued == 0
            ? 'No hay ventas POS pendientes por preparar.'
            : 'POS preparado: ${result.salesEnqueued} venta(s), '
                '${result.mutationsEnqueued} mutación(es). '
                'Se subirán en el horario programado.',
      );
    } catch (error) {
      _showMessage('No se pudo preparar POS para sync: $error');
    }
  }

  List<PosLocalPaymentInput> _buildPaymentInputsForSale(double total) {
    final nonZeroPayments = _paymentDrafts
        .where((payment) => payment.amount > 0.01)
        .map(
          (payment) => _PosPaymentDraft(
            id: payment.id,
            method: payment.method,
            amount: payment.amount,
          ),
        )
        .toList();

    if (nonZeroPayments.isEmpty) {
      throw StateError('Registra al menos un pago.');
    }

    final paidTotal = nonZeroPayments.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );

    if (paidTotal + 0.01 < total) {
      throw StateError('El pago está incompleto.');
    }

    var overpaid = paidTotal - total;

    if (overpaid > 0.01) {
      final hasCash =
          nonZeroPayments.any((payment) => payment.method == 'cash');

      if (!hasCash) {
        throw StateError(
          'El cambio solo se permite cuando existe un pago en efectivo.',
        );
      }

      for (var index = nonZeroPayments.length - 1; index >= 0; index--) {
        if (overpaid <= 0.01) {
          break;
        }

        final payment = nonZeroPayments[index];

        if (payment.method != 'cash') {
          continue;
        }

        final discount = math.min(payment.amount, overpaid);

        nonZeroPayments[index] = payment.copyWith(
          amount: payment.amount - discount,
        );

        overpaid -= discount;
      }

      if (overpaid > 0.01) {
        throw StateError(
          'El efectivo recibido no alcanza para cubrir el cambio.',
        );
      }
    }

    final appliedPayments =
        nonZeroPayments.where((payment) => payment.amount > 0.01).toList();

    if (appliedPayments.isEmpty) {
      throw StateError('No hay pagos aplicables para la venta.');
    }

    final appliedTotal = appliedPayments.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );

    final roundingDifference = total - appliedTotal;

    if (roundingDifference.abs() > 0.01) {
      throw StateError(
        'Los pagos no coinciden con el total. '
        'total=$total aplicado=$appliedTotal',
      );
    }

    if (roundingDifference.abs() > 0) {
      final first = appliedPayments.first;

      appliedPayments[0] = first.copyWith(
        amount: first.amount + roundingDifference,
      );
    }

    return appliedPayments
        .map(
          (payment) => PosLocalPaymentInput(
            method: payment.method,
            amount: payment.amount,
          ),
        )
        .toList();
  }

  Future<void> _chargeSale() async {
    if (_isCharging) {
      return;
    }

    final total = _subtotal;
    final paid = _paidTotal;
    final change = math.max(0.0, paid - total);

    if (_cartItems.isEmpty) {
      _showMessage('Agrega productos antes de cobrar.');
      return;
    }

    if (widget.cashRegisterId == null ||
        widget.cashRegisterId!.trim().isEmpty) {
      _showMessage('No hay caja abierta para registrar la venta.');
      return;
    }

    if (widget.cashSessionId == null || widget.cashSessionId!.trim().isEmpty) {
      _showMessage('No hay sesión de caja abierta para registrar la venta.');
      return;
    }

    if (paid + 0.01 < total) {
      _showMessage('El pago está incompleto.');
      return;
    }

    setState(() {
      _isCharging = true;
    });

    try {
      final payments = _buildPaymentInputsForSale(total);

      final result =
          await ref.read(posLocalSaleServiceProvider).createLocalSale(
                CreatePosLocalSaleInput(
                  businessId: widget.businessId,
                  branchId: widget.branchId,
                  profileId: widget.profileId,
                  appDeviceId: widget.appDeviceId,
                  deviceInstallationId: widget.deviceInstallationId,
                  cashRegisterId: widget.cashRegisterId,
                  cashSessionId: widget.cashSessionId,
                  items: _cartItems
                      .map(
                        (item) => PosLocalSaleItemInput(
                          productId: item.productId,
                          quantity: item.quantity,
                          unitPrice: item.unitPrice,
                        ),
                      )
                      .toList(),
                  payments: payments,
                  metadata: {
                    'source': 'pos_sale_screen',
                    'ui': 'professional_pos',
                    'received_total': paid,
                    'change_amount': change,
                    'cart_item_count': _cartItems.length,
                  },
                ),
              );

      dynamic enqueueResult;

      try {
        enqueueResult = await _enqueuePendingPosSales(limit: 25);
      } catch (error) {
        if (mounted) {
          _showMessage(
            'Venta local creada, pero no se pudo preparar sync POS: $error',
          );
        }
      }

      if (!mounted) {
        return;
      }

      final restoredPreviousCart = _isQuickSaleMode && _parkedCartItems != null;

      String? quickSaleRestoreMessage;

      if (restoredPreviousCart) {
        quickSaleRestoreMessage = await _restoreParkedSaleDraft().timeout(
          const Duration(seconds: 4),
          onTimeout: () {
            return 'Venta registrada. El carrito anterior no se pudo refrescar automáticamente; vuelve a POS para continuar.';
          },
        );
      } else {
        _resetSaleDraft();
      }

      final enqueuedSales = enqueueResult?.salesEnqueued ?? 0;
      final enqueuedMutations = enqueueResult?.mutationsEnqueued ?? 0;

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Venta registrada'),
            content: Text(
              'La venta se guardó localmente y el stock local fue actualizado.\n\n'
              'Total: ${_money(result.total)}\n'
              'Cambio: ${_money(change)}\n\n'
              'Preparación sync POS: $enqueuedSales venta(s), '
              '$enqueuedMutations mutación(es).\n\n'
              'La subida a Supabase no se hace inmediatamente. '
              'Se ejecutará a las 11:00, a las 23:00 o al cierre de caja.'
              '${quickSaleRestoreMessage != null ? '\n\n$quickSaleRestoreMessage' : ''}',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Aceptar'),
              ),
            ],
          );
        },
      );

      _searchFocusNode.requestFocus();
    } catch (error) {
      _showMessage(error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _isCharging = false;
        });
      }
    }
  }

  void _resetSaleDraft() {
    for (final controller in _paymentAmountControllers.values) {
      controller.dispose();
    }

    _paymentAmountControllers.clear();

    setState(() {
      _cartItems.clear();
      _paymentDrafts
        ..clear()
        ..add(
          const _PosPaymentDraft(
            id: 'payment-1',
            method: 'cash',
            amount: 0,
          ),
        );
      _paymentSequence = 1;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(
      localProductsWithStockProvider(
        ProductsWithLocalStockKey(
          businessId: widget.businessId,
          branchId: widget.branchId,
          limit: 300,
        ),
      ),
    );

    return Theme(
      data: CronosTheme.light(),
      child: Builder(
        builder: (context) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Nueva venta'),
              actions: [
                IconButton(
                  onPressed: _showQrPending,
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                  tooltip: 'Escanear QR con cámara',
                ),
                IconButton(
                  onPressed: _showScannerInfo,
                  icon: const Icon(Icons.qr_code_2_outlined),
                  tooltip: 'Lector Bluetooth',
                ),
              ],
            ),
            body: AppGradientBackground(
              child: productsAsync.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, _) => _PosErrorState(
                  message: error.toString(),
                ),
                data: (products) {
                  return LayoutBuilder(
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
                                  products: products,
                                  searchController: _searchController,
                                  searchFocusNode: _searchFocusNode,
                                  onSearchChanged: (_) {
                                    setState(() {});
                                  },
                                  onSearchSubmitted: (value) {
                                    _handleSubmittedSearch(value, products);
                                  },
                                  onProductTap: _addProductToCart,
                                  onScannerInfo: _showScannerInfo,
                                ),
                              ),
                              const SizedBox(width: CronosSpacing.md),
                              SizedBox(
                                width: 430,
                                child: _CartSection(
                                  cartItems: _cartItems,
                                  paymentDrafts: _paymentDrafts,
                                  isCharging: _isCharging,
                                  isEnqueueing: _isEnqueueing,
                                  isQuickSaleMode: _isQuickSaleMode,
                                  hasParkedSale: _hasParkedSale,
                                  paymentControllerFor: _paymentControllerFor,
                                  onPaymentMethodChanged: _updatePaymentMethod,
                                  onPaymentAmountChanged: _updatePaymentAmount,
                                  onAddPaymentLine: _addPaymentLine,
                                  onRemovePaymentLine: _removePaymentLine,
                                  onFillCashPaymentWithTotal:
                                      _fillCashPaymentWithTotal,
                                  onIncrease: _increaseCartItem,
                                  onDecrease: _decreaseCartItem,
                                  onEditQuantity: _editCartItemQuantity,
                                  onRemove: _removeCartItem,
                                  onChargePressed: _chargeSale,
                                  onPrepareSyncPressed: _preparePendingPosSync,
                                  onStartQuickSale: _startQuickSale,
                                  onRestoreParkedSale: _restoreParkedSale,
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
                            products: products,
                            searchController: _searchController,
                            searchFocusNode: _searchFocusNode,
                            onSearchChanged: (_) {
                              setState(() {});
                            },
                            onSearchSubmitted: (value) {
                              _handleSubmittedSearch(value, products);
                            },
                            onProductTap: _addProductToCart,
                            onScannerInfo: _showScannerInfo,
                          ),
                          const SizedBox(height: CronosSpacing.md),
                          _CartSection(
                            cartItems: _cartItems,
                            paymentDrafts: _paymentDrafts,
                            isCharging: _isCharging,
                            isEnqueueing: _isEnqueueing,
                            isQuickSaleMode: _isQuickSaleMode,
                            hasParkedSale: _hasParkedSale,
                            paymentControllerFor: _paymentControllerFor,
                            onPaymentMethodChanged: _updatePaymentMethod,
                            onPaymentAmountChanged: _updatePaymentAmount,
                            onAddPaymentLine: _addPaymentLine,
                            onRemovePaymentLine: _removePaymentLine,
                            onFillCashPaymentWithTotal:
                                _fillCashPaymentWithTotal,
                            onIncrease: _increaseCartItem,
                            onDecrease: _decreaseCartItem,
                            onEditQuantity: _editCartItemQuantity,
                            onRemove: _removeCartItem,
                            onChargePressed: _chargeSale,
                            onPrepareSyncPressed: _preparePendingPosSync,
                            onStartQuickSale: _startQuickSale,
                            onRestoreParkedSale: _restoreParkedSale,
                            cashRegisterName: widget.cashRegisterName,
                            cashSessionId: widget.cashSessionId,
                          ),
                        ],
                      );
                    },
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
    required this.products,
    required this.searchController,
    required this.searchFocusNode,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onProductTap,
    required this.onScannerInfo,
  });

  final List<Map<String, dynamic>> products;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onSearchSubmitted;
  final ValueChanged<Map<String, dynamic>> onProductTap;
  final VoidCallback onScannerInfo;

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim();
    final filteredProducts = _filterProducts(products, query).take(40).toList();

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
                focusNode: searchFocusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: onSearchChanged,
                onSubmitted: onSearchSubmitted,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: IconButton(
                    onPressed: onScannerInfo,
                    icon: const Icon(Icons.qr_code_2_outlined),
                    tooltip: 'Usar lector Bluetooth',
                  ),
                  labelText: 'Nombre o código de barras',
                  helperText:
                      'Para lector Bluetooth: escanea aquí. Enter agrega si hay coincidencia exacta.',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: CronosSpacing.md),
        AppGlassCard(
          child: query.isEmpty
              ? _InitialProductsState(
                  products: products.take(12).toList(),
                  onProductTap: onProductTap,
                )
              : _SearchResultsState(
                  query: query,
                  products: filteredProducts,
                  onProductTap: onProductTap,
                ),
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
                    'Busca por nombre, código de barras o lector Bluetooth.',
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

class _InitialProductsState extends StatelessWidget {
  const _InitialProductsState({
    required this.products,
    required this.onProductTap,
  });

  final List<Map<String, dynamic>> products;
  final ValueChanged<Map<String, dynamic>> onProductTap;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return const _EmptyProductsState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Productos recientes/locales',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: CronosSpacing.sm),
        ...products.map(
          (product) => _ProductResultTile(
            product: product,
            onTap: () => onProductTap(product),
          ),
        ),
      ],
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
          'No hay productos locales',
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: CronosSpacing.xs),
        Text(
          'Ejecuta pull de catálogo/stock antes de vender desde POS.',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: CronosSpacing.md),
      ],
    );
  }
}

class _SearchResultsState extends StatelessWidget {
  const _SearchResultsState({
    required this.query,
    required this.products,
    required this.onProductTap,
  });

  final String query;
  final List<Map<String, dynamic>> products;
  final ValueChanged<Map<String, dynamic>> onProductTap;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return Row(
        children: [
          const Icon(
            Icons.search_off_outlined,
            color: CronosColors.warning,
          ),
          const SizedBox(width: CronosSpacing.sm),
          Expanded(
            child: Text(
              'No encontramos productos para “$query”.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${products.length} resultado(s)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: CronosSpacing.sm),
        ...products.map(
          (product) => _ProductResultTile(
            product: product,
            onTap: () => onProductTap(product),
          ),
        ),
      ],
    );
  }
}

class _ProductResultTile extends StatelessWidget {
  const _ProductResultTile({
    required this.product,
    required this.onTap,
  });

  final Map<String, dynamic> product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = _string(product['product_name']) ?? 'Producto sin nombre';
    final barcode = _string(product['barcode']);
    final price = _num(product['sale_price']);
    final available = _int(product['quantity_available']);
    final canSell = available > 0 && price > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: CronosSpacing.sm),
      child: Material(
        color: CronosColors.surfaceMuted,
        borderRadius: BorderRadius.circular(CronosRadius.md),
        child: InkWell(
          onTap: canSell ? onTap : null,
          borderRadius: BorderRadius.circular(CronosRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(CronosSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: canSell
                        ? CronosColors.primarySoft
                        : CronosColors.surface,
                    borderRadius: BorderRadius.circular(CronosRadius.md),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    color:
                        canSell ? CronosColors.primary : CronosColors.textMuted,
                  ),
                ),
                const SizedBox(width: CronosSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        barcode == null || barcode.isEmpty
                            ? 'Sin código · Stock: $available'
                            : '$barcode · Stock: $available',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CronosSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(price),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    AppStatusChip(
                      label: canSell ? 'Agregar' : 'No vendible',
                      tone: canSell
                          ? AppStatusTone.success
                          : AppStatusTone.danger,
                      icon: canSell
                          ? Icons.add_circle_outline
                          : Icons.block_outlined,
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

class _CartSection extends StatelessWidget {
  const _CartSection({
    required this.cartItems,
    required this.paymentDrafts,
    required this.isCharging,
    required this.isEnqueueing,
    required this.isQuickSaleMode,
    required this.hasParkedSale,
    required this.paymentControllerFor,
    required this.onPaymentMethodChanged,
    required this.onPaymentAmountChanged,
    required this.onAddPaymentLine,
    required this.onRemovePaymentLine,
    required this.onFillCashPaymentWithTotal,
    required this.onIncrease,
    required this.onDecrease,
    required this.onEditQuantity,
    required this.onRemove,
    required this.onChargePressed,
    required this.onPrepareSyncPressed,
    required this.onStartQuickSale,
    required this.onRestoreParkedSale,
    required this.cashRegisterName,
    required this.cashSessionId,
  });

  final List<_PosCartItem> cartItems;
  final List<_PosPaymentDraft> paymentDrafts;
  final bool isCharging;
  final bool isEnqueueing;
  final bool isQuickSaleMode;
  final bool hasParkedSale;
  final TextEditingController Function(_PosPaymentDraft payment)
      paymentControllerFor;
  final void Function(String paymentId, String? method) onPaymentMethodChanged;
  final void Function(String paymentId, String rawValue) onPaymentAmountChanged;
  final VoidCallback onAddPaymentLine;
  final ValueChanged<String> onRemovePaymentLine;
  final VoidCallback onFillCashPaymentWithTotal;
  final ValueChanged<String> onIncrease;
  final ValueChanged<String> onDecrease;
  final ValueChanged<String> onEditQuantity;
  final ValueChanged<String> onRemove;
  final VoidCallback onChargePressed;
  final VoidCallback onPrepareSyncPressed;
  final VoidCallback onStartQuickSale;
  final VoidCallback onRestoreParkedSale;
  final String? cashRegisterName;
  final String? cashSessionId;

  @override
  Widget build(BuildContext context) {
    final subtotal = cartItems.fold<double>(
      0,
      (sum, item) => sum + item.lineTotal,
    );

    final paidTotal = paymentDrafts.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );

    final pending = math.max(0.0, subtotal - paidTotal);
    final change = math.max(0.0, paidTotal - subtotal);

    final itemCount = cartItems.fold<int>(
      0,
      (sum, item) => sum + item.quantity,
    );

    final canCharge =
        cartItems.isNotEmpty && subtotal > 0 && paidTotal >= subtotal;

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
              AppStatusChip(
                label: '$itemCount ítem(s)',
                tone: itemCount > 0
                    ? AppStatusTone.success
                    : AppStatusTone.neutral,
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
          const SizedBox(height: CronosSpacing.sm),
          if (isQuickSaleMode)
            AppStatusChip(
              label: 'Venta rápida activa',
              tone: AppStatusTone.info,
              icon: Icons.flash_on_outlined,
            ),
          const SizedBox(height: CronosSpacing.sm),
          OutlinedButton.icon(
            onPressed: isQuickSaleMode ? onRestoreParkedSale : onStartQuickSale,
            icon: Icon(
              isQuickSaleMode
                  ? Icons.assignment_return_outlined
                  : Icons.flash_on_outlined,
            ),
            label: Text(
              isQuickSaleMode ? 'Volver al carrito anterior' : 'Venta rápida',
            ),
          ),
          const SizedBox(height: CronosSpacing.xs),
          Text(
            isQuickSaleMode
                ? 'Cobra esta venta corta para restaurar el carrito anterior.'
                : 'Pausa el carrito actual para atender una venta corta.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: CronosSpacing.md),
          if (cartItems.isEmpty)
            const _EmptyCartState()
          else
            ...cartItems.map(
              (item) => _CartItemTile(
                item: item,
                onIncrease: () => onIncrease(item.productId),
                onDecrease: () => onDecrease(item.productId),
                onEditQuantity: () => onEditQuantity(item.productId),
                onRemove: () => onRemove(item.productId),
              ),
            ),
          const SizedBox(height: CronosSpacing.md),
          _PaymentPanel(
            paymentDrafts: paymentDrafts,
            paymentControllerFor: paymentControllerFor,
            onPaymentMethodChanged: onPaymentMethodChanged,
            onPaymentAmountChanged: onPaymentAmountChanged,
            onAddPaymentLine: onAddPaymentLine,
            onRemovePaymentLine: onRemovePaymentLine,
            onFillCashPaymentWithTotal: onFillCashPaymentWithTotal,
          ),
          const SizedBox(height: CronosSpacing.md),
          _TotalRow(label: 'Subtotal', value: _money(subtotal)),
          const _TotalRow(label: 'Descuentos', value: '\$0.00'),
          const _TotalRow(label: 'Impuestos', value: '\$0.00'),
          const Divider(height: CronosSpacing.lg),
          _TotalRow(
            label: 'Total',
            value: _money(subtotal),
            emphasized: true,
          ),
          _TotalRow(label: 'Pagado', value: _money(paidTotal)),
          _TotalRow(label: 'Pendiente', value: _money(pending)),
          if (change > 0) _TotalRow(label: 'Cambio', value: _money(change)),
          const SizedBox(height: CronosSpacing.md),
          FilledButton.icon(
            onPressed: canCharge && !isCharging ? onChargePressed : null,
            icon: isCharging
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline),
            label: Text(isCharging ? 'Registrando...' : 'Cobrar venta'),
          ),
          const SizedBox(height: CronosSpacing.sm),
          OutlinedButton.icon(
            onPressed: isEnqueueing ? null : onPrepareSyncPressed,
            icon: isEnqueueing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.playlist_add_check_outlined),
            label: Text(
              isEnqueueing ? 'Preparando...' : 'Preparar sync programado',
            ),
          ),
          const SizedBox(height: CronosSpacing.xs),
          Text(
            'Las ventas se suben automáticamente a las 11:00, 23:00 '
            'o al cierre de caja.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
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

class _PaymentPanel extends StatelessWidget {
  const _PaymentPanel({
    required this.paymentDrafts,
    required this.paymentControllerFor,
    required this.onPaymentMethodChanged,
    required this.onPaymentAmountChanged,
    required this.onAddPaymentLine,
    required this.onRemovePaymentLine,
    required this.onFillCashPaymentWithTotal,
  });

  final List<_PosPaymentDraft> paymentDrafts;
  final TextEditingController Function(_PosPaymentDraft payment)
      paymentControllerFor;
  final void Function(String paymentId, String? method) onPaymentMethodChanged;
  final void Function(String paymentId, String rawValue) onPaymentAmountChanged;
  final VoidCallback onAddPaymentLine;
  final ValueChanged<String> onRemovePaymentLine;
  final VoidCallback onFillCashPaymentWithTotal;

  @override
  Widget build(BuildContext context) {
    final isMixed = paymentDrafts.length > 1;

    return Container(
      padding: const EdgeInsets.all(CronosSpacing.md),
      decoration: BoxDecoration(
        color: CronosColors.surfaceMuted,
        borderRadius: BorderRadius.circular(CronosRadius.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isMixed ? Icons.call_split_outlined : Icons.payments_outlined,
                color: CronosColors.primary,
              ),
              const SizedBox(width: CronosSpacing.sm),
              Expanded(
                child: Text(
                  isMixed ? 'Pago mixto' : 'Pago',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              AppStatusChip(
                label: isMixed
                    ? 'Mixto'
                    : _paymentLabel(paymentDrafts.first.method),
                tone: isMixed ? AppStatusTone.info : AppStatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: CronosSpacing.md),
          ...paymentDrafts.map(
            (payment) => _PaymentLineTile(
              payment: payment,
              amountController: paymentControllerFor(payment),
              canRemove: paymentDrafts.length > 1,
              onMethodChanged: (method) {
                onPaymentMethodChanged(payment.id, method);
              },
              onAmountChanged: (value) {
                onPaymentAmountChanged(payment.id, value);
              },
              onRemove: () {
                onRemovePaymentLine(payment.id);
              },
            ),
          ),
          const SizedBox(height: CronosSpacing.sm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAddPaymentLine,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar pago'),
                ),
              ),
              const SizedBox(width: CronosSpacing.sm),
              IconButton.filledTonal(
                onPressed: onFillCashPaymentWithTotal,
                icon: const Icon(Icons.price_check_outlined),
                tooltip: 'Autocompletar efectivo',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PaymentLineTile extends StatelessWidget {
  const _PaymentLineTile({
    required this.payment,
    required this.amountController,
    required this.canRemove,
    required this.onMethodChanged,
    required this.onAmountChanged,
    required this.onRemove,
  });

  final _PosPaymentDraft payment;
  final TextEditingController amountController;
  final bool canRemove;
  final ValueChanged<String?> onMethodChanged;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final methodField = DropdownButtonFormField<String>(
      value: payment.method,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Método',
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(value: 'cash', child: Text('Efectivo')),
        DropdownMenuItem(value: 'bank_transfer', child: Text('Transferencia')),
        DropdownMenuItem(value: 'card', child: Text('Tarjeta')),
      ],
      onChanged: onMethodChanged,
    );

    final amountField = TextField(
      controller: amountController,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(
        labelText: 'Valor',
        isDense: true,
      ),
      onChanged: onAmountChanged,
    );

    final removeButton = IconButton(
      onPressed: canRemove ? onRemove : null,
      icon: const Icon(Icons.close),
      tooltip: 'Quitar pago',
      visualDensity: VisualDensity.compact,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: CronosSpacing.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 380;

          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                methodField,
                const SizedBox(height: CronosSpacing.sm),
                Row(
                  children: [
                    Expanded(child: amountField),
                    const SizedBox(width: CronosSpacing.xs),
                    removeButton,
                  ],
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                flex: 6,
                child: methodField,
              ),
              const SizedBox(width: CronosSpacing.sm),
              Expanded(
                flex: 5,
                child: amountField,
              ),
              const SizedBox(width: CronosSpacing.xs),
              SizedBox(
                width: 40,
                child: removeButton,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyCartState extends StatelessWidget {
  const _EmptyCartState();

  @override
  Widget build(BuildContext context) {
    return Container(
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
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
    required this.onEditQuantity,
    required this.onRemove,
  });

  final _PosCartItem item;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onEditQuantity;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: CronosSpacing.sm),
      child: Container(
        padding: const EdgeInsets.all(CronosSpacing.sm),
        decoration: BoxDecoration(
          color: CronosColors.surfaceMuted,
          borderRadius: BorderRadius.circular(CronosRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: Theme.of(context).textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.barcode == null || item.barcode!.isEmpty
                            ? 'Stock: ${item.quantityAvailable}'
                            : '${item.barcode} · Stock: ${item.quantityAvailable}',
                        style: Theme.of(context).textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: CronosSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _money(item.lineTotal),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    IconButton(
                      onPressed: onRemove,
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Eliminar',
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: CronosSpacing.sm),
            Wrap(
              spacing: CronosSpacing.xs,
              runSpacing: CronosSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton.filledTonal(
                  onPressed: onDecrease,
                  icon: const Icon(Icons.remove),
                  tooltip: 'Disminuir',
                  visualDensity: VisualDensity.compact,
                ),
                InkWell(
                  onTap: onEditQuantity,
                  borderRadius: BorderRadius.circular(CronosRadius.md),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: CronosSpacing.md,
                      vertical: CronosSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: CronosColors.surface,
                      borderRadius: BorderRadius.circular(CronosRadius.md),
                      border: Border.all(color: CronosColors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${item.quantity}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.edit_outlined, size: 16),
                      ],
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  onPressed: onIncrease,
                  icon: const Icon(Icons.add),
                  tooltip: 'Aumentar',
                  visualDensity: VisualDensity.compact,
                ),
                Chip(
                  label: Text('Disponible: ${item.quantityAvailable}'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityEditDialog extends StatefulWidget {
  const _QuantityEditDialog({
    required this.initialQuantity,
    required this.maxQuantity,
  });

  final int initialQuantity;
  final int maxQuantity;

  @override
  State<_QuantityEditDialog> createState() => _QuantityEditDialogState();
}

class _QuantityEditDialogState extends State<_QuantityEditDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();

    _controller = TextEditingController(
      text: widget.initialQuantity.toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    final parsed = int.tryParse(raw);

    if (parsed == null) {
      setState(() {
        _errorText = 'Ingresa un número válido.';
      });
      return;
    }

    if (parsed < 0) {
      setState(() {
        _errorText = 'La cantidad no puede ser negativa.';
      });
      return;
    }

    if (parsed > widget.maxQuantity) {
      setState(() {
        _errorText = 'Máximo disponible: ${widget.maxQuantity}.';
      });
      return;
    }

    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cambiar cantidad'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: 'Cantidad',
          helperText: 'Stock disponible: ${widget.maxQuantity}',
          errorText: _errorText,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Aplicar'),
        ),
      ],
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
          Expanded(child: Text(label)),
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

class _PosErrorState extends StatelessWidget {
  const _PosErrorState({
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppGlassCard(
        margin: const EdgeInsets.all(CronosSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: CronosColors.danger,
              size: 42,
            ),
            const SizedBox(height: CronosSpacing.sm),
            Text(
              'No se pudo cargar POS',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: CronosSpacing.xs),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _CartStockRefreshResult {
  const _CartStockRefreshResult({
    required this.items,
    required this.wasAdjusted,
    this.message,
  });

  final List<_PosCartItem> items;
  final bool wasAdjusted;
  final String? message;
}

class _PosCartItem {
  const _PosCartItem({
    required this.productId,
    required this.name,
    required this.unitPrice,
    required this.quantityAvailable,
    required this.quantity,
    this.barcode,
  });

  final String productId;
  final String name;
  final String? barcode;
  final double unitPrice;
  final int quantityAvailable;
  final int quantity;

  double get lineTotal => unitPrice * quantity;

  _PosCartItem copyWith({
    int? quantity,
    int? quantityAvailable,
  }) {
    return _PosCartItem(
      productId: productId,
      name: name,
      barcode: barcode,
      unitPrice: unitPrice,
      quantityAvailable: quantityAvailable ?? this.quantityAvailable,
      quantity: quantity ?? this.quantity,
    );
  }
}

class _PosPaymentDraft {
  const _PosPaymentDraft({
    required this.id,
    required this.method,
    required this.amount,
  });

  final String id;
  final String method;
  final double amount;

  _PosPaymentDraft copyWith({
    String? method,
    double? amount,
  }) {
    return _PosPaymentDraft(
      id: id,
      method: method ?? this.method,
      amount: amount ?? this.amount,
    );
  }
}

List<Map<String, dynamic>> _filterProducts(
  List<Map<String, dynamic>> products,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();

  if (normalizedQuery.isEmpty) {
    return products;
  }

  return products.where((product) {
    final name = (_string(product['product_name']) ?? '').toLowerCase();
    final barcode = (_string(product['barcode']) ?? '').toLowerCase();

    return name.contains(normalizedQuery) || barcode.contains(normalizedQuery);
  }).toList();
}

String? _string(Object? value) {
  if (value == null) {
    return null;
  }

  final text = value.toString().trim();

  if (text.isEmpty) {
    return null;
  }

  return text;
}

int _int(Object? value) {
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

double _num(Object? value) {
  if (value == null) {
    return 0;
  }

  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value.toString()) ?? 0;
}

double _parseMoney(String value) {
  final normalized = value.trim().replaceAll(',', '.');

  if (normalized.isEmpty) {
    return 0;
  }

  return double.tryParse(normalized) ?? 0;
}

String _paymentLabel(String method) {
  return switch (method) {
    'cash' => 'Efectivo',
    'bank_transfer' => 'Transferencia',
    'transfer' => 'Transferencia',
    'card' => 'Tarjeta',
    _ => method,
  };
}

String _money(Object? value) {
  return '\$${_num(value).toStringAsFixed(2)}';
}
