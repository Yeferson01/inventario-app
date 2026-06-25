import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/database_provider.dart';
import '../data/datasources/local_sync_outbox_dao.dart';
import 'local_sync_outbox_service.dart';

final localSyncOutboxDaoProvider = Provider<LocalSyncOutboxDao>((ref) {
  final database = ref.watch(appDatabaseProvider);
  return LocalSyncOutboxDao(database);
});

final localSyncOutboxServiceProvider = Provider<LocalSyncOutboxService>((ref) {
  final dao = ref.watch(localSyncOutboxDaoProvider);
  return LocalSyncOutboxService(dao);
});
