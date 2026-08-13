import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../inventory/application/inventory_product_providers.dart';
import 'app_e2e_local_flow_provider.dart';
import 'app_e2e_product_from_catalog_flow_service.dart';

final appE2EProductFromCatalogFlowServiceProvider =
    Provider<AppE2EProductFromCatalogFlowService>((ref) {
  return AppE2EProductFromCatalogFlowService(
    db: ref.watch(appDatabaseProvider),
    localFlowService: ref.watch(appE2ELocalFlowServiceProvider),
    productFromMasterSyncService:
        ref.watch(inventoryProductFromMasterSyncServiceProvider),
  );
});
