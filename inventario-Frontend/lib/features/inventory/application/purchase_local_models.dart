class PurchaseLocalItemInput {
  const PurchaseLocalItemInput({
    required this.productId,
    required this.quantity,
    required this.unitCost,
  });

  final String productId;
  final int quantity;
  final double unitCost;
}

class CreatePurchaseLocalInput {
  const CreatePurchaseLocalInput({
    required this.businessId,
    required this.branchId,
    required this.profileId,
    required this.items,
    this.supplierId,
    this.supplierName,
    this.appDeviceId,
    this.deviceInstallationId,
    this.clientSequenceStart,
    this.metadata = const {},
  });

  final String businessId;
  final String branchId;
  final String profileId;
  final List<PurchaseLocalItemInput> items;
  final String? supplierId;
  final String? supplierName;
  final String? appDeviceId;
  final String? deviceInstallationId;
  final int? clientSequenceStart;
  final Map<String, dynamic> metadata;
}

class PurchaseLocalLineResult {
  const PurchaseLocalLineResult({
    required this.itemId,
    required this.productId,
    required this.quantity,
    required this.unitCost,
    required this.subtotal,
    required this.inventoryMovementId,
    required this.stockAfter,
  });

  final String itemId;
  final String productId;
  final int quantity;
  final double unitCost;
  final double subtotal;
  final String inventoryMovementId;
  final int stockAfter;

  Map<String, dynamic> toJson() {
    return {
      'item_id': itemId,
      'product_id': productId,
      'quantity': quantity,
      'unit_cost': unitCost,
      'subtotal': subtotal,
      'inventory_movement_id': inventoryMovementId,
      'stock_after': stockAfter,
    };
  }
}

class PurchaseLocalResult {
  const PurchaseLocalResult({
    required this.purchaseId,
    required this.businessId,
    required this.branchId,
    required this.total,
    required this.itemCount,
    required this.lines,
  });

  final String purchaseId;
  final String businessId;
  final String branchId;
  final double total;
  final int itemCount;
  final List<PurchaseLocalLineResult> lines;

  Map<String, dynamic> toJson() {
    return {
      'purchase_id': purchaseId,
      'business_id': businessId,
      'branch_id': branchId,
      'total': total,
      'item_count': itemCount,
      'lines': lines.map((line) => line.toJson()).toList(),
    };
  }
}
