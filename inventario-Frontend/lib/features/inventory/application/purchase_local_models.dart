import '../../../core/models/product_sale_mode.dart';
import '../../../core/money/cop_price_input.dart';
import '../../../core/quantity/weight_quantity_input.dart';
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
    this.saleModeSnapshot = ProductSaleMode.unit,
    this.costBasisQuantitySnapshot = 1,
  });

  factory PurchaseLocalItemInput.weightedFromText({
    required String productId,
    required String quantityText,
    required WeightInputUnit inputUnit,
    required String quotedCostText,
    required int costBasisQuantitySnapshot,
  }) {
    final grams = parseWeightQuantity(quantityText, inputUnit);
    final cents = parseCopPriceCents(quotedCostText);
    if (grams == null ||
        cents == null ||
        costBasisQuantitySnapshot != 500 && costBasisQuantitySnapshot != 1000) {
      throw ArgumentError('Invalid weighted purchase quantity, cost or basis.');
    }
    return PurchaseLocalItemInput(
      productId: productId,
      quantity: grams,
      unitCostCents: BigInt.from(cents),
      saleModeSnapshot: ProductSaleMode.weight,
      costBasisQuantitySnapshot: costBasisQuantitySnapshot,
    );
  }

  final String productId;
  final int quantity;
  final BigInt unitCostCents;
  final ProductSaleMode saleModeSnapshot;
  final int costBasisQuantitySnapshot;

  /// UNIT: cost per unit. WEIGHT: quote per 500/1000 grams, never per gram.
  /// REAL is compatibility only; exact cents are the documentary source.
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
    required this.saleModeSnapshot,
    required this.costBasisQuantitySnapshot,
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
  final ProductSaleMode saleModeSnapshot;
  final int costBasisQuantitySnapshot;
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
      'sale_mode_snapshot': saleModeSnapshot.wireValue,
      'cost_basis_quantity_snapshot': costBasisQuantitySnapshot,
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
