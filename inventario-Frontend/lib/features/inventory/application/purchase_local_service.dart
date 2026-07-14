import '../../../core/database/app_database.dart';
import '../../../core/utils/app_uuid.dart';
import '../data/datasources/purchase_local_dao.dart';
import 'purchase_local_models.dart';

class PurchaseLocalService {
  PurchaseLocalService({
    required PurchaseLocalDao dao,
  }) : _dao = dao;

  final PurchaseLocalDao _dao;

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

    var total = 0.0;
    var sequence = sequenceStart;

    for (final item in input.items) {
      sequence++;

      await _dao.getRequiredProductSnapshot(
        businessId: input.businessId,
        productId: item.productId,
      );

      final balance = await _dao.getLocalStockBalance(
        businessId: input.businessId,
        branchId: input.branchId,
        productId: item.productId,
      );

      final stockBefore = _int(balance?['quantity_available']);
      final stockAfter = stockBefore + item.quantity;
      final subtotal = item.quantity * item.unitCost;

      final itemId = AppUuid.v7();
      final movementId = AppUuid.v7();

      total += subtotal;

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
        'unit_cost': item.unitCost,
        'subtotal': subtotal,
        'idempotency_key': itemIdempotencyKey,
        'local_status': 'dirty',
        'metadata': {
          'source': 'purchase_local_service',
          'stock_before': stockBefore,
          'stock_after': stockAfter,
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
          inventoryMovementId: movementId,
          stockAfter: stockAfter,
        ),
      );
    }

    final purchaseIdempotencyKey =
        '${input.deviceInstallationId ?? input.profileId}:purchases:$purchaseId';

    final purchaseDraft = {
      'id': purchaseId,
      'business_id': input.businessId,
      'branch_id': input.branchId,
      'supplier_id': input.supplierId,
      'user_id': input.profileId,
      'total': total,
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
      },
      'version': 1,
      'sync_status': SyncStatus.pendingInsert.index,
    };

    await _dao.insertPurchaseWithLocalInventoryImpact(
      purchase: purchaseDraft,
      items: itemDrafts,
      inventoryMovements: movementDrafts,
    );

    return PurchaseLocalResult(
      purchaseId: purchaseId,
      businessId: input.businessId,
      branchId: input.branchId,
      total: total,
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

      if (item.unitCost < 0) {
        throw ArgumentError('El costo unitario no puede ser negativo.');
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
