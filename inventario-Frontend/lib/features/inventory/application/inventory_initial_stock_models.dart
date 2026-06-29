import '../../sync/data/models/local_sync_outbox_models.dart';

class CreateInitialStockInput {
  const CreateInitialStockInput({
    required this.businessId,
    required this.branchId,
    required this.productId,
    required this.quantity,
    required this.unitCost,
    required this.profileId,
    required this.appDeviceId,
    required this.deviceInstallationId,
    this.notes = 'E2E initial stock from Flutter offline sync',
    this.clientSequenceStart = 1,
  });

  final String businessId;
  final String branchId;
  final String productId;
  final int quantity;
  final double unitCost;
  final String profileId;
  final String appDeviceId;
  final String deviceInstallationId;
  final String notes;
  final int clientSequenceStart;
}

class InitialStockSyncResult {
  const InitialStockSyncResult({
    required this.movementId,
    required this.payload,
    required this.outboxResult,
  });

  final String movementId;
  final Map<String, dynamic> payload;
  final LocalSyncEnqueueResult outboxResult;

  Map<String, dynamic> toJson() {
    return {
      'movement_id': movementId,
      'payload': payload,
      'outbox_result': outboxResult.toJson(),
    };
  }
}
