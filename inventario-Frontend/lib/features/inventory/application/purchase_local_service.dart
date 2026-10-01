import '../../../core/database/app_database.dart';
import '../../../core/models/product_sale_mode.dart';
import '../../../core/money/exact_basis_money.dart';
import '../../../core/utils/app_uuid.dart';
import '../data/datasources/purchase_local_dao.dart';
import 'purchase_local_models.dart';
import 'purchase_money.dart';

class PurchaseLocalService {
  PurchaseLocalService({
    required PurchaseLocalDao dao,
    void Function()? onCommitted,
    bool enableWeightedDomain = false,
  })  : _dao = dao,
        _onCommitted = onCommitted,
        _enableWeightedDomain = enableWeightedDomain;

  final PurchaseLocalDao _dao;
  final void Function()? _onCommitted;
  // The productive provider enables WEIGHT at W4C; other callers remain gated.
  final bool _enableWeightedDomain;

  Future<PurchasePaymentBasis?> getPaymentBasis({
    required String purchaseId,
    required String businessId,
    required String branchId,
  }) async {
    final row = await _dao.getPurchasePaymentBasisRow(
      purchaseId: purchaseId,
      businessId: businessId,
      branchId: branchId,
    );
    if (row == null) return null;
    final cents = row['total_cents'];
    return PurchasePaymentBasis(
      purchaseId: row['id'] as String,
      totalCents: cents is int ? BigInt.from(cents) : null,
      financiallyFinalized: row['financial_finalized_at'] != null,
      contractVersion: row['monetary_contract_version'] as String?,
    );
  }

  Future<PurchaseLocalResult> createLocalPurchase(
    CreatePurchaseLocalInput input,
  ) async {
    _validateInput(input);

    final now = DateTime.now().toUtc();
    final purchaseId = AppUuid.v7();
    final sequenceStart = input.clientSequenceStart ?? _safeClientSequence();

    final itemDrafts = <Map<String, dynamic>>[];
    final movementDrafts = <Map<String, dynamic>>[];
    final lineResults = <PurchaseLocalLineResult>[];

    var totalCents = BigInt.zero;
    var sequence = sequenceStart;
    final stockAfterByProduct = <String, int>{};

    for (final item in input.items) {
      if (item.saleModeSnapshot == ProductSaleMode.weight &&
          !_enableWeightedDomain) {
        throw StateError('weighted_purchase_not_available');
      }
      sequence++;

      await _dao.getRequiredProductSnapshot(
        businessId: input.businessId,
        productId: item.productId,
        expectedSaleMode: item.saleModeSnapshot,
      );

      final balance = await _dao.getLocalStockBalance(
        businessId: input.businessId,
        branchId: input.branchId,
        productId: item.productId,
      );

      final stockBefore = stockAfterByProduct[item.productId] ??
          _int(balance?['quantity_available']);
      final stockAfter = checkedSignedInt64(
        BigInt.from(stockBefore) + BigInt.from(item.quantity),
      );
      stockAfterByProduct[item.productId] = stockAfter;
      final subtotalCents = purchaseBasisLineTotalCents(
        quotedCostCents: item.unitCostCents,
        quantity: item.quantity,
        costBasisQuantity: item.costBasisQuantitySnapshot,
      );
      final subtotal = double.parse(formatPurchaseMoneyCents(subtotalCents));

      final itemId = AppUuid.v7();
      final movementId = AppUuid.v7();

      totalCents += subtotalCents;
      if (totalCents > BigInt.from(purchaseMoneyMaxCents)) {
        throw RangeError('Purchase total exceeds numeric(12,2) range.');
      }

      final itemIdempotencyKey =
          '${input.deviceInstallationId ?? input.profileId}:'
          'purchase_items:$itemId:insert';

      itemDrafts.add({
        'id': itemId,
        'purchase_id': purchaseId,
        'business_id': input.businessId,
        'branch_id': input.branchId,
        'product_id': item.productId,
        'quantity': item.quantity,
        'sale_mode_snapshot': item.saleModeSnapshot.wireValue,
        'cost_basis_quantity_snapshot': item.costBasisQuantitySnapshot,
        'unit_cost': item.unitCost,
        'subtotal': subtotal,
        'unit_cost_cents': item.unitCostCents.toInt(),
        'subtotal_cents': subtotalCents.toInt(),
        'idempotency_key': itemIdempotencyKey,
        'local_status': 'dirty',
        'metadata': {
          'source': 'purchase_local_service',
          'stock_before': stockBefore,
          'stock_after': stockAfter,
          'unit_cost_cents': item.unitCostCents.toString(),
          'subtotal_cents': subtotalCents.toString(),
          'sale_mode_snapshot': item.saleModeSnapshot.wireValue,
          'cost_basis_quantity_snapshot': item.costBasisQuantitySnapshot,
        },
        'version': 1,
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
        'last_synced_at': null,
        'sync_status': SyncStatus.pendingInsert.index,
      });

      final movementIdempotencyKey =
          '${input.deviceInstallationId ?? input.profileId}:'
          'inventory_movements:$movementId:purchase:$sequence';

      movementDrafts.add({
        'id': movementId,
        'business_id': input.businessId,
        'branch_id': input.branchId,
        'product_id': item.productId,
        'movement_type': 'purchase',
        'quantity_change': item.quantity,
        'sale_mode_snapshot': item.saleModeSnapshot.wireValue,
        'cost_effect_cents': item.saleModeSnapshot == ProductSaleMode.weight
            ? subtotalCents.toInt()
            : null,
        'unit_cost': item.unitCost,
        'source_type': 'purchase',
        'source_id': purchaseId,
        'reference_type': 'purchase_item',
        'reference_id': itemId,
        'notes': 'Local purchase inventory movement',
        'idempotency_key': movementIdempotencyKey,
        'sync_status': SyncStatus.pendingInsert.index,
        'local_status': 'dirty',
        'version': 1,
        'occurred_at': now,
        'metadata': {
          'source': 'purchase_local_service',
          'purchase_id': purchaseId,
          'purchase_item_id': itemId,
          'client_sequence': sequence,
          'stock_before': stockBefore,
          'stock_after': stockAfter,
          'sale_mode_snapshot': item.saleModeSnapshot.wireValue,
          'cost_basis_quantity_snapshot': item.costBasisQuantitySnapshot,
          'quoted_cost_cents': item.unitCostCents.toString(),
          'subtotal_cents': subtotalCents.toString(),
        },
        'created_at': now,
        'updated_at': now,
        'deleted_at': null,
        'last_synced_at': null,
      });

      lineResults.add(
        PurchaseLocalLineResult(
          itemId: itemId,
          productId: item.productId,
          quantity: item.quantity,
          unitCost: item.unitCost,
          subtotal: subtotal,
          unitCostCents: item.unitCostCents,
          subtotalCents: subtotalCents,
          saleModeSnapshot: item.saleModeSnapshot,
          costBasisQuantitySnapshot: item.costBasisQuantitySnapshot,
          inventoryMovementId: movementId,
          stockAfter: stockAfter,
        ),
      );
    }

    final purchaseIdempotencyKey =
        '${input.deviceInstallationId ?? input.profileId}:purchases:$purchaseId';

    final hasWeight = input.items.any(
      (item) => item.saleModeSnapshot == ProductSaleMode.weight,
    );
    final monetaryContractVersion =
        hasWeight ? 'exact_weight_basis_v1' : 'exact_v1';
    final purchaseDraft = {
      'id': purchaseId,
      'business_id': input.businessId,
      'branch_id': input.branchId,
      'supplier_id': input.supplierId,
      'user_id': input.profileId,
      'total': double.parse(formatPurchaseMoneyCents(totalCents)),
      'total_cents': totalCents.toInt(),
      'monetary_contract_version': monetaryContractVersion,
      'status': 'completed',
      'created_at': now,
      'updated_at': now,
      'deleted_at': null,
      'last_synced_at': null,
      'invoice_photo_url': null,
      'processing_status': 'completed',
      'supplier_name': input.supplierName,
      'idempotency_key': purchaseIdempotencyKey,
      'local_status': 'dirty',
      'metadata': {
        ...input.metadata,
        'source': 'purchase_local_service',
        'app_device_id': input.appDeviceId,
        'device_installation_id': input.deviceInstallationId,
        'item_count': input.items.length,
        'monetary_contract_version': monetaryContractVersion,
        'total_cents': totalCents.toString(),
      },
      'version': 1,
      'sync_status': SyncStatus.pendingInsert.index,
    };

    await _dao.insertPurchaseWithLocalInventoryImpact(
      purchase: purchaseDraft,
      items: itemDrafts,
      inventoryMovements: movementDrafts,
    );
    _onCommitted?.call();

    return PurchaseLocalResult(
      purchaseId: purchaseId,
      businessId: input.businessId,
      branchId: input.branchId,
      total: double.parse(formatPurchaseMoneyCents(totalCents)),
      totalCents: totalCents,
      itemCount: itemDrafts.length,
      lines: lineResults,
    );
  }

  void _validateInput(CreatePurchaseLocalInput input) {
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
      throw ArgumentError('La compra debe tener al menos un producto.');
    }

    for (final item in input.items) {
      if (item.productId.trim().isEmpty) {
        throw ArgumentError('productId es requerido.');
      }

      if (item.quantity <= 0) {
        throw ArgumentError('La cantidad debe ser mayor a cero.');
      }

      if (item.unitCostCents < BigInt.zero ||
          item.unitCostCents > BigInt.from(purchaseMoneyMaxCents)) {
        throw ArgumentError('El costo unitario no puede ser negativo.');
      }
      final validBasis = switch (item.saleModeSnapshot) {
        ProductSaleMode.unit => item.costBasisQuantitySnapshot == 1,
        ProductSaleMode.weight => item.costBasisQuantitySnapshot == 500 ||
            item.costBasisQuantitySnapshot == 1000,
      };
      if (!validBasis) {
        throw ArgumentError('Base de costo incompatible con forma de venta.');
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
}
