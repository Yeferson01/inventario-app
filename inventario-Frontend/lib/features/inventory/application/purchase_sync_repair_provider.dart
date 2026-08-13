import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import 'purchase_sync_repair_service.dart';

final purchaseSyncRepairServiceProvider =
    Provider<PurchaseSyncRepairService>((ref) {
  final database = ref.watch(appDatabaseProvider);

  return PurchaseSyncRepairService(database);
});
