import '../../../core/database/app_database.dart';
import '../../../core/utils/app_uuid.dart';
import '../data/datasources/pos_local_sale_dao.dart';
import 'pos_local_sale_models.dart';

class PosLocalSaleService {
  PosLocalSaleService({
    required PosLocalSaleDao dao,
  }) : _dao = dao;

  final PosLocalSaleDao _dao;

  Future<PosLocalSaleResult> createLocalSale(
    CreatePosLocalSaleInput input,
  ) async {
    _validateInput(input);

    final now = DateTime.now().toUtc();
    final saleId = AppUuid.v7();
    final sequenceStart = input.clientSequenceStart ?? _safeClientSequence();

    final lineDrafts = <Map<String, dynamic>>[];
    final movementDrafts = <Map<String, dynamic>>[];
    final lineResults = <PosLocalSaleLineResult>[];

    var subtotal = 0.0;
    var discountTotal = 0.0;
    var taxTotal = 0.0;
    var sequence = sequenceStart;

    for (final item in input.items) {
      sequence++;

      final product = await _dao.getRequiredProductSnapshot(
        businessId: input.businessId,
        productId: item.productId,
      );

      final balance = await _dao.getRequiredStockBalance(
        businessId: input.businessId,
        branchId: input.branchId,
        productId: item.productId,
      );

      final quantityAvailable = _int(balance['quantity_available']);

      if (quantityAvailable < item.quantity) {
        throw StateError(
          'Stock insuficiente para product=${item.productId}. '
          'Disponible=$quantityAvailable requerido=${item.quantity}',
        );
      }

      final unitPrice = item.unitPrice ?? _double(product['sale_price']);

      if (unitPrice <= 0) {
        throw StateError(
          'Precio de venta inválido para product=${item.productId}: $unitPrice',
        );
      }

      final itemSubtotal = unitPrice * item.quantity;
      final itemLineTotal = itemSubtotal - item.discountTotal + item.taxTotal;

      final itemId = AppUuid.v7();
      final movementId = AppUuid.v7();
      final movementQuantity = -item.quantity;
      final stockAfter = quantityAvailable + movementQuantity;

      subtotal += itemSubtotal;
      discountTotal += item.discountTotal;
      taxTotal += item.taxTotal;

      lineDrafts.add({
        'id': itemId,
        'sale_id': saleId,
        'product_id': item.productId,
        'product_name_snapshot': _nullableString(product['name']),
        'barcode_snapshot': _nullableString(product['barcode']),
        'quantity': item.quantity,
        'unit_price': unitPrice,
        'discount_total': item.discountTotal,
        'tax_total': item.taxTotal,
        'subtotal': itemSubtotal,
        'line_total': itemLineTotal,
        'metadata': {
          'source': 'pos_local_sale_service',
          'stock_before': quantityAvailable,
          'stock_after': stockAfter,
        },
        'created_at': now,
        'updated_at': now,
        'sync_status': SyncStatus.pendingInsert.index,
      });

      final movementIdempotencyKey =
          '${input.deviceInstallationId ?? input.profileId}:'
          'inventory_movements:$movementId:sale:$sequence';

      movementDrafts.add({
        'id': movementId,
        'business_id': input.businessId,
        'branch_id': input.branchId,
        'product_id': item.productId,
        'movement_type': 'sale',
        'quantity_change': movementQuantity,
        'unit_cost': null,
        'source_type': 'sale',
        'source_id': saleId,
        'reference_type': 'sale',
        'reference_id': saleId,
        'notes': 'POS local sale inventory movement',
        'idempotency_key': movementIdempotencyKey,
        'sync_status': SyncStatus.pendingInsert.index,
        'local_status': 'dirty',
        'version': 1,
        'occurred_at': now,
        'metadata': {
          'source': 'pos_local_sale_service',
          'sale_id': saleId,
          'sale_item_id': itemId,
          'client_sequence': sequence,
          'stock_before': quantityAvailable,
          'stock_after': stockAfter,
        },
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
        'last_synced_at': null,
      });

      lineResults.add(
        PosLocalSaleLineResult(
          itemId: itemId,
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: unitPrice,
          lineTotal: itemLineTotal,
          inventoryMovementId: movementId,
          stockAfter: stockAfter,
        ),
      );
    }

    final total = subtotal - discountTotal + taxTotal;

    final paymentInputs = input.payments.isEmpty
        ? [
            PosLocalPaymentInput(
              method: 'cash',
              amount: total,
            ),
          ]
        : input.payments;

    final paymentTotal = paymentInputs.fold<double>(
      0,
      (sum, payment) => sum + payment.amount,
    );

    if ((paymentTotal - total).abs() > 0.01) {
      throw StateError(
        'El total pagado no coincide con el total de la venta. '
        'total=$total paymentTotal=$paymentTotal',
      );
    }

    final paymentDrafts = paymentInputs.map((payment) {
      return {
        'id': AppUuid.v7(),
        'business_id': input.businessId,
        'branch_id': input.branchId,
        'sale_id': saleId,
        'payment_method': payment.method,
        'amount': payment.amount,
        'currency': 'COP',
        'status': 'completed',
        'reference': payment.reference,
        'metadata': {
          'source': 'pos_local_sale_service',
        },
        'sync_status': SyncStatus.pendingInsert.index,
        'local_status': 'dirty',
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
      };
    }).toList();

    final saleIdempotencyKey =
        '${input.deviceInstallationId ?? input.profileId}:sales:$saleId';

    final saleDraft = {
      'id': saleId,
      'business_id': input.businessId,
      'user_id': input.profileId,
      'customer_id': input.customerId,
      'branch_id': input.branchId,
      'cash_register_id': input.cashRegisterId,
      'cash_session_id': input.cashSessionId,
      'subtotal': subtotal,
      'discount_total': discountTotal,
      'tax_total': taxTotal,
      'total': total,
      'payment_method': paymentInputs.first.method,
      'payment_status': 'paid',
      'idempotency_key': saleIdempotencyKey,
      'local_status': 'dirty',
      'metadata': {
        ...input.metadata,
        'source': 'pos_local_sale_service',
        'app_device_id': input.appDeviceId,
        'device_installation_id': input.deviceInstallationId,
        'item_count': input.items.length,
      },
      'status': 'completed',
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'sync_status': SyncStatus.pendingInsert.index,
    };

    await _dao.insertSaleWithLocalInventoryImpact(
      sale: saleDraft,
      items: lineDrafts,
      payments: paymentDrafts,
      inventoryMovements: movementDrafts,
    );

    return PosLocalSaleResult(
      saleId: saleId,
      businessId: input.businessId,
      branchId: input.branchId,
      subtotal: subtotal,
      discountTotal: discountTotal,
      taxTotal: taxTotal,
      total: total,
      paymentTotal: paymentTotal,
      itemCount: lineDrafts.length,
      paymentCount: paymentDrafts.length,
      lines: lineResults,
    );
  }

  void _validateInput(CreatePosLocalSaleInput input) {
    if (input.businessId.trim().isEmpty) {
      throw ArgumentError('businessId es requerido.');
    }

    if (input.branchId.trim().isEmpty) {
      throw ArgumentError('branchId es requerido.');
    }

    if (input.profileId.trim().isEmpty) {
      throw ArgumentError('profileId es requerido.');
    }

    if (input.items.isEmpty) {
      throw ArgumentError('La venta debe tener al menos un producto.');
    }

    for (final item in input.items) {
      if (item.productId.trim().isEmpty) {
        throw ArgumentError('productId es requerido.');
      }

      if (item.quantity <= 0) {
        throw ArgumentError('La cantidad debe ser mayor a cero.');
      }

      if (item.discountTotal < 0 || item.taxTotal < 0) {
        throw ArgumentError('Descuento/impuesto no pueden ser negativos.');
      }
    }

    for (final payment in input.payments) {
      if (payment.method.trim().isEmpty) {
        throw ArgumentError('Método de pago requerido.');
      }

      if (payment.amount <= 0) {
        throw ArgumentError('El pago debe ser mayor a cero.');
      }
    }
  }

  int _safeClientSequence() {
    final value =
        DateTime.now().toUtc().microsecondsSinceEpoch.remainder(2000000000);

    if (value < 1) {
      return 1;
    }

    return value;
  }

  int _int(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  double _double(Object? value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  String? _nullableString(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }
}
