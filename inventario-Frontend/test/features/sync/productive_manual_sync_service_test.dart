import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/application/app_sync_coordinator_models.dart';
import 'package:inventario_frontend/features/sync/application/productive_manual_sync_service.dart';
import 'package:inventario_frontend/features/sync/application/productive_sync_status.dart';
import 'package:inventario_frontend/features/sync/data/models/runtime_setup_models.dart';

void main() {
  test('C4B1B authoritative progress re-runs the shared domain order',
      () async {
    var progress = (0, 0);
    var purchaseCalls = 0;
    final fixture = _Fixture(
      dependencyProgress: () => progress,
      onPurchases: () {
        purchaseCalls++;
        if (purchaseCalls == 1) progress = (1, 1);
      },
    );
    await fixture.service().run();
    expect(fixture.calls.where((call) => call == 'cash'), hasLength(2));
    expect(purchaseCalls, 2);
  });

  test('C4B1B no authoritative progress stops after one pass', () async {
    final fixture = _Fixture(
      dependencyProgress: () => (0, 0),
      purchasesResult: () => throw StateError('network'),
    );
    await fixture.service().run();
    expect(fixture.calls.where((call) => call == 'cash'), hasLength(1));
  });

  test('C4B1B progress is deterministically bounded at eight passes', () async {
    var applied = 0;
    final fixture = _Fixture(
      dependencyProgress: () => (applied, 0),
      onPurchases: () => applied++,
    );
    await fixture.service().run();
    expect(fixture.calls.where((call) => call == 'cash'), hasLength(8));
  });
  test('SY-01 clean no-op reports Todo al día without duplicate stages',
      () async {
    final fixture = _Fixture();

    final result = await fixture.service().run();

    expect(result.outcome, ProductiveManualSyncOutcome.completed);
    expect(result.message, 'Todo al día.');
    expect(fixture.calls, ['validate', ..._expectedOrder]);
    expect(fixture.localStateChangeCalls, 1);
    expect(result.domainResults, hasLength(5));
    expect(result.domainResults.every((item) => item.succeeded), isTrue);
  });

  test('SY-02 pending sale runs POS and verifies pendingSales becomes zero',
      () async {
    var pendingSales = 1;
    final fixture = _Fixture(
      status: () => _status(pendingSales: pendingSales),
      onPos: () => pendingSales = 0,
    );

    final result = await fixture.service().run();

    expect(fixture.calls, contains('pos'));
    expect(result.finalStatus?.pendingSales, 0);
    expect(result.outcome, ProductiveManualSyncOutcome.completed);
  });

  test('SY-03 Product dependency is attempted before its pending Purchase',
      () async {
    var pendingProducts = 1;
    var pendingPurchases = 1;
    final fixture = _Fixture(
      status: () => _status(
        pendingProductOperations: pendingProducts,
        pendingPurchases: pendingPurchases,
      ),
      onCatalogUpload: () => pendingProducts = 0,
      onPurchases: () {
        expect(pendingProducts, 0);
        pendingPurchases = 0;
      },
    );

    final result = await fixture.service().run();

    expect(fixture.calls.indexOf('catalog-upload'),
        lessThan(fixture.calls.indexOf('purchases')));
    expect(result.outcome, ProductiveManualSyncOutcome.completed);
  });

  test('SY-04 pending cash is published without cash lifecycle actions',
      () async {
    var pendingCash = 1;
    final fixture = _Fixture(
      status: () => _status(pendingCashOperations: pendingCash),
      onCash: () => pendingCash = 0,
    );

    final result = await fixture.service().run();

    expect(fixture.calls.where((call) => call == 'cash'), hasLength(1));
    expect(result.finalStatus?.pendingCashOperations, 0);
    expect(result.outcome, ProductiveManualSyncOutcome.completed);
  });

  test('SY-05 independent inventory outbox is published', () async {
    var pendingInventory = 1;
    final fixture = _Fixture(
      status: () => _status(pendingInventoryOperations: pendingInventory),
      onInventory: () => pendingInventory = 0,
    );

    final result = await fixture.service().run();

    expect(fixture.calls, contains('inventory'));
    expect(result.finalStatus?.pendingInventoryOperations, 0);
    expect(result.outcome, ProductiveManualSyncOutcome.completed);
  });

  test('SY-06 mixed domains execute in the dependency-safe order', () async {
    final fixture = _Fixture();

    final result = await fixture.service().run();

    expect(fixture.calls, ['validate', ..._expectedOrder]);
    expect(result.outcome, ProductiveManualSyncOutcome.completed);
  });

  test('pending purchase is uploaded before its dependent POS sale', () async {
    var purchaseUploaded = false;
    final fixture = _Fixture(
      onPurchases: () => purchaseUploaded = true,
      onPos: () => expect(purchaseUploaded, isTrue),
    );

    await fixture.service().run();

    expect(fixture.calls.indexOf('purchases'),
        lessThan(fixture.calls.indexOf('pos')));
  });

  test('SY-07 one retryable failure does not stop other domains', () async {
    final fixture = _Fixture(
      status: () => _status(pendingPurchases: 1),
      purchasesResult: () => throw StateError('network'),
    );

    final result = await fixture.service().run();

    expect(fixture.calls, containsAll(['inventory', 'catalog-refresh']));
    expect(result.outcome, ProductiveManualSyncOutcome.pending);
    expect(result.finalStatus?.requiresAttention, isFalse);
    final purchases = result.domainResults.singleWhere(
      (item) => item.domain == ProductiveSyncDomain.purchases,
    );
    expect(purchases.failedRetryable, isTrue);
  });

  test('SY-08 conflict or rejection is reported as requires attention',
      () async {
    final fixture = _Fixture(
      status: () => _status(attentionOperationCount: 1),
      posResult: () => const ProductiveSyncDomainResult.pending(
        ProductiveSyncDomain.pos,
        requiresAttention: true,
      ),
    );

    final result = await fixture.service().run();

    expect(result.outcome, ProductiveManualSyncOutcome.requiresAttention);
    expect(result.message, contains('revisión'));
  });

  test('SY-09 offline preserves pending work and performs no upload', () async {
    final fixture = _Fixture(input: _input(isOnline: false));

    final result = await fixture.service().run();

    expect(result.outcome, ProductiveManualSyncOutcome.unavailable);
    expect(result.message, contains('Sin conexión'));
    expect(result.domainResults, hasLength(5));
    expect(result.domainResults.every((item) => !item.attempted), isTrue);
    expect(fixture.calls, isEmpty);
    expect(fixture.localStateChangeCalls, 0);
  });

  test('SY-10 concurrent taps share one effective execution', () async {
    final completer = Completer<ProductiveSyncDomainResult>();
    final fixture = _Fixture(
      catalogResult: () => completer.future,
    );
    final service = fixture.service();

    final first = service.run();
    final second = service.run();
    await Future<void>.delayed(Duration.zero);

    expect(fixture.calls.where((call) => call == 'validate'), hasLength(1));
    expect(
        fixture.calls.where((call) => call == 'catalog-upload'), hasLength(1));
    completer.complete(
      const ProductiveSyncDomainResult.succeeded(ProductiveSyncDomain.catalog),
    );
    expect((await first).completed, isTrue);
    expect((await second).completed, isTrue);
    expect(
        fixture.calls.where((call) => call == 'catalog-upload'), hasLength(1));
  });
}

const _expectedOrder = [
  'catalog-upload',
  'cash',
  'purchases',
  'pos',
  'inventory',
  'catalog-refresh',
  'status',
];

class _Fixture {
  _Fixture({
    AppSyncCoordinatorInput? input,
    ProductiveSyncStatus Function()? status,
    this.onCatalogUpload,
    this.onCash,
    this.onPos,
    this.onPurchases,
    this.onInventory,
    this.catalogResult,
    this.posResult,
    this.purchasesResult,
    this.dependencyProgress,
  })  : input = input ?? _input(),
        status = status ?? _status;

  final AppSyncCoordinatorInput input;
  final ProductiveSyncStatus Function() status;
  final void Function()? onCatalogUpload;
  final void Function()? onCash;
  final void Function()? onPos;
  final void Function()? onPurchases;
  final void Function()? onInventory;
  final FutureOr<ProductiveSyncDomainResult> Function()? catalogResult;
  final FutureOr<ProductiveSyncDomainResult> Function()? posResult;
  final FutureOr<ProductiveSyncDomainResult> Function()? purchasesResult;
  final (int, int) Function()? dependencyProgress;
  final calls = <String>[];
  var localStateChangeCalls = 0;

  ProductiveManualSyncService service() {
    return ProductiveManualSyncService(
      inputLoader: () async => input,
      contextValidator: (received) async {
        calls.add('validate');
        expect(received.metadata?['source'], 'productive_sync');
        expect(received.metadata?['sync_trigger'], 'manual');
        return const AppRuntimeContext(
          businessId: 'business-1',
          branchId: 'branch-1',
          profileId: 'profile-1',
          installationId: 'installation-1',
          appDeviceId: 'device-1',
        );
      },
      catalogUploadRunner: (context) async {
        calls.add('catalog-upload');
        _expectScope(context);
        onCatalogUpload?.call();
        return await catalogResult?.call() ??
            const ProductiveSyncDomainResult.succeeded(
              ProductiveSyncDomain.catalog,
            );
      },
      cashRunner: (context) async {
        calls.add('cash');
        _expectScope(context);
        onCash?.call();
        return const ProductiveSyncDomainResult.succeeded(
          ProductiveSyncDomain.cash,
        );
      },
      posRunner: (context) async {
        calls.add('pos');
        _expectScope(context);
        onPos?.call();
        return await posResult?.call() ??
            const ProductiveSyncDomainResult.succeeded(
              ProductiveSyncDomain.pos,
            );
      },
      purchasesRunner: (context) async {
        calls.add('purchases');
        _expectScope(context);
        onPurchases?.call();
        return await purchasesResult?.call() ??
            const ProductiveSyncDomainResult.succeeded(
              ProductiveSyncDomain.purchases,
            );
      },
      inventoryRunner: (context) async {
        calls.add('inventory');
        _expectScope(context);
        onInventory?.call();
        return const ProductiveSyncDomainResult.succeeded(
          ProductiveSyncDomain.inventory,
        );
      },
      catalogRefreshRunner: (context) async {
        calls.add('catalog-refresh');
        _expectScope(context);
        return const ProductiveSyncDomainResult.succeeded(
          ProductiveSyncDomain.catalog,
        );
      },
      statusLoader: (
          {required scope, required isOnline, required isSyncing}) async {
        calls.add('status');
        expect(localStateChangeCalls, 1);
        expect(scope.profileId, 'profile-1');
        expect(scope.businessId, 'business-1');
        expect(scope.branchId, 'branch-1');
        expect(isOnline, isTrue);
        expect(isSyncing, isFalse);
        return status();
      },
      dependencyProgressLoader: dependencyProgress == null
          ? null
          : ({required businessId, required branchId}) async =>
              dependencyProgress!(),
      onLocalStateChanged: () => localStateChangeCalls++,
    );
  }
}

void _expectScope(ProductiveSyncExecutionContext context) {
  expect(context.profileId, 'profile-1');
  expect(context.businessId, 'business-1');
  expect(context.branchId, 'branch-1');
  expect(context.installationId, 'installation-1');
  expect(context.appDeviceId, 'device-1');
}

AppSyncCoordinatorInput _input({bool isOnline = true}) {
  return AppSyncCoordinatorInput(
    businessId: 'business-1',
    branchId: 'branch-1',
    profileId: 'profile-1',
    installationId: 'installation-1',
    isOnline: isOnline,
  );
}

ProductiveSyncStatus _status({
  int pendingSales = 0,
  int pendingPurchases = 0,
  int pendingCashOperations = 0,
  int pendingProductOperations = 0,
  int pendingInventoryOperations = 0,
  int openIssueCount = 0,
  int attentionOperationCount = 0,
}) {
  return ProductiveSyncStatus(
    scope: const ProductiveSyncScope(
      profileId: 'profile-1',
      businessId: 'business-1',
      branchId: 'branch-1',
    ),
    connectivity: ProductiveSyncConnectivity.online,
    isSyncing: false,
    pendingSales: pendingSales,
    pendingPurchases: pendingPurchases,
    pendingCashOperations: pendingCashOperations,
    pendingProductOperations: pendingProductOperations,
    pendingInventoryOperations: pendingInventoryOperations,
    openIssueCount: openIssueCount,
    attentionOperationCount: attentionOperationCount,
  );
}
