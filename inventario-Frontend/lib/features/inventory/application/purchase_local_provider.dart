import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../sync/application/local_sync_outbox_providers.dart';
import '../data/datasources/purchase_local_dao.dart';
import 'purchase_local_service.dart';
import 'purchase_sync_outbox_service.dart';

final purchaseLocalDaoProvider = Provider<PurchaseLocalDao>((ref) {
  final db = ref.watch(appDatabaseProvider);

  return PurchaseLocalDao(db);
});

final purchaseLocalServiceProvider = Provider<PurchaseLocalService>((ref) {
  return PurchaseLocalService(
    dao: ref.watch(purchaseLocalDaoProvider),
  );
});

final purchaseSyncOutboxServiceProvider =
    Provider<PurchaseSyncOutboxService>((ref) {
  return PurchaseSyncOutboxService(
    dao: ref.watch(purchaseLocalDaoProvider),
    outboxService: ref.watch(localSyncOutboxServiceProvider),
  );
});
