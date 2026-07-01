import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../sync/application/local_sync_outbox_providers.dart';
import '../data/datasources/pos_local_sale_dao.dart';
import 'pos_local_sale_service.dart';
import 'pos_sync_outbox_service.dart';

final posLocalSaleDaoProvider = Provider<PosLocalSaleDao>((ref) {
  final db = ref.watch(appDatabaseProvider);

  return PosLocalSaleDao(db);
});

final posLocalSaleServiceProvider = Provider<PosLocalSaleService>((ref) {
  return PosLocalSaleService(
    dao: ref.watch(posLocalSaleDaoProvider),
  );
});

final posSyncOutboxServiceProvider = Provider<PosSyncOutboxService>((ref) {
  return PosSyncOutboxService(
    dao: ref.watch(posLocalSaleDaoProvider),
    outboxService: ref.watch(localSyncOutboxServiceProvider),
  );
});
