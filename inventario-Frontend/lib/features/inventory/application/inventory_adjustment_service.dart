import 'dart:convert';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/app_uuid.dart';
import '../../sync/application/app_context_models.dart';
import '../../sync/application/local_sync_outbox_service.dart';
import '../../sync/data/datasources/local_sync_outbox_dao.dart';
import '../../sync/data/models/local_sync_outbox_models.dart';
import '../data/datasources/inventory_adjustment_local_dao.dart';
import 'inventory_adjustment_models.dart';

class InventoryAdjustmentService {
  InventoryAdjustmentService(
      {required AppDatabase database,
      required Future<AppCurrentContext?> Function() loadCurrentContext})
      : _dao = InventoryAdjustmentLocalDao(database),
        // Both participants must share this exact database/transaction zone.
        _outbox = LocalSyncOutboxService(LocalSyncOutboxDao(database)),
        _loadCurrentContext = loadCurrentContext;

  final InventoryAdjustmentLocalDao _dao;
  final LocalSyncOutboxService _outbox;
  final Future<AppCurrentContext?> Function() _loadCurrentContext;

  Future<InventoryAdjustmentResult> applyAdjustment(
      InventoryAdjustmentRequest request) async {
    request.validate();
    return _dao.transaction(() async {
      final context = await _loadCurrentContext();
      if (context == null ||
          !context.authorizationContextReady ||
          context.profileId != request.profileId ||
          context.businessId != request.businessId ||
          context.branchId != request.branchId ||
          context.installationId.trim().isEmpty ||
          context.appDeviceId?.trim().isNotEmpty != true) {
        throw const InventoryAdjustmentException(
            InventoryAdjustmentFailure.invalidContext);
      }
      if (!context.hasPermission('inventory.adjust')) {
        throw const InventoryAdjustmentException(
            InventoryAdjustmentFailure.permissionDenied);
      }
      await _dao.validateContext(context);
      await _dao.validateProduct(context.businessId, request.productId);

      final previous = await _dao.findMovement(request.idempotencyKey);
      if (previous != null) {
        final metadata = previous.metadataJson == null
            ? const <String, dynamic>{}
            : jsonDecode(previous.metadataJson!) as Map<String, dynamic>;
        if (previous.deletedAt != null ||
            previous.businessId != request.businessId ||
            previous.branchId != request.branchId ||
            previous.productId != request.productId ||
            previous.createdBy != context.profileId ||
            previous.quantityChange != request.delta ||
            previous.sourceType != request.reason.sourceType ||
            previous.movementType != request.reason.sourceType ||
            previous.notes != request.note ||
            metadata['source'] != 'inventory_adjustment' ||
            metadata['adjustment_reason'] != request.reason.code ||
            metadata['requested_occurred_at'] !=
                request.occurredAt?.toUtc().toIso8601String() ||
            previous.previousStock == null ||
            previous.newStock == null) {
          throw const InventoryAdjustmentException(
              InventoryAdjustmentFailure.idempotencyConflict);
        }
        return InventoryAdjustmentResult(
            movementId: previous.id,
            previousOnHand: previous.previousStock!,
            resultingOnHand: previous.newStock!,
            unitCost: previous.unitCost,
            alreadyApplied: true);
      }
      // The common outbox upserts by key. Never let a new adjustment overwrite another operation.
      if (await _dao.hasOutboxKey(request.idempotencyKey)) {
        throw const InventoryAdjustmentException(
            InventoryAdjustmentFailure.idempotencyConflict);
      }
      final balance = await _dao.balance(
          request.businessId, request.branchId, request.productId);
      final oldQuantity = balance?.quantityOnHand ?? 0;
      final reserved = balance?.quantityReserved ?? 0;
      final cost = balance?.averageCost;
      if (balance?.deletedAt != null ||
          oldQuantity < 0 ||
          reserved < 0 ||
          reserved > oldQuantity ||
          (balance != null &&
              balance.quantityAvailable != oldQuantity - reserved) ||
          (cost != null && (!cost.isFinite || cost < 0))) {
        throw const InventoryAdjustmentException(
            InventoryAdjustmentFailure.invalidBalance);
      }
      final nextQuantity = oldQuantity + request.delta;
      if (nextQuantity < 0) {
        throw const InventoryAdjustmentException(
            InventoryAdjustmentFailure.insufficientStock);
      }
      if (nextQuantity < reserved) {
        throw const InventoryAdjustmentException(
            InventoryAdjustmentFailure.reservedStockConflict);
      }
      if (nextQuantity > 2147483647) {
        throw const InventoryAdjustmentException(
            InventoryAdjustmentFailure.invalidRequest);
      }
      final now = DateTime.now().toUtc();
      final occurredAt = request.occurredAt?.toUtc() ?? now;
      final id = AppUuid.v7();
      // One mutation per batch; sequence follows the existing int32 contract.
      final sequence = now.microsecondsSinceEpoch.remainder(1999999999) + 1;
      final metadata = <String, dynamic>{
        'source': 'inventory_adjustment',
        'adjustment_reason': request.reason.code,
        'client_sequence': sequence,
        'requested_occurred_at': request.occurredAt?.toUtc().toIso8601String()
      };
      final payload = <String, dynamic>{
        'id': id,
        'business_id': context.businessId,
        'branch_id': context.branchId,
        'product_id': request.productId,
        'movement_type': request.reason.sourceType,
        'source_type': request.reason.sourceType,
        'source_id': id,
        'reference_type': 'inventory_adjustment',
        'reference_id': id,
        'quantity_change': request.delta,
        'unit_cost': cost,
        'notes': request.note,
        'idempotency_key': request.idempotencyKey,
        'occurred_at': occurredAt.toIso8601String(),
        'created_by': context.profileId,
        'sync_status': 'pending_upload',
        'local_status': 'dirty',
        'version': 1,
        'metadata': metadata
      };
      await _dao.writeBalance(
          previous: balance,
          context: context,
          productId: request.productId,
          onHand: nextQuantity,
          reserved: reserved,
          occurredAt: occurredAt,
          now: now);
      await _dao.insertMovement(LocalInventoryMovementsCompanion.insert(
          id: id,
          businessId: context.businessId,
          branchId: Value(context.branchId),
          productId: request.productId,
          movementType: request.reason.sourceType,
          sourceType: Value(request.reason.sourceType),
          sourceId: Value(id),
          referenceType: const Value('inventory_adjustment'),
          referenceId: Value(id),
          quantityChange: request.delta,
          unitCost: Value(cost),
          previousStock: Value(oldQuantity),
          newStock: Value(nextQuantity),
          createdBy: Value(context.profileId),
          deviceId: Value(context.appDeviceId),
          notes: Value(request.note),
          idempotencyKey: request.idempotencyKey,
          occurredAt: occurredAt,
          syncStatus: const Value(0),
          localStatus: const Value('dirty'),
          metadataJson: Value(jsonEncode(metadata)),
          createdAt: Value(now),
          updatedAt: Value(now)));
      await _outbox.enqueueInventoryMutations(
          businessId: context.businessId,
          branchId: context.branchId,
          appDeviceId: context.appDeviceId,
          profileId: context.profileId,
          deviceInstallationId: context.installationId,
          mutations: [
            LocalSyncMutationDraft(
                clientMutationId:
                    '${context.installationId}:mutation:$sequence:$id',
                clientSequence: sequence,
                entityTable: 'inventory_movements',
                entityId: id,
                operation: 'insert',
                payload: payload,
                changedFields: payload.keys.toList(),
                idempotencyKey: request.idempotencyKey,
                businessId: context.businessId,
                branchId: context.branchId,
                profileId: context.profileId,
                appDeviceId: context.appDeviceId)
          ],
          metadata: {
            'source': 'inventory_adjustment',
            'movement_id': id
          });
      return InventoryAdjustmentResult(
          movementId: id,
          previousOnHand: oldQuantity,
          resultingOnHand: nextQuantity,
          unitCost: cost,
          alreadyApplied: false);
    });
  }
}
