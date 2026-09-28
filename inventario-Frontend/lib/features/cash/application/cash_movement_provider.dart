import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../sync/application/local_sync_outbox_providers.dart';
import '../../sync/application/productive_sync_status_revision_provider.dart';
import 'cash_movement_models.dart';
import 'cash_movement_service.dart';

final cashMovementServiceProvider = Provider<CashMovementService>((ref) {
  final contextService = ref.watch(appContextServiceProvider);
  return CashMovementService(
    database: ref.watch(appDatabaseProvider),
    onCommitted: ref
        .read(productiveSyncStatusRevisionProvider.notifier)
        .markLocalStateChanged,
    loadCurrentContext: () async {
      final profileId = ref.read(currentSupabaseUserProvider)?.id;
      if (profileId == null) return null;
      final installationId = await ref.read(installationIdProvider.future);
      final context = await contextService.loadCurrentContext(
        installationId: installationId,
        profileId: profileId,
        isOnline: false,
      );
      if (ref.read(currentSupabaseUserProvider)?.id != profileId) return null;
      return context;
    },
  );
});

final cashMovementSubmitProvider =
    Provider<Future<CashMovementResult> Function(CashMovementRequest)>((ref) {
  return ref.watch(cashMovementServiceProvider).recordMovement;
});
