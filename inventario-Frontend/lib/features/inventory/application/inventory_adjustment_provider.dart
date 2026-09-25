import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_provider.dart';
import '../../../core/providers/device_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../sync/application/local_sync_outbox_providers.dart';
import 'inventory_adjustment_service.dart';

final inventoryAdjustmentServiceProvider =
    Provider<InventoryAdjustmentService>((ref) {
  final contextService = ref.watch(appContextServiceProvider);
  return InventoryAdjustmentService(
      database: ref.watch(appDatabaseProvider),
      loadCurrentContext: () async {
        // Read the locally held auth identity; no network or connectivity check.
        final profileId = ref.read(currentSupabaseUserProvider)?.id;
        if (profileId == null) return null;
        final installationId = await ref.read(installationIdProvider.future);
        final context = await contextService.loadCurrentContext(
            installationId: installationId,
            profileId: profileId,
            isOnline: false);
        if (ref.read(currentSupabaseUserProvider)?.id != profileId) return null;
        return context;
      });
});
