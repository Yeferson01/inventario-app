import '../../../core/utils/app_uuid.dart';
import '../../sync/application/local_sync_outbox_service.dart';
import '../../sync/data/models/local_sync_outbox_models.dart';
import '../data/datasources/inventory_movement_local_dao.dart';
import 'inventory_initial_stock_models.dart';

class InventoryInitialStockService {
  InventoryInitialStockService({
    required InventoryMovementLocalDao localDao,
    required LocalSyncOutboxService outboxService,
  })  : _localDao = localDao,
        _outboxService = outboxService;

  final InventoryMovementLocalDao _localDao;
  final LocalSyncOutboxService _outboxService;

  Future<InitialStockSyncResult> createInitialStockAndQueueSync(
    CreateInitialStockInput input,
  ) async {
    if (input.quantity <= 0) {
      throw ArgumentError('La cantidad inicial debe ser mayor que cero.');
    }

    if (input.unitCost < 0) {
      throw ArgumentError('El costo unitario no puede ser negativo.');
    }

    final movementId = AppUuid.v7();
    final occurredAt = DateTime.now().toUtc();
    final sequence = _safeSequence(input.clientSequenceStart);
    final idempotencyKey =
        '${input.deviceInstallationId}:inventory_movements:$movementId:insert:$sequence';

    final metadata = {
      'source': 'flutter_e2e_initial_stock',
      'phase': '6.18C.28',
      'product_id': input.productId,
    };

    final payload = {
      'id': movementId,
      'business_id': input.businessId,
      'branch_id': input.branchId,
      'product_id': input.productId,
      'movement_type': 'manual_adjustment',
      'quantity_change': input.quantity,
      'unit_cost': input.unitCost,
      'source_type': 'manual_adjustment',
      'source_id': null,
      'reference_type': 'manual_initial_stock',
      'reference_id': null,
      'notes': input.notes,
      'idempotency_key': idempotencyKey,
      'sync_status': 'pending_upload',
      'local_status': 'dirty',
      'version': 1,
      'occurred_at': occurredAt.toIso8601String(),
      'metadata': metadata,
    };

    await _localDao.insertInitialMovement(
      id: movementId,
      businessId: input.businessId,
      branchId: input.branchId,
      productId: input.productId,
      movementType: 'manual_adjustment',
      quantityChange: input.quantity,
      unitCost: input.unitCost,
      sourceType: 'manual_adjustment',
      referenceType: 'manual_initial_stock',
      notes: input.notes,
      idempotencyKey: idempotencyKey,
      occurredAt: occurredAt,
      metadata: metadata,
    );

    final mutation = LocalSyncMutationDraft(
      clientMutationId:
          '${input.deviceInstallationId}:mutation:$sequence:$movementId',
      clientSequence: sequence,
      entityTable: 'inventory_movements',
      entityId: movementId,
      operation: 'insert',
      payload: payload,
      changedFields: const [
        'id',
        'business_id',
        'branch_id',
        'product_id',
        'movement_type',
        'quantity_change',
        'unit_cost',
        'source_type',
        'source_id',
        'reference_type',
        'reference_id',
        'notes',
        'idempotency_key',
        'sync_status',
        'local_status',
        'version',
        'occurred_at',
        'metadata',
      ],
      idempotencyKey: idempotencyKey,
      businessId: input.businessId,
      branchId: input.branchId,
      profileId: input.profileId,
      appDeviceId: input.appDeviceId,
      metadata: {
        'source': 'flutter_local_inventory_movement',
        'phase': '6.18C.28',
      },
    );

    final outboxResult = await _outboxService.enqueueInventoryMutations(
      businessId: input.businessId,
      branchId: input.branchId,
      appDeviceId: input.appDeviceId,
      profileId: input.profileId,
      deviceInstallationId: input.deviceInstallationId,
      mutations: [mutation],
      metadata: {
        'source': 'initial_stock',
        'product_id': input.productId,
        'movement_id': movementId,
        'quantity_change': input.quantity,
      },
    );

    return InitialStockSyncResult(
      movementId: movementId,
      payload: payload,
      outboxResult: outboxResult,
    );
  }

  int _safeSequence(int value) {
    if (value > 0 && value < 2000000000) {
      return value;
    }

    final generated =
        DateTime.now().toUtc().microsecondsSinceEpoch.remainder(2000000000);

    if (generated < 1) {
      return 1;
    }

    return generated;
  }
}
