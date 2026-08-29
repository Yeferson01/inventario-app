import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../data/datasources/inventory_transfer_remote_datasource.dart';
import 'inventory_initial_stock_provider.dart';
import 'inventory_transfer_models.dart';
import 'inventory_transfer_service.dart';
import 'product_stock_balance_providers.dart';

final inventoryTransferRemoteDataSourceProvider =
    Provider<InventoryTransferRemoteDataSource>((ref) {
  return InventoryTransferRemoteDataSource(ref.watch(supabaseClientProvider));
});

final inventoryTransferServiceProvider = Provider<InventoryTransferService>(
  (ref) {
    final remoteDataSource = ref.watch(
      inventoryTransferRemoteDataSourceProvider,
    );
    return InventoryTransferService(
      database: ref.watch(appDatabaseProvider),
      executeRemote: (input) => _executeRemote(remoteDataSource, input),
      movementDao: ref.watch(inventoryMovementLocalDaoProvider),
      balanceDao: ref.watch(productStockBalanceLocalDaoProvider),
    );
  },
);

Future<InventoryTransferResult> _executeRemote(
  InventoryTransferRemoteDataSource dataSource,
  CreateInventoryTransferInput input,
) async {
  try {
    final response = await dataSource.createAndComplete(input.toRpcParams());
    return InventoryTransferResult.fromRpc(response);
  } on TimeoutException catch (_) {
    throw const InventoryTransferException(
      kind: InventoryTransferFailureKind.network,
      message:
          'No fue posible confirmar la transferencia por falta de conexión.',
    );
  } on SocketException catch (_) {
    throw const InventoryTransferException(
      kind: InventoryTransferFailureKind.network,
      message:
          'No fue posible confirmar la transferencia por falta de conexión.',
    );
  } on PostgrestException catch (error) {
    throw _mapPostgrest(error);
  }
}

InventoryTransferException _mapPostgrest(PostgrestException error) {
  final message = error.message.toLowerCase();
  if (message.contains('insufficient available stock')) {
    return const InventoryTransferException(
      kind: InventoryTransferFailureKind.insufficientStock,
      message: 'No hay stock disponible suficiente en la sucursal origen.',
    );
  }
  if (message.contains('must be greater than zero')) {
    return const InventoryTransferException(
      kind: InventoryTransferFailureKind.invalidQuantity,
      message: 'La cantidad debe ser mayor que cero.',
    );
  }
  if (message.contains('must be different')) {
    return const InventoryTransferException(
      kind: InventoryTransferFailureKind.sameBranch,
      message: 'La sucursal destino debe ser diferente de la sucursal origen.',
    );
  }
  if (message.contains('permission') ||
      message.contains('authentication required')) {
    return const InventoryTransferException(
      kind: InventoryTransferFailureKind.permissionDenied,
      message:
          'No tienes permiso para transferir inventario entre esas sucursales.',
    );
  }
  if (message.contains('destination branch') ||
      message.contains('destination stock balance') ||
      message.contains('origin branch') ||
      message.contains('requested business') ||
      message.contains('product is not active')) {
    return const InventoryTransferException(
      kind: InventoryTransferFailureKind.invalidDestination,
      message:
          'El producto o alguna sucursal ya no está disponible para la transferencia.',
    );
  }
  if (message.contains('idempotency_key') ||
      message.contains('idempotent transfer')) {
    return const InventoryTransferException(
      kind: InventoryTransferFailureKind.idempotencyConflict,
      message:
          'La transferencia no coincide con el intento anterior. Actualiza e inténtalo nuevamente.',
    );
  }
  return const InventoryTransferException(
    kind: InventoryTransferFailureKind.unknown,
    message: 'No fue posible completar la transferencia de inventario.',
  );
}
