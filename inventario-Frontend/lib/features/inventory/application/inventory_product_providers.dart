import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../sync/application/local_sync_outbox_providers.dart';
import 'inventory_product_creation_service.dart';
import 'inventory_product_from_master_sync_service.dart';

final inventoryProductCreationServiceProvider =
    Provider<InventoryProductCreationService>((ref) {
  final database = ref.watch(appDatabaseProvider);

  return InventoryProductCreationService(database);
});

final inventoryProductFromMasterSyncServiceProvider =
    Provider<InventoryProductFromMasterSyncService>((ref) {
  final productCreationService =
      ref.watch(inventoryProductCreationServiceProvider);
  final outboxService = ref.watch(localSyncOutboxServiceProvider);

  return InventoryProductFromMasterSyncService(
    productCreationService: productCreationService,
    outboxService: outboxService,
  );
});
