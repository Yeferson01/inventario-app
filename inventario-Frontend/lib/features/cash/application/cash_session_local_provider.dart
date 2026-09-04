import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_provider.dart';
import '../../../core/supabase/supabase_client_provider.dart';
import '../../sync/application/local_sync_outbox_providers.dart';
import '../../sync/data/models/runtime_setup_models.dart';
import '../data/datasources/cash_session_local_dao.dart';
import '../data/datasources/cash_session_remote_datasource.dart';
import '../data/models/cash_session_remote_models.dart';
import 'cash_session_local_service.dart';
import 'cash_sync_outbox_service.dart';

final cashSessionLocalDaoProvider = Provider<CashSessionLocalDao>((ref) {
  final db = ref.watch(appDatabaseProvider);

  return CashSessionLocalDao(db);
});

final cashSessionLocalServiceProvider =
    Provider<CashSessionLocalService>((ref) {
  final runtimeStore = ref.watch(appRuntimeContextStoreProvider);
  return CashSessionLocalService(
    dao: ref.watch(cashSessionLocalDaoProvider),
    remoteDataSource: CashSessionRemoteDataSource(
      ref.watch(supabaseClientProvider),
    ),
    runtimeProjector: (input, session) async {
      final installationId = input.deviceInstallationId?.trim();
      final appDeviceId = input.appDeviceId?.trim();
      if (installationId == null ||
          installationId.isEmpty ||
          appDeviceId == null ||
          appDeviceId.isEmpty) {
        return;
      }
      final current = await runtimeStore.getContext(
        businessId: input.businessId,
        branchId: input.branchId,
        installationId: installationId,
      );
      if (current == null ||
          current.profileId != input.profileId ||
          current.appDeviceId != appDeviceId ||
          current.cashRegisterId != input.cashRegisterId) {
        throw const CashRemoteStateUnavailableException(
          'La sesión abrió remotamente, pero el runtime local no coincide con el contexto.',
        );
      }
      await runtimeStore.saveContext(
        AppRuntimeContext(
          businessId: current.businessId,
          branchId: current.branchId,
          profileId: current.profileId,
          installationId: current.installationId,
          appDeviceId: current.appDeviceId,
          cashRegisterId: current.cashRegisterId,
          cashSessionId: session.id,
          receiptSequenceId: current.receiptSequenceId,
        ),
      );
    },
    runtimeCloseProjector: (input, result) async {
      final installationId = input.deviceInstallationId?.trim();
      final appDeviceId = input.appDeviceId?.trim();
      if (installationId == null ||
          installationId.isEmpty ||
          appDeviceId == null ||
          appDeviceId.isEmpty) {
        return;
      }
      final current = await runtimeStore.getContext(
        businessId: input.businessId,
        branchId: input.branchId,
        installationId: installationId,
      );
      if (current == null ||
          current.profileId != input.profileId ||
          current.appDeviceId != appDeviceId ||
          current.cashRegisterId != result.cashRegisterId ||
          current.cashSessionId != result.cashSessionId) {
        throw const CashRemoteStateUnavailableException(
          'La sesión cerró remotamente, pero el runtime local no coincide con el contexto.',
        );
      }
      await runtimeStore.saveContext(
        AppRuntimeContext(
          businessId: current.businessId,
          branchId: current.branchId,
          profileId: current.profileId,
          installationId: current.installationId,
          appDeviceId: current.appDeviceId,
          cashRegisterId: current.cashRegisterId,
          cashSessionId: null,
          receiptSequenceId: current.receiptSequenceId,
        ),
      );
    },
  );
});

final cashSyncOutboxServiceProvider = Provider<CashSyncOutboxService>((ref) {
  return CashSyncOutboxService(
    dao: ref.watch(cashSessionLocalDaoProvider),
    outboxService: ref.watch(localSyncOutboxServiceProvider),
  );
});
