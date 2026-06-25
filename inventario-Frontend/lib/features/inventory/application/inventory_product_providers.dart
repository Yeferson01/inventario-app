import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import 'inventory_product_creation_service.dart';

final inventoryProductCreationServiceProvider =
    Provider<InventoryProductCreationService>((ref) {
  final database = ref.watch(appDatabaseProvider);

  return InventoryProductCreationService(database);
});
