import 'dart:convert';

enum InventoryMovementTransportState {
  pending,
  terminalApplied,
  terminalIncompatible,
}

class LocalInventoryMovementForReconciliation {
  const LocalInventoryMovementForReconciliation({
    required this.id,
    required this.businessId,
    required this.branchId,
    required this.productId,
    required this.sourceType,
    required this.sourceId,
    required this.sourceItemId,
    required this.idempotencyKey,
    required this.quantityChange,
    required this.unitCost,
    required this.occurredAt,
    required this.clientSequence,
    required this.transportState,
    required this.transportEvidence,
  });

  final String id;
  final String businessId;
  final String branchId;
  final String productId;
  final String sourceType;
  final String? sourceId;
  final String? sourceItemId;
  final String idempotencyKey;
  final int quantityChange;
  final double? unitCost;
  final DateTime occurredAt;
  final int? clientSequence;
  final InventoryMovementTransportState transportState;
  final List<String> transportEvidence;

  bool get requiresSourceItemId =>
      sourceType == 'sale' || sourceType == 'purchase';

  bool get canRequestAcknowledgement =>
      const {'sale', 'purchase', 'manual_adjustment'}.contains(sourceType) &&
      quantityChange != 0 &&
      (!requiresSourceItemId || (sourceId != null && sourceItemId != null));

  InventoryMovementAcknowledgementOperation get acknowledgementOperation {
    if (!canRequestAcknowledgement) {
      throw StateError('Movement $id cannot be acknowledged safely.');
    }
    return InventoryMovementAcknowledgementOperation(
      movementId: id,
      idempotencyKey: idempotencyKey,
      sourceType: sourceType,
      sourceId: sourceId,
      sourceItemId: sourceItemId,
      productId: productId,
      quantityChange: quantityChange,
    );
  }

  String get fingerprint => jsonEncode({
        'id': id,
        'business_id': businessId,
        'branch_id': branchId,
        'product_id': productId,
        'source_type': sourceType,
        'source_id': sourceId,
        'source_item_id': sourceItemId,
        'idempotency_key': idempotencyKey,
        'quantity_change': quantityChange,
        'unit_cost': unitCost,
        'occurred_at': occurredAt.toIso8601String(),
        'client_sequence': clientSequence,
        'transport_state': transportState.name,
        'transport_evidence': transportEvidence,
      });
}

class InventoryMovementAcknowledgementOperation {
  const InventoryMovementAcknowledgementOperation({
    required this.movementId,
    required this.idempotencyKey,
    required this.sourceType,
    required this.sourceId,
    required this.sourceItemId,
    required this.productId,
    required this.quantityChange,
  });

  final String movementId;
  final String idempotencyKey;
  final String sourceType;
  final String? sourceId;
  final String? sourceItemId;
  final String productId;
  final int quantityChange;

  Map<String, Object?> toJson() => {
        'movement_id': movementId,
        'idempotency_key': idempotencyKey,
        'source_type': sourceType,
        'source_id': sourceId,
        'source_item_id': sourceItemId,
        'product_id': productId,
        'quantity_change': quantityChange,
      };
}

enum InventoryMovementAcknowledgementStatus {
  applied,
  notFound,
  rejected,
  ambiguous;

  static InventoryMovementAcknowledgementStatus fromJson(Object? value) {
    return switch (value) {
      'applied' => InventoryMovementAcknowledgementStatus.applied,
      'not_found' => InventoryMovementAcknowledgementStatus.notFound,
      'rejected' => InventoryMovementAcknowledgementStatus.rejected,
      'ambiguous' => InventoryMovementAcknowledgementStatus.ambiguous,
      _ => throw FormatException('Unsupported acknowledgement status: $value'),
    };
  }
}

class InventoryMovementAcknowledgement {
  const InventoryMovementAcknowledgement({
    required this.movementId,
    required this.status,
    required this.remoteMovementId,
    required this.remoteIdempotencyKey,
    required this.remoteEvidenceStatus,
    required this.checkedAt,
  });

  factory InventoryMovementAcknowledgement.fromJson(Object? value) {
    final json = _map(value, 'acknowledgement');
    return InventoryMovementAcknowledgement(
      movementId: _requiredString(json, 'movement_id'),
      status: InventoryMovementAcknowledgementStatus.fromJson(json['status']),
      remoteMovementId: _optionalString(json['remote_movement_id']),
      remoteIdempotencyKey: _optionalString(json['remote_idempotency_key']),
      remoteEvidenceStatus: _optionalString(json['remote_evidence_status']),
      checkedAt: _requiredDate(json, 'checked_at'),
    );
  }

  final String movementId;
  final InventoryMovementAcknowledgementStatus status;
  final String? remoteMovementId;
  final String? remoteIdempotencyKey;
  final String? remoteEvidenceStatus;
  final DateTime checkedAt;
}

class InventoryMovementAcknowledgementBatch {
  const InventoryMovementAcknowledgementBatch({
    required this.businessId,
    required this.branchId,
    required this.appDeviceId,
    required this.authorizationValidatedAt,
    required this.checkedAt,
    required this.acknowledgements,
  });

  factory InventoryMovementAcknowledgementBatch.fromRpc(Object? value) {
    final json = _map(value, 'acknowledgement response');
    final rawAcknowledgements = json['acknowledgements'];
    if (rawAcknowledgements is! List) {
      throw const FormatException('acknowledgements must be an array.');
    }
    return InventoryMovementAcknowledgementBatch(
      businessId: _requiredString(json, 'business_id'),
      branchId: _requiredString(json, 'branch_id'),
      appDeviceId: _requiredString(json, 'app_device_id'),
      authorizationValidatedAt:
          _requiredDate(json, 'authorization_validated_at'),
      checkedAt: _requiredDate(json, 'checked_at'),
      acknowledgements: rawAcknowledgements
          .map(InventoryMovementAcknowledgement.fromJson)
          .toList(growable: false),
    );
  }

  final String businessId;
  final String branchId;
  final String appDeviceId;
  final DateTime authorizationValidatedAt;
  final DateTime checkedAt;
  final List<InventoryMovementAcknowledgement> acknowledgements;
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is! Map) {
    throw FormatException('$field must be an object.');
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = _optionalString(json[key]);
  if (value == null) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value;
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! String || value.trim().isEmpty) {
    throw const FormatException('Expected a non-empty string or null.');
  }
  return value.trim();
}

DateTime _requiredDate(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('$key must be an ISO-8601 string.');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw FormatException('$key must be an ISO-8601 string.');
  }
  return parsed.toUtc();
}
