import '../../../core/utils/app_uuid.dart';
import '../data/models/product_stock_balance_models.dart';

enum InventoryTransferFailureKind {
  invalidQuantity,
  insufficientStock,
  sameBranch,
  invalidDestination,
  permissionDenied,
  idempotencyConflict,
  network,
  malformedResponse,
  unknown,
}

class InventoryTransferException implements Exception {
  const InventoryTransferException({
    required this.kind,
    required this.message,
  });

  final InventoryTransferFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

class InventoryTransferOperationIdentity {
  InventoryTransferOperationIdentity._({
    required this.transferId,
    required this.transferItemId,
    required this.idempotencyKey,
  });

  factory InventoryTransferOperationIdentity.create() {
    final transferId = AppUuid.v7();
    return InventoryTransferOperationIdentity._(
      transferId: transferId,
      transferItemId: AppUuid.v7(),
      idempotencyKey: 'inventory-transfer:$transferId',
    );
  }

  final String transferId;
  final String transferItemId;
  final String idempotencyKey;
}

class CreateInventoryTransferInput {
  const CreateInventoryTransferInput({
    required this.businessId,
    required this.fromBranchId,
    required this.toBranchId,
    required this.productId,
    required this.quantity,
    required this.transferId,
    required this.transferItemId,
    required this.idempotencyKey,
    this.notes,
  });

  final String businessId;
  final String fromBranchId;
  final String toBranchId;
  final String productId;
  final int quantity;
  final String transferId;
  final String transferItemId;
  final String idempotencyKey;
  final String? notes;

  String get fingerprint => [
        businessId,
        fromBranchId,
        toBranchId,
        productId,
        quantity,
        transferId,
        transferItemId,
      ].join('|');

  Map<String, Object?> toRpcParams() => {
        'p_business_id': businessId,
        'p_from_branch_id': fromBranchId,
        'p_to_branch_id': toBranchId,
        'p_product_id': productId,
        'p_quantity': quantity,
        'p_transfer_id': transferId,
        'p_transfer_item_id': transferItemId,
        'p_idempotency_key': idempotencyKey,
        'p_notes': notes,
      };
}

class InventoryTransferMovementProjection {
  const InventoryTransferMovementProjection({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.productId,
    required this.quantityChange,
    required this.unitCost,
    required this.sourceId,
    required this.idempotencyKey,
    required this.occurredAt,
    required this.metadata,
  });

  factory InventoryTransferMovementProjection.fromJson(Object? value) {
    final json = _map(value, 'inventory movement');
    final sourceType = _requiredString(json, 'source_type');
    if (sourceType != 'transfer') {
      throw const InventoryTransferException(
        kind: InventoryTransferFailureKind.malformedResponse,
        message: 'El servidor devolvió un movimiento que no es transferencia.',
      );
    }
    return InventoryTransferMovementProjection(
      id: _requiredString(json, 'id'),
      businessId: _requiredString(json, 'business_id'),
      branchId: _requiredString(json, 'branch_id'),
      productId: _requiredString(json, 'product_id'),
      quantityChange: _requiredInt(json, 'quantity_change'),
      unitCost: _optionalDouble(json['unit_cost']),
      sourceId: _requiredString(json, 'source_id'),
      idempotencyKey: _requiredString(json, 'idempotency_key'),
      occurredAt: _requiredDate(json, 'occurred_at'),
      metadata: _nullableMap(json['metadata']),
    );
  }

  final String id;
  final String businessId;
  final String branchId;
  final String productId;
  final int quantityChange;
  final double? unitCost;
  final String sourceId;
  final String idempotencyKey;
  final DateTime occurredAt;
  final Map<String, dynamic> metadata;
}

class InventoryTransferResult {
  const InventoryTransferResult({
    required this.transferId,
    required this.transferItemId,
    required this.businessId,
    required this.fromBranchId,
    required this.toBranchId,
    required this.productId,
    required this.quantity,
    required this.unitCostSnapshot,
    required this.idempotentReplay,
    required this.sourceMovement,
    required this.destinationMovement,
    required this.sourceBalance,
    required this.destinationBalance,
  });

  factory InventoryTransferResult.fromRpc(Object? value) {
    final json = _map(value, 'inventory transfer result');
    if (_requiredString(json, 'status') != 'completed') {
      throw const InventoryTransferException(
        kind: InventoryTransferFailureKind.malformedResponse,
        message: 'El servidor no confirmó la transferencia como completada.',
      );
    }
    return InventoryTransferResult(
      transferId: _requiredString(json, 'transfer_id'),
      transferItemId: _requiredString(json, 'transfer_item_id'),
      businessId: _requiredString(json, 'business_id'),
      fromBranchId: _requiredString(json, 'from_branch_id'),
      toBranchId: _requiredString(json, 'to_branch_id'),
      productId: _requiredString(json, 'product_id'),
      quantity: _requiredInt(json, 'quantity'),
      unitCostSnapshot: _optionalDouble(json['unit_cost_snapshot']),
      idempotentReplay: json['idempotent_replay'] == true,
      sourceMovement:
          InventoryTransferMovementProjection.fromJson(json['source_movement']),
      destinationMovement: InventoryTransferMovementProjection.fromJson(
        json['destination_movement'],
      ),
      sourceBalance: RemoteProductStockBalance.fromJson(
        _map(json['source_balance'], 'source balance'),
      ),
      destinationBalance: RemoteProductStockBalance.fromJson(
        _map(json['destination_balance'], 'destination balance'),
      ),
    );
  }

  final String transferId;
  final String transferItemId;
  final String businessId;
  final String fromBranchId;
  final String toBranchId;
  final String productId;
  final int quantity;
  final double? unitCostSnapshot;
  final bool idempotentReplay;
  final InventoryTransferMovementProjection sourceMovement;
  final InventoryTransferMovementProjection destinationMovement;
  final RemoteProductStockBalance sourceBalance;
  final RemoteProductStockBalance destinationBalance;
}

Map<String, dynamic> _map(Object? value, String field) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  throw InventoryTransferException(
    kind: InventoryTransferFailureKind.malformedResponse,
    message: 'Respuesta inválida para $field.',
  );
}

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim();
  if (value == null || value.isEmpty) {
    throw InventoryTransferException(
      kind: InventoryTransferFailureKind.malformedResponse,
      message: 'La respuesta de transferencia no contiene $key.',
    );
  }
  return value;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is num && value == value.roundToDouble()) return value.toInt();
  final parsed = int.tryParse(value?.toString() ?? '');
  if (parsed != null) return parsed;
  throw InventoryTransferException(
    kind: InventoryTransferFailureKind.malformedResponse,
    message: 'La respuesta de transferencia contiene $key inválido.',
  );
}

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime _requiredDate(Map<String, dynamic> json, String key) {
  final value = DateTime.tryParse(json[key]?.toString() ?? '')?.toUtc();
  if (value == null) {
    throw InventoryTransferException(
      kind: InventoryTransferFailureKind.malformedResponse,
      message: 'La respuesta de transferencia contiene $key inválido.',
    );
  }
  return value;
}

Map<String, dynamic> _nullableMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}
