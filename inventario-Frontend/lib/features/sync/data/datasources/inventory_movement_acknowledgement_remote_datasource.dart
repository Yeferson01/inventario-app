import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/inventory_movement_acknowledgement_models.dart';
import '../models/operational_bootstrap_models.dart';

typedef InventoryMovementAcknowledgementRpcInvoker = Future<Object?> Function(
  Map<String, Object?> parameters,
);

class InventoryMovementAcknowledgementRemoteDataSource {
  InventoryMovementAcknowledgementRemoteDataSource(SupabaseClient client)
      : this.withInvoker(
          (parameters) => client.rpc(
            'lookup_inventory_movement_acknowledgements',
            params: parameters,
          ),
        );

  InventoryMovementAcknowledgementRemoteDataSource.withInvoker(this._invoke);

  static const maxOperationsPerRequest = 200;

  final InventoryMovementAcknowledgementRpcInvoker _invoke;

  Future<Map<String, InventoryMovementAcknowledgement>> lookup({
    required String businessId,
    required String branchId,
    required String appDeviceId,
    required List<InventoryMovementAcknowledgementOperation> operations,
  }) async {
    final requestedIds = operations.map((item) => item.movementId).toSet();
    if (requestedIds.length != operations.length) {
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.malformedResponse,
        message: 'Acknowledgement operations contain duplicate movement IDs.',
      );
    }

    final results = <String, InventoryMovementAcknowledgement>{};
    for (var offset = 0; offset < operations.length; offset += 200) {
      final end = (offset + maxOperationsPerRequest < operations.length)
          ? offset + maxOperationsPerRequest
          : operations.length;
      final chunk = operations.sublist(offset, end);
      final batch = await _lookupChunk(
        businessId: businessId,
        branchId: branchId,
        appDeviceId: appDeviceId,
        operations: chunk,
      );
      final chunkIds = chunk.map((item) => item.movementId).toSet();
      for (final acknowledgement in batch.acknowledgements) {
        if (!chunkIds.contains(acknowledgement.movementId) ||
            results.containsKey(acknowledgement.movementId)) {
          throw const OperationalBootstrapException(
            kind: OperationalBootstrapFailureKind.scopeMismatch,
            message:
                'Acknowledgement response contains an unexpected movement.',
          );
        }
        results[acknowledgement.movementId] = acknowledgement;
      }
      if (batch.acknowledgements.length != chunk.length ||
          !chunkIds.every(results.containsKey)) {
        throw const OperationalBootstrapException(
          kind: OperationalBootstrapFailureKind.malformedResponse,
          message: 'Acknowledgement response omitted requested movements.',
        );
      }
    }
    return Map.unmodifiable(results);
  }

  Future<InventoryMovementAcknowledgementBatch> _lookupChunk({
    required String businessId,
    required String branchId,
    required String appDeviceId,
    required List<InventoryMovementAcknowledgementOperation> operations,
  }) async {
    try {
      final raw = await _invoke({
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_app_device_id': appDeviceId,
        'p_operations': operations.map((item) => item.toJson()).toList(),
      });
      final response = InventoryMovementAcknowledgementBatch.fromRpc(raw);
      if (response.businessId != businessId ||
          response.branchId != branchId ||
          response.appDeviceId != appDeviceId) {
        throw const OperationalBootstrapException(
          kind: OperationalBootstrapFailureKind.scopeMismatch,
          message: 'Acknowledgement response scope does not match the request.',
        );
      }
      return response;
    } on OperationalBootstrapException {
      rethrow;
    } on TimeoutException catch (error) {
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.networkTransient,
        message: 'Inventory acknowledgement request timed out.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.networkTransient,
        message: 'Inventory acknowledgement network request failed.',
        cause: error,
      );
    } on PostgrestException catch (error) {
      final diagnostic =
          '${error.message} ${error.details} ${error.hint}'.toLowerCase();
      final forbidden = error.code == '42501' ||
          diagnostic.contains('membership') ||
          diagnostic.contains('permission') ||
          diagnostic.contains('app_device') ||
          diagnostic.contains('branch');
      throw OperationalBootstrapException(
        kind: forbidden
            ? OperationalBootstrapFailureKind.forbidden
            : OperationalBootstrapFailureKind.remoteFailure,
        message: forbidden
            ? 'Inventory acknowledgement context is not authorized.'
            : 'Inventory acknowledgement RPC returned an error.',
        cause: error,
      );
    } catch (error) {
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.remoteFailure,
        message: 'Inventory acknowledgement RPC failed.',
        cause: error,
      );
    }
  }
}
