import '../../../core/database/app_database.dart';
import '../data/datasources/inventory_movement_local_dao.dart';
import '../data/datasources/product_stock_balance_local_dao.dart';
import 'inventory_transfer_models.dart';

typedef InventoryTransferExecutor = Future<InventoryTransferResult> Function(
  CreateInventoryTransferInput input,
);

class InventoryTransferService {
  InventoryTransferService({
    required AppDatabase database,
    required InventoryTransferExecutor executeRemote,
    required InventoryMovementLocalDao movementDao,
    required ProductStockBalanceLocalDao balanceDao,
  })  : _database = database,
        _executeRemote = executeRemote,
        _movementDao = movementDao,
        _balanceDao = balanceDao;

  final AppDatabase _database;
  final InventoryTransferExecutor _executeRemote;
  final InventoryMovementLocalDao _movementDao;
  final ProductStockBalanceLocalDao _balanceDao;
  final Map<String, Future<InventoryTransferResult>> _inFlight = {};

  Future<InventoryTransferResult> transfer(
    CreateInventoryTransferInput input,
  ) {
    _validate(input);
    final existing = _inFlight[input.idempotencyKey];
    if (existing != null) {
      return existing;
    }

    late final Future<InventoryTransferResult> tracked;
    tracked = _execute(input).whenComplete(() {
      if (identical(_inFlight[input.idempotencyKey], tracked)) {
        _inFlight.remove(input.idempotencyKey);
      }
    });
    _inFlight[input.idempotencyKey] = tracked;
    return tracked;
  }

  Future<InventoryTransferResult> _execute(
    CreateInventoryTransferInput input,
  ) async {
    final result = await _executeRemote(input);
    _validateResult(input, result);

    await _database.transaction(() async {
      await _projectMovement(result.sourceMovement);
      await _projectMovement(result.destinationMovement);
      await _balanceDao.upsertRemoteBalance(result.sourceBalance);
      await _balanceDao.upsertRemoteBalance(result.destinationBalance);
    });

    return result;
  }

  Future<void> _projectMovement(
    InventoryTransferMovementProjection movement,
  ) {
    return _movementDao.upsertSyncedTransferMovement(
      id: movement.id,
      businessId: movement.businessId,
      branchId: movement.branchId,
      productId: movement.productId,
      quantityChange: movement.quantityChange,
      unitCost: movement.unitCost,
      transferId: movement.sourceId,
      idempotencyKey: movement.idempotencyKey,
      occurredAt: movement.occurredAt,
      metadata: movement.metadata,
    );
  }

  void _validate(CreateInventoryTransferInput input) {
    if (input.quantity <= 0) {
      throw const InventoryTransferException(
        kind: InventoryTransferFailureKind.invalidQuantity,
        message: 'La cantidad debe ser mayor que cero.',
      );
    }
    if (input.fromBranchId == input.toBranchId) {
      throw const InventoryTransferException(
        kind: InventoryTransferFailureKind.sameBranch,
        message:
            'La sucursal destino debe ser diferente de la sucursal origen.',
      );
    }
    if ([
      input.businessId,
      input.fromBranchId,
      input.toBranchId,
      input.productId,
      input.transferId,
      input.transferItemId,
      input.idempotencyKey,
    ].any((value) => value.trim().isEmpty)) {
      throw const InventoryTransferException(
        kind: InventoryTransferFailureKind.invalidDestination,
        message: 'La transferencia requiere producto y sucursales válidas.',
      );
    }
  }

  void _validateResult(
    CreateInventoryTransferInput input,
    InventoryTransferResult result,
  ) {
    final matches = result.transferId == input.transferId &&
        result.transferItemId == input.transferItemId &&
        result.businessId == input.businessId &&
        result.fromBranchId == input.fromBranchId &&
        result.toBranchId == input.toBranchId &&
        result.productId == input.productId &&
        result.quantity == input.quantity &&
        result.sourceMovement.businessId == input.businessId &&
        result.sourceMovement.branchId == input.fromBranchId &&
        result.sourceMovement.productId == input.productId &&
        result.sourceMovement.sourceId == input.transferId &&
        result.destinationMovement.branchId == input.toBranchId &&
        result.destinationMovement.businessId == input.businessId &&
        result.destinationMovement.productId == input.productId &&
        result.destinationMovement.sourceId == input.transferId &&
        result.sourceMovement.quantityChange == -input.quantity &&
        result.destinationMovement.quantityChange == input.quantity &&
        result.sourceBalance.businessId == input.businessId &&
        result.sourceBalance.branchId == input.fromBranchId &&
        result.sourceBalance.productId == input.productId &&
        result.destinationBalance.businessId == input.businessId &&
        result.destinationBalance.branchId == input.toBranchId &&
        result.destinationBalance.productId == input.productId;
    if (!matches) {
      throw const InventoryTransferException(
        kind: InventoryTransferFailureKind.malformedResponse,
        message:
            'El servidor devolvió una transferencia que no coincide con la solicitud.',
      );
    }
  }
}
