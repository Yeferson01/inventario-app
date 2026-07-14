class PosLocalSaleItemInput {
  const PosLocalSaleItemInput({
    required this.productId,
    required this.quantity,
    this.unitPrice,
    this.discountTotal = 0,
    this.taxTotal = 0,
  });

  final String productId;
  final int quantity;
  final double? unitPrice;
  final double discountTotal;
  final double taxTotal;
}

class PosLocalPaymentInput {
  const PosLocalPaymentInput({
    required this.method,
    required this.amount,
    this.reference,
  });

  final String method;
  final double amount;
  final String? reference;
}

class CreatePosLocalSaleInput {
  const CreatePosLocalSaleInput({
    required this.businessId,
    required this.branchId,
    required this.profileId,
    required this.items,
    this.payments = const [],
    this.customerId,
    this.cashRegisterId,
    this.cashSessionId,
    this.appDeviceId,
    this.deviceInstallationId,
    this.clientSequenceStart,
    this.metadata = const {},
  });

  final String businessId;
  final String branchId;
  final String profileId;
  final List<PosLocalSaleItemInput> items;
  final List<PosLocalPaymentInput> payments;
  final String? customerId;
  final String? cashRegisterId;
  final String? cashSessionId;
  final String? appDeviceId;
  final String? deviceInstallationId;
  final int? clientSequenceStart;
  final Map<String, dynamic> metadata;
}

class PosLocalSaleLineResult {
  const PosLocalSaleLineResult({
    required this.itemId,
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    required this.inventoryMovementId,
    required this.stockAfter,
  });

  final String itemId;
  final String productId;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final String inventoryMovementId;
  final int stockAfter;

  Map<String, dynamic> toJson() {
    return {
      'item_id': itemId,
      'product_id': productId,
      'quantity': quantity,
      'unit_price': unitPrice,
      'line_total': lineTotal,
      'inventory_movement_id': inventoryMovementId,
      'stock_after': stockAfter,
    };
  }
}

class PosLocalSaleResult {
  const PosLocalSaleResult({
    required this.saleId,
    required this.businessId,
    required this.branchId,
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.total,
    required this.paymentTotal,
    required this.itemCount,
    required this.paymentCount,
    required this.lines,
  });

  final String saleId;
  final String businessId;
  final String branchId;
  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double total;
  final double paymentTotal;
  final int itemCount;
  final int paymentCount;
  final List<PosLocalSaleLineResult> lines;

  Map<String, dynamic> toJson() {
    return {
      'sale_id': saleId,
      'business_id': businessId,
      'branch_id': branchId,
      'subtotal': subtotal,
      'discount_total': discountTotal,
      'tax_total': taxTotal,
      'total': total,
      'payment_total': paymentTotal,
      'item_count': itemCount,
      'payment_count': paymentCount,
      'lines': lines.map((line) => line.toJson()).toList(),
    };
  }
}
