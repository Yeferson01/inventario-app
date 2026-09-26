import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_models.dart';
import 'package:inventario_frontend/features/cash/application/cash_movement_provider.dart';
import 'package:inventario_frontend/features/cash/application/cash_movement_service.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_provider.dart';
import 'package:inventario_frontend/features/cash/application/cash_session_local_service.dart';
import 'package:inventario_frontend/features/cash/application/cash_sync_outbox_service.dart';
import 'package:inventario_frontend/features/cash/data/datasources/cash_session_local_dao.dart';
import 'package:inventario_frontend/features/cash/data/datasources/cash_session_remote_datasource.dart';
import 'package:inventario_frontend/features/cash/presentation/screens/cash_dashboard_screen.dart';
import 'package:inventario_frontend/features/sales/application/pos_local_sale_provider.dart';
import 'package:inventario_frontend/features/sales/application/pos_sync_outbox_service.dart';
import 'package:inventario_frontend/features/sync/application/cash_sync_upload_provider.dart';
import 'package:inventario_frontend/features/sync/application/app_context_models.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';
import 'package:inventario_frontend/features/sync/application/app_router_sync_bootstrap_provider.dart';
import 'package:inventario_frontend/features/sync/application/app_sync_coordinator_models.dart';
import 'package:inventario_frontend/features/sync/application/cash_close_sync_trigger_service.dart';
import 'package:inventario_frontend/features/sync/application/cash_sync_upload_service.dart';
import 'package:inventario_frontend/features/sync/application/intentional_stale_sale_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/application/pos_sync_upload_provider.dart';
import 'package:inventario_frontend/features/sync/application/pos_sync_upload_service.dart';
import 'package:inventario_frontend/features/sync/application/productive_manual_sync_service.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status.dart';
import 'package:inventario_frontend/features/sync/application/productive_stale_sale_reconciliation_service.dart';
import 'package:inventario_frontend/features/sync/application/unmaterialized_local_sale_discard_service.dart';
import 'package:inventario_frontend/features/sync/data/models/catalog_upload_models.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_setup_models.dart';

void main() {
  late AppDatabase database;
  late CashSessionLocalService service;
  late CashCloseSyncTriggerService closeSyncService;

  setUp(() async {
    database = AppDatabase.executor(NativeDatabase.memory());
    await _seed(database);
    service = CashSessionLocalService(
      dao: CashSessionLocalDao(database),
      remoteDataSource: CashSessionRemoteDataSource.withInvoker(
        (functionName, parameters) async => _closedSnapshot,
      ),
    );
    closeSyncService = CashCloseSyncTriggerService(
      productiveSyncService: _successfulProductiveSyncService(),
      cashSessionService: service,
    );
  });

  tearDown(() => database.close());

  testWidgets('successful close completes after dialog controllers dispose',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cashSessionLocalServiceProvider.overrideWithValue(service),
          cashCloseSyncTriggerServiceProvider.overrideWithValue(
            closeSyncService,
          ),
          cashSyncOutboxServiceProvider.overrideWithValue(
            _FakeCashSyncOutboxService(),
          ),
          posSyncOutboxServiceProvider.overrideWithValue(
            _FakePosSyncOutboxService(),
          ),
          cashSyncUploadServiceProvider.overrideWithValue(
            _FakeCashSyncUploadService(),
          ),
          posSyncUploadServiceProvider.overrideWithValue(
            _FakePosSyncUploadService(),
          ),
          productiveStaleSaleReconciliationServiceProvider.overrideWithValue(
            _NoPendingStaleSalesController(),
          ),
        ],
        child: const MaterialApp(
          home: CashDashboardScreen(
            businessId: 'business-a',
            branchId: 'branch-a',
            profileId: 'profile-a',
            cashRegisterId: 'register-a',
            canReadCash: true,
            canOpenCash: true,
            canCloseCash: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar caja'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '65');
    await tester.tap(find.widgetWithText(FilledButton, 'Cerrar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Cierre sincronizado'), findsOneWidget);
    expect(find.text('La información de caja y ventas quedó actualizada.'),
        findsOneWidget);
    expect(find.textContaining('Batches'), findsNothing);
    expect(find.textContaining('Mutaciones'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Aceptar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('receive-only Caja registers an offline inflow and refreshes',
      (tester) async {
    await _authorizeMovement(database, const ['cash.receive']);
    await _pumpMovementDashboard(
      tester,
      database: database,
      service: service,
      closeSyncService: closeSyncService,
      permissions: const {'cash.receive'},
    );
    expect(find.text('Entrada de efectivo'), findsOneWidget);
    expect(find.text('Salida de efectivo'), findsNothing);
    await tester.tap(find.text('Entrada de efectivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aporte del propietario').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '10.000');
    await tester.enterText(find.byType(TextField).last, 'Aporte adicional');
    await tester.pumpAndSettle();
    expect(find.text('Después del movimiento: \$ 10.050'), findsOneWidget);
    await tester.tap(find.text('Registrar movimiento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(
        find.text('Movimiento registrado en el dispositivo.'), findsOneWidget);
    final movement = await database
        .customSelect(
          'select direction, category, amount_cents, note, source_type, '
          'source_id, local_status '
          'from local_cash_movements',
        )
        .getSingle();
    expect(movement.read<String>('direction'), 'inflow');
    expect(movement.read<String>('category'), 'owner_contribution');
    expect(movement.read<int>('amount_cents'), 1000000);
    expect(movement.read<String>('note'), 'Aporte adicional');
    expect(movement.read<String>('source_type'), 'manual');
    expect(movement.data['source_id'], isNull);
    expect(movement.read<String>('local_status'), 'dirty');
    expect(
        await database
            .customSelect(
              'select count(*) as n from local_sync_mutations '
              "where entity_table = 'cash_movements'",
            )
            .getSingle()
            .then((row) => row.read<int>('n')),
        1);
  });

  testWidgets('disburse-only Caja shows only outflow while session is open',
      (tester) async {
    await _authorizeMovement(database, const ['cash.disburse']);
    await _pumpMovementDashboard(
      tester,
      database: database,
      service: service,
      closeSyncService: closeSyncService,
      permissions: const {'cash.disburse'},
    );
    expect(find.text('Salida de efectivo'), findsOneWidget);
    expect(find.text('Entrada de efectivo'), findsNothing);
    await tester.tap(find.text('Salida de efectivo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Servicios públicos').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '20');
    await tester.pumpAndSettle();
    expect(find.text('Después del movimiento: \$ 30'), findsOneWidget);
    await tester.tap(find.text('Registrar movimiento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(
      await CashSessionLocalDao(database).calculateExpectedCashCentsForSession(
        cashSessionId: 'session-s1',
      ),
      BigInt.from(3000),
    );
  });

  testWidgets('both capabilities show both movement actions', (tester) async {
    await _pumpMovementDashboard(
      tester,
      database: database,
      service: service,
      closeSyncService: closeSyncService,
      permissions: const {'cash.receive', 'cash.disburse'},
    );
    expect(find.text('Entrada de efectivo'), findsOneWidget);
    expect(find.text('Salida de efectivo'), findsOneWidget);
  });

  testWidgets('no movement capability hides both actions', (tester) async {
    await _pumpMovementDashboard(
      tester,
      database: database,
      service: service,
      closeSyncService: closeSyncService,
      permissions: const {},
    );
    expect(find.text('Entrada de efectivo'), findsNothing);
    expect(find.text('Salida de efectivo'), findsNothing);
  });

  testWidgets('closed Caja does not expose movement actions', (tester) async {
    await database.customStatement(
      "update cash_sessions set status = 'closed' where id = 'session-s1'",
    );
    await _pumpMovementDashboard(
      tester,
      database: database,
      service: service,
      closeSyncService: closeSyncService,
      permissions: const {'cash.receive', 'cash.disburse'},
    );
    expect(find.text('Entrada de efectivo'), findsNothing);
    expect(find.text('Salida de efectivo'), findsNothing);
  });

  test('successful canonical close projects the closed state locally',
      () async {
    final result = await service.closeCashSession(
      const CloseCashSessionInput(
        businessId: 'business-a',
        branchId: 'branch-a',
        profileId: 'profile-a',
        actualClosingAmount: 65,
      ),
    );
    final row = await database
        .customSelect(
          "select * from cash_sessions where id = 'session-s1'",
        )
        .getSingle();
    final openSession =
        await CashSessionLocalDao(database).getOpenCashSessionForBranch(
      businessId: 'business-a',
      branchId: 'branch-a',
    );

    expect(result.expectedCashAmount, 65);
    expect(result.actualClosingAmount, 65);
    expect(result.differenceAmount, 0);
    expect(row.data['status'], 'closed');
    expect(row.data['local_status'], 'synced');
    expect(row.data['sync_status'], SyncStatus.synced.index);
    expect(openSession, isNull);
  });

  test('successful canonical close projects the closed runtime state',
      () async {
    CloseCashSessionResult? projected;
    final runtimeAwareService = CashSessionLocalService(
      dao: CashSessionLocalDao(database),
      remoteDataSource: CashSessionRemoteDataSource.withInvoker(
        (functionName, parameters) async => _closedSnapshot,
      ),
      runtimeCloseProjector: (input, result) async {
        expect(input.deviceInstallationId, 'installation-a');
        expect(input.appDeviceId, 'device-a');
        projected = result;
      },
    );

    final result = await runtimeAwareService.closeCashSession(
      const CloseCashSessionInput(
        businessId: 'business-a',
        branchId: 'branch-a',
        profileId: 'profile-a',
        actualClosingAmount: 65,
        appDeviceId: 'device-a',
        deviceInstallationId: 'installation-a',
      ),
    );

    expect(projected?.cashSessionId, result.cashSessionId);
    expect(projected?.status, 'closed');
  });
}

ProductiveManualSyncService _successfulProductiveSyncService() {
  Future<ProductiveSyncDomainResult> succeed(
    ProductiveSyncExecutionContext context,
  ) async {
    return const ProductiveSyncDomainResult.succeeded(
      ProductiveSyncDomain.catalog,
    );
  }

  return ProductiveManualSyncService(
    inputLoader: () async => const AppSyncCoordinatorInput(
      businessId: 'business-a',
      branchId: 'branch-a',
      profileId: 'profile-a',
      installationId: 'installation-a',
      isOnline: true,
    ),
    contextValidator: (input) async => const AppRuntimeContext(
      businessId: 'business-a',
      branchId: 'branch-a',
      profileId: 'profile-a',
      installationId: 'installation-a',
      appDeviceId: 'device-a',
    ),
    catalogUploadRunner: succeed,
    cashRunner: (context) async =>
        const ProductiveSyncDomainResult.succeeded(ProductiveSyncDomain.cash),
    posRunner: (context) async =>
        const ProductiveSyncDomainResult.succeeded(ProductiveSyncDomain.pos),
    purchasesRunner: (context) async =>
        const ProductiveSyncDomainResult.succeeded(
            ProductiveSyncDomain.purchases),
    inventoryRunner: (context) async =>
        const ProductiveSyncDomainResult.succeeded(
            ProductiveSyncDomain.inventory),
    catalogRefreshRunner: succeed,
    statusLoader: ({
      required scope,
      required isOnline,
      required isSyncing,
    }) async =>
        ProductiveSyncStatus(
      scope: scope,
      connectivity: ProductiveSyncConnectivity.online,
      isSyncing: false,
      pendingSales: 0,
      pendingPurchases: 0,
      pendingCashOperations: 0,
      pendingProductOperations: 0,
      pendingInventoryOperations: 0,
      openIssueCount: 0,
      attentionOperationCount: 0,
    ),
  );
}

class _NoPendingStaleSalesController
    implements ProductiveStaleSaleReconciliationController {
  @override
  Future<List<StaleSaleResolutionCandidate>> loadPending({
    required String profileId,
    required String businessId,
    required String branchId,
  }) async =>
      const [];

  @override
  Future<String?> resolveOpenDestination(
    StaleSaleResolutionCandidate candidate,
  ) =>
      throw UnimplementedError();

  @override
  Future<IntentionalStaleSaleReconciliationPreview> previewOccurred({
    required StaleSaleResolutionCandidate candidate,
    required String destinationCashSessionId,
    required IntentionalStaleSaleCashTreatment cashTreatment,
  }) =>
      throw UnimplementedError();

  @override
  Future<DiscardUnmaterializedLocalSaleResult> discardDidNotOccur({
    required String profileId,
    required String appDeviceId,
    required StaleSaleResolutionCandidate candidate,
  }) =>
      throw UnimplementedError();

  @override
  Future<IntentionalStaleSaleReconciliationResult> reconcileDidOccur({
    required String profileId,
    required String appDeviceId,
    required Set<String> effectivePermissions,
    required StaleSaleResolutionCandidate candidate,
    required String destinationCashSessionId,
    required IntentionalStaleSaleCashTreatment cashTreatment,
  }) =>
      throw UnimplementedError();
}

class _FakeCashSyncOutboxService implements CashSyncOutboxService {
  @override
  Future<CashSyncOutboxResult> enqueuePendingCash({
    required String businessId,
    required String branchId,
    required String profileId,
    String? appDeviceId,
    String? deviceInstallationId,
    int limit = 10,
  }) async {
    return CashSyncOutboxResult(
      businessId: businessId,
      branchId: branchId,
      cashRegistersChecked: 0,
      cashSessionsChecked: 0,
      batchesCreated: 0,
      mutationsEnqueued: 0,
      results: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosSyncOutboxService implements PosSyncOutboxService {
  @override
  Future<PosSyncOutboxResult> enqueuePendingPosSales({
    required String businessId,
    required String branchId,
    required String profileId,
    String? appDeviceId,
    String? deviceInstallationId,
    int limit = 10,
  }) async {
    return PosSyncOutboxResult(
      businessId: businessId,
      branchId: branchId,
      salesChecked: 0,
      salesEnqueued: 0,
      batchesCreated: 0,
      mutationsEnqueued: 0,
      results: const [],
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCashSyncUploadService implements CashSyncUploadService {
  @override
  Future<CatalogUploadRunResult> uploadPendingCashBatches({
    required String businessId,
    String? branchId,
    int batchLimit = 10,
  }) async {
    return _emptyUploadResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePosSyncUploadService implements PosSyncUploadService {
  @override
  Future<CatalogUploadRunResult> uploadPendingPosBatches({
    required String businessId,
    String? branchId,
    int batchLimit = 10,
  }) async {
    return _emptyUploadResult;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _emptyUploadResult = CatalogUploadRunResult(
  batchesChecked: 0,
  batchesUploaded: 0,
  batchesCompleted: 0,
  batchesPartial: 0,
  batchesFailed: 0,
  mutationsUploaded: 0,
);

final _closedSnapshot = <String, Object?>{
  'cash_session_id': 'session-s1',
  'business_id': 'business-a',
  'branch_id': 'branch-a',
  'cash_register_id': 'register-a',
  'opened_by_profile_id': 'profile-a',
  'closed_by_profile_id': 'profile-a',
  'opened_at': '2026-08-30T12:00:00Z',
  'closed_at': '2026-08-30T13:00:00Z',
  'opening_cash_amount': 50,
  'expected_cash_amount': 65,
  'closing_cash_amount': 65,
  'difference_amount': 0,
  'status': 'closed',
  'version': 2,
  'notes': null,
  'created_at': '2026-08-30T12:00:00Z',
  'updated_at': '2026-08-30T13:00:00Z',
  'reused_open_session': false,
};

Future<void> _seed(AppDatabase database) async {
  await database.customStatement('''
    insert into businesses (id, name) values ('business-a', 'Business A')
  ''');
  await database.customStatement('''
    insert into branches (id, business_id, name)
    values ('branch-a', 'business-a', 'Principal')
  ''');
  await database.customStatement('''
    insert into profiles (id, full_name) values ('profile-a', 'Profile A')
  ''');
  await database.customStatement('''
    insert into cash_registers (
      id, business_id, branch_id, name, code, status, local_status, sync_status
    ) values (
      'register-a', 'business-a', 'branch-a', 'Principal', 'MAIN',
      'active', 'synced', 0
    )
  ''');
  await database.customStatement('''
    insert into cash_sessions (
      id, business_id, branch_id, cash_register_id, opened_by_profile_id,
      opened_at, opening_cash_amount, status, idempotency_key,
      local_status, sync_status
    ) values (
      'session-s1', 'business-a', 'branch-a', 'register-a', 'profile-a',
      '2026-08-30T12:00:00Z', 50, 'open', 'session-s1-key',
      'synced', 0
    )
  ''');
}

Future<void> _authorizeMovement(
  AppDatabase database,
  List<String> permissions,
) async {
  await AuthorizedOperationalContextLocalDao(database).replaceContext(
    AuthorizedOperationalContextProjection(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
      effectivePermissions: permissions,
      effectiveRoles: const [],
      applicableMembershipIds: const [],
      authorizationValidatedAt: DateTime.now().toUtc(),
      snapshotId: 'c3-snapshot',
    ),
  );
}

Future<void> _pumpMovementDashboard(
  WidgetTester tester, {
  required AppDatabase database,
  required CashSessionLocalService service,
  required CashCloseSyncTriggerService closeSyncService,
  required Set<String> permissions,
}) async {
  await tester.binding.setSurfaceSize(const Size(1000, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final movementService = CashMovementService(
    database: database,
    loadCurrentContext: () async => AppCurrentContext(
      businessId: 'business-a',
      branchId: 'branch-a',
      profileId: 'profile-a',
      installationId: 'installation-a',
      appDeviceId: 'device-a',
      cashRegisterId: 'register-a',
      cashSessionId: 'session-s1',
      isOnline: false,
      authorizationContextReady: true,
      permissions: AppPermissionSet(permissions),
    ),
  );
  await tester.pumpWidget(ProviderScope(
    overrides: [
      cashSessionLocalServiceProvider.overrideWithValue(service),
      cashMovementServiceProvider.overrideWithValue(movementService),
      cashCloseSyncTriggerServiceProvider.overrideWithValue(closeSyncService),
      cashSyncOutboxServiceProvider.overrideWithValue(
        _FakeCashSyncOutboxService(),
      ),
      posSyncOutboxServiceProvider.overrideWithValue(
        _FakePosSyncOutboxService(),
      ),
      cashSyncUploadServiceProvider.overrideWithValue(
        _FakeCashSyncUploadService(),
      ),
      posSyncUploadServiceProvider.overrideWithValue(
        _FakePosSyncUploadService(),
      ),
      productiveStaleSaleReconciliationServiceProvider.overrideWithValue(
        _NoPendingStaleSalesController(),
      ),
    ],
    child: MaterialApp(
      home: CashDashboardScreen(
        businessId: 'business-a',
        branchId: 'branch-a',
        profileId: 'profile-a',
        cashRegisterId: 'register-a',
        canReadCash: permissions.contains('cash.read'),
        canOpenCash: permissions.contains('cash.open'),
        canCloseCash: permissions.contains('cash.close'),
        effectivePermissions: permissions,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}
