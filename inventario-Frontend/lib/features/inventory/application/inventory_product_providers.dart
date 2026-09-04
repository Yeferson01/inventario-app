import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../catalog/application/catalog_local_providers.dart';
import '../../sync/application/local_sync_outbox_providers.dart';
import 'business_product_creation_service.dart';
import 'business_product_creation_models.dart';
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
  final database = ref.watch(appDatabaseProvider);

  return InventoryProductFromMasterSyncService(
    database: database,
    productCreationService: productCreationService,
    outboxService: outboxService,
  );
});

final businessProductCreationServiceProvider =
    Provider<BusinessProductCreationService>((ref) {
  return BusinessProductCreationService(
    barcodeLookupService: ref.watch(catalogBarcodeLookupServiceProvider),
    productSyncService:
        ref.watch(inventoryProductFromMasterSyncServiceProvider),
  );
});

final businessProductMinimumStockUpdaterProvider = Provider<
    Future<BusinessProductMinimumStockUpdateResult> Function(
      BusinessProductMinimumStockUpdateInput input,
    )>((ref) {
  final service = ref.watch(businessProductCreationServiceProvider);
  return service.updateMinimumStock;
});
