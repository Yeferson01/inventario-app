import 'purchase_money.dart';

/// Documentary money only. Never fall back to the legacy REAL total.
class PurchasePaymentBasis {
  const PurchasePaymentBasis({
    required this.purchaseId,
    required this.totalCents,
    required this.financiallyFinalized,
    required this.contractVersion,
  });

  final String purchaseId;
  final BigInt? totalCents;
  final bool financiallyFinalized;
  final String? contractVersion;

  bool get paymentEligible => financiallyFinalized && totalCents != null;
}

class PurchaseLocalItemInput {
  const PurchaseLocalItemInput({
    required this.productId,
    required this.quantity,
    required this.unitCostCents,
  });

  final String productId;
  final int quantity;
  final BigInt unitCostCents;

  /// Compatibility only: the documentary source of truth is unitCostCents.
  double get unitCost => double.parse(formatPurchaseMoneyCents(unitCostCents));
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
    required this.unitCostCents,
    required this.subtotalCents,
    required this.inventoryMovementId,
    required this.stockAfter,
  });

  final String itemId;
  final String productId;
  final int quantity;
  final double unitCost;
  final double subtotal;
  final BigInt unitCostCents;
  final BigInt subtotalCents;
  final String inventoryMovementId;
  final int stockAfter;

  Map<String, dynamic> toJson() {
    return {
      'item_id': itemId,
      'product_id': productId,
      'quantity': quantity,
      'unit_cost': unitCost,
      'subtotal': subtotal,
      'unit_cost_cents': unitCostCents.toString(),
      'subtotal_cents': subtotalCents.toString(),
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
    required this.totalCents,
    required this.itemCount,
    required this.lines,
  });

  final String purchaseId;
  final String businessId;
  final String branchId;
  final double total;
  final BigInt totalCents;
  final int itemCount;
  final List<PurchaseLocalLineResult> lines;

  Map<String, dynamic> toJson() {
    return {
      'purchase_id': purchaseId,
      'business_id': businessId,
      'branch_id': branchId,
      'total': total,
      'total_cents': totalCents.toString(),
      'item_count': itemCount,
      'lines': lines.map((line) => line.toJson()).toList(),
    };
  }
}
