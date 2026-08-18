import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/sync/application/app_context_service.dart';
import 'package:inventario_frontend/features/sync/application/app_runtime_context_store.dart';
import 'package:inventario_frontend/features/sync/application/app_selected_sync_context_store.dart';
import 'package:inventario_frontend/features/sync/application/core_context_snapshot_applier.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_download_models.dart';
import 'package:inventario_frontend/features/sync/application/operational_bootstrap_download_service.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/core_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_checkpoint_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_remote_datasource.dart';
import 'package:inventario_frontend/features/sync/data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/datasources/reconciliation_issue_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/core_context_snapshot_models.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';
import 'package:inventario_frontend/features/sync/data/models/operational_bootstrap_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/operational_bootstrap_test_data.dart';

void main() {
  late AppDatabase database;
  late AuthorizedOperationalContextLocalDao authorizationDao;
  late CoreContextSnapshotApplier applier;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    database = AppDatabase.executor(NativeDatabase.memory());
    authorizationDao = AuthorizedOperationalContextLocalDao(database);
    applier = CoreContextSnapshotApplier(
      coreContextLocalDao: CoreContextLocalDao(database),
      authorizationDao: authorizationDao,
    );
  });

  tearDown(() => database.close());

  test('maps the real core row and rejects a non-core dataset', () async {
    final snapshot = _coreSnapshot();
    final context = CoreContextSnapshot.fromBootstrapRow(
      snapshot.datasets['context']!.rows.single,
    );

    expect(context.profileId, 'profile-a');
    expect(context.business.id, 'business-a');
    expect(context.branch.id, 'branch-x');
    expect(context.applicableMembershipIds,
        ['membership-business', 'membership-branch']);
    expect(context.effectiveRoles.map((role) => role.name),
        ['cashier', 'inventory_operator']);
    expect(context.authorizationValidatedAt,
        DateTime.parse('2026-08-15T10:00:00Z'));

    final productSnapshot = OperationalBootstrapSnapshotPage.fromRpc(
      bootstrapRpcResponse(),
    );
    await expectLater(
      applier.applyPage(
        profileId: 'profile-a',
        snapshot: productSnapshot,
        page: productSnapshot.datasets['products']!,
      ),
      throwsA(_kind(OperationalBootstrapFailureKind.malformedResponse)),
    );
  });

  test('applies business, branch and effective projection without outbox',
      () async {
    final snapshot = _coreSnapshot();

    await _apply(applier, snapshot);

    final businesses = await database.select(database.businesses).get();
    final branches = await database.select(database.branches).get();
    final projection = await authorizationDao.getContextRecord(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    expect(businesses.single.syncStatus, SyncStatus.synced);
    expect(branches.single.syncStatus, 0);
    expect(projection?.snapshotId, 'core-snapshot-1');
    expect(projection?.isActive, isTrue);
    expect(projection?.effectivePermissions,
        ['inventory.read', 'products.read', 'sales.create']);
    expect(projection?.effectiveRoles, ['cashier', 'inventory_operator']);
    expect(await database.select(database.profiles).get(), isEmpty);
    expect(await database.select(database.businessMembers).get(), isEmpty);
    expect(await database.select(database.roles).get(), isEmpty);
    expect(await database.select(database.rolePermissions).get(), isEmpty);
    expect(await database.select(database.localSyncBatches).get(), isEmpty);
    expect(await database.select(database.localSyncMutations).get(), isEmpty);
  });

  test('replaces permissions and uses the complete multi-membership union',
      () async {
    await _apply(applier, _coreSnapshot());
    await _apply(
      applier,
      _coreSnapshot(
        snapshotId: 'core-snapshot-2',
        permissions: const ['sales.create'],
        authorizationValidatedAt: '2026-08-15T11:00:00Z',
      ),
    );

    final service = _contextService(database, authorizationDao);
    await service.selectBusinessContext(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    final context = await service.loadCurrentContext(
      profileId: 'profile-a',
      installationId: 'installation-1',
      isOnline: false,
    );

    expect(context?.hasPermission('sales.create'), isTrue);
    expect(context?.hasPermission('inventory.read'), isFalse);
    expect(context?.effectiveRoles, ['cashier', 'inventory_operator']);
    expect(context?.applicableMembershipIds,
        ['membership-business', 'membership-branch']);
    expect(context?.authorizationContextReady, isTrue);
    expect(context?.authorizationValidatedAt,
        DateTime.parse('2026-08-15T11:00:00Z'));
  });

  test('isolates projections and selections by profile and branch', () async {
    await _apply(
      applier,
      _coreSnapshot(permissions: const ['sales.create']),
    );
    await _apply(
      applier,
      _coreSnapshot(
        profileId: 'profile-b',
        snapshotId: 'core-profile-b',
        permissions: const ['inventory.read'],
      ),
      profileId: 'profile-b',
    );
    await _apply(
      applier,
      _coreSnapshot(
        branchId: 'branch-y',
        snapshotId: 'core-branch-y',
        permissions: const ['inventory.adjust'],
      ),
    );

    final service = _contextService(database, authorizationDao);
    await service.selectBusinessContext(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    await service.selectBusinessContext(
      profileId: 'profile-b',
      businessId: 'business-a',
      branchId: 'branch-x',
    );

    final profileA = await service.loadCurrentContext(
      profileId: 'profile-a',
      installationId: 'installation-1',
      isOnline: false,
    );
    final profileB = await service.loadCurrentContext(
      profileId: 'profile-b',
      installationId: 'installation-1',
      isOnline: false,
    );
    expect(profileA?.permissions.sorted(), ['sales.create']);
    expect(profileB?.permissions.sorted(), ['inventory.read']);

    await service.selectBusinessContext(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-y',
    );
    final branchY = await service.loadCurrentContext(
      profileId: 'profile-a',
      installationId: 'installation-1',
      isOnline: false,
    );
    expect(branchY?.permissions.sorted(), ['inventory.adjust']);
  });

  test('revoked projection denies permissions without legacy fallback',
      () async {
    await _apply(applier, _coreSnapshot(permissions: const ['sales.create']));
    await authorizationDao.invalidateContext(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    final service = _contextService(database, authorizationDao);
    await service.selectBusinessContext(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
    );

    final context = await service.loadCurrentContext(
      profileId: 'profile-a',
      installationId: 'installation-1',
      isOnline: false,
    );

    expect(context?.permissions.sorted(), isEmpty);
    expect(context?.authorizationContextReady, isFalse);
    expect(
      (await authorizationDao.getContextRecord(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-x',
      ))
          ?.status,
      'revoked',
    );
  });

  test('forbidden core response invalidates while transient preserves',
      () async {
    await authorizationDao.replaceContext(_projection('old-snapshot'));
    var forbiddenCalls = 0;
    final forbiddenService = _downloadService(
      database,
      authorizationDao,
      (_) async {
        forbiddenCalls += 1;
        if (forbiddenCalls == 1) {
          return bootstrapCoreRpcResponse(
            snapshotId: 'continuing-snapshot',
            permissions: const ['inventory.read'],
            hasMore: true,
            nextPageToken: 'core-page-2',
          );
        }
        throw const OperationalBootstrapException(
          kind: OperationalBootstrapFailureKind.forbidden,
          message: 'revoked',
        );
      },
    );

    await expectLater(
      forbiddenService.download(_coreRequest),
      throwsA(_kind(OperationalBootstrapFailureKind.forbidden)),
    );
    expect(
      (await authorizationDao.getContextRecord(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-x',
      ))
          ?.status,
      'revoked',
    );

    await authorizationDao.replaceContext(_projection('restored-snapshot'));
    final transientService = _downloadService(
      database,
      authorizationDao,
      (_) async => throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.networkTransient,
        message: 'offline',
      ),
      maxTransientRetries: 0,
    );
    await expectLater(
      transientService.download(_coreRequest),
      throwsA(_kind(OperationalBootstrapFailureKind.networkTransient)),
    );
    expect(
      (await authorizationDao.getContextRecord(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-x',
      ))
          ?.status,
      'active',
    );
  });

  test('projection and checkpoint commit atomically', () async {
    await authorizationDao.replaceContext(_projection('old-snapshot'));
    final response = bootstrapCoreRpcResponse(
      permissions: const ['inventory.read'],
    );
    final failingService = _downloadService(
      database,
      authorizationDao,
      (_) async => response,
      checkpointDao: _FailingCheckpointDao(database),
    );

    await expectLater(failingService.download(_coreRequest), throwsA(anything));
    var projection = await authorizationDao.getContextRecord(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    expect(projection?.snapshotId, 'old-snapshot');
    expect(projection?.effectivePermissions, ['sales.create']);

    final successService = _downloadService(
      database,
      authorizationDao,
      (_) async => response,
    );
    final result = await successService.download(_coreRequest);
    projection = await authorizationDao.getContextRecord(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-x',
    );
    expect(result.completed, isTrue);
    expect(projection?.snapshotId, 'core-snapshot-1');
    expect(projection?.effectivePermissions, ['inventory.read']);
    expect(await database.select(database.localSyncBatches).get(), isEmpty);
    expect(await database.select(database.localSyncMutations).get(), isEmpty);
  });
}

const _coreRequest = OperationalBootstrapDownloadRequest(
  profileId: 'profile-a',
  businessId: 'business-a',
  branchId: 'branch-x',
  appDeviceId: 'device-a',
  bundle: 'core',
  limit: 1000,
);

OperationalBootstrapSnapshotPage _coreSnapshot({
  String snapshotId = 'core-snapshot-1',
  String profileId = 'profile-a',
  String branchId = 'branch-x',
  List<String> permissions = const [
    'inventory.read',
    'products.read',
    'sales.create',
  ],
  String authorizationValidatedAt = '2026-08-15T10:00:00Z',
}) {
  return OperationalBootstrapSnapshotPage.fromRpc(
    bootstrapCoreRpcResponse(
      snapshotId: snapshotId,
      profileId: profileId,
      branchId: branchId,
      permissions: permissions,
      authorizationValidatedAt: authorizationValidatedAt,
    ),
  );
}

Future<void> _apply(
  CoreContextSnapshotApplier applier,
  OperationalBootstrapSnapshotPage snapshot, {
  String profileId = 'profile-a',
}) {
  return applier
      .applyPage(
        profileId: profileId,
        snapshot: snapshot,
        page: snapshot.datasets['context']!,
      )
      .then((_) {});
}

AppContextService _contextService(
  AppDatabase database,
  AuthorizedOperationalContextLocalDao authorizationDao,
) {
  return AppContextService(
    database: database,
    selectedContextStore: AppSelectedSyncContextStore(),
    runtimeContextStore: AppRuntimeContextStore(),
    authorizationContextDao: authorizationDao,
  );
}

AuthorizedOperationalContextProjection _projection(String snapshotId) {
  return AuthorizedOperationalContextProjection(
    profileId: 'profile-a',
    businessId: 'business-a',
    branchId: 'branch-x',
    effectivePermissions: const ['sales.create'],
    effectiveRoles: const ['cashier'],
    applicableMembershipIds: const ['membership-1'],
    authorizationValidatedAt: DateTime.utc(2026, 8, 15, 10),
    snapshotId: snapshotId,
  );
}

OperationalBootstrapDownloadService _downloadService(
  AppDatabase database,
  AuthorizedOperationalContextLocalDao authorizationDao,
  Future<Object?> Function(Map<String, Object?>) invoke, {
  int maxTransientRetries = 0,
  OperationalBootstrapCheckpointLocalDao? checkpointDao,
}) {
  return OperationalBootstrapDownloadService(
    database: database,
    remoteDataSource: OperationalBootstrapRemoteDataSource.withInvoker(invoke),
    checkpointDao:
        checkpointDao ?? OperationalBootstrapCheckpointLocalDao(database),
    seenRecordDao: OperationalBootstrapSeenRecordLocalDao(database),
    reconciliationIssueDao: ReconciliationIssueLocalDao(database),
    pageApplier: CoreContextSnapshotApplier(
      coreContextLocalDao: CoreContextLocalDao(database),
      authorizationDao: authorizationDao,
    ),
    authorizationContextDao: authorizationDao,
    maxTransientRetries: maxTransientRetries,
    retryDelay: (_) async {},
  );
}

Matcher _kind(OperationalBootstrapFailureKind kind) {
  return isA<OperationalBootstrapException>()
      .having((error) => error.kind, 'kind', kind);
}

class _FailingCheckpointDao extends OperationalBootstrapCheckpointLocalDao {
  _FailingCheckpointDao(super.database);

  @override
  Future<void> commitPageProgress({
    required OperationalBootstrapScope scope,
    required String? nextPageToken,
    required int rowsReceived,
    DateTime? authorizationValidatedAt,
  }) {
    throw StateError('simulated checkpoint failure');
  }
}
