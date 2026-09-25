import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/reports/application/profitability_report_controller.dart';
import 'package:inventario_frontend/features/reports/application/profitability_report_providers.dart';
import 'package:inventario_frontend/features/reports/application/profitability_report_service.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_controller.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_providers.dart';
import 'package:inventario_frontend/features/reports/data/datasources/profitability_report_remote_datasource.dart';
import 'package:inventario_frontend/features/reports/data/models/profitability_report_models.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';

void main() {
  final period = SalesReportPeriod(
    from: DateTime.utc(2026, 9),
    to: DateTime.utc(2026, 10),
  );

  test('without both capabilities no cache or refresh is requested', () async {
    final fake = _FakeProfitabilityService();
    final container = _container(fake, online: true);
    addTearDown(container.dispose);
    final request = _request(period, permissions: const {'reports.sales'});
    final subscription = container.listen(
      profitabilityReportControllerProvider(request),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await _flush();
    expect(container.read(profitabilityReportControllerProvider(request)).phase,
        ProfitabilityReportPhase.unauthorized);
    expect(fake.readScopes, isEmpty);
    expect(fake.refreshScopes, isEmpty);
  });

  test('offline cache is presented without a remote call', () async {
    final fake = _FakeProfitabilityService(cache: _snapshot(period));
    final container = _container(fake, online: false);
    addTearDown(container.dispose);
    final request = _request(period);
    final subscription = container.listen(
      profitabilityReportControllerProvider(request),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await _flush();
    final state =
        container.read(profitabilityReportControllerProvider(request));
    expect(state.phase, ProfitabilityReportPhase.ready);
    expect(state.notice, ProfitabilityReportNotice.offlineCache);
    expect(state.snapshot!.summary.knownNetSalesCents, BigInt.from(5400000));
    expect(fake.refreshScopes, isEmpty);
  });

  test('offline without cache is unavailable, not fabricated zeroes', () async {
    final fake = _FakeProfitabilityService();
    final container = _container(fake, online: false);
    addTearDown(container.dispose);
    final request = _request(period);
    final subscription = container.listen(
      profitabilityReportControllerProvider(request),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await _flush();
    final state =
        container.read(profitabilityReportControllerProvider(request));
    expect(state.phase, ProfitabilityReportPhase.unavailableOffline);
    expect(state.snapshot, isNull);
  });

  test('refresh is single-flight and keeps cached metrics visible', () async {
    final pending = Completer<ProfitabilityRefreshResult>();
    final fake = _FakeProfitabilityService(
      cache: _snapshot(period),
      onRefresh: (_) => pending.future,
    );
    var online = false;
    final container = ProviderContainer(overrides: [
      profitabilityReportServiceProvider.overrideWithValue(fake),
      salesReportOnlineCheckProvider.overrideWithValue(() async => online),
    ]);
    addTearDown(container.dispose);
    final request = _request(period);
    final subscription = container.listen(
      profitabilityReportControllerProvider(request),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await _flush();
    online = true;
    final controller =
        container.read(profitabilityReportControllerProvider(request).notifier);
    final first = controller.refresh();
    final second = controller.refresh();
    await _flush();
    expect(fake.refreshScopes, hasLength(1));
    expect(
        container.read(profitabilityReportControllerProvider(request)).snapshot,
        isNotNull);
    pending.complete(ProfitabilityRefreshResult(
      outcome: ProfitabilityRefreshOutcome.refreshed,
      snapshot: _snapshot(period, net: 5500000),
    ));
    await Future.wait([first, second]);
    expect(
        container
            .read(profitabilityReportControllerProvider(request))
            .snapshot!
            .summary
            .knownNetSalesCents,
        BigInt.from(5500000));
  });

  test('remote failure preserves cache and exposes warning', () async {
    final cached = _snapshot(period);
    final fake = _FakeProfitabilityService(
      cache: cached,
      onRefresh: (_) async => ProfitabilityRefreshResult(
        outcome: ProfitabilityRefreshOutcome.remoteFailure,
        preservedCache: cached,
        failureKind: ProfitabilityReportRemoteFailureKind.network,
      ),
    );
    final container = _container(fake, online: true);
    addTearDown(container.dispose);
    final request = _request(period);
    final subscription = container.listen(
      profitabilityReportControllerProvider(request),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await _flush();
    final state =
        container.read(profitabilityReportControllerProvider(request));
    expect(state.phase, ProfitabilityReportPhase.ready);
    expect(state.notice, ProfitabilityReportNotice.refreshFailed);
    expect(state.snapshot, same(cached));
  });

  test('authoritative denial clears previously visible sensitive data',
      () async {
    final pending = Completer<ProfitabilityRefreshResult>();
    final fake = _FakeProfitabilityService(
      cache: _snapshot(period),
      onRefresh: (_) => pending.future,
    );
    final container = _container(fake, online: true);
    addTearDown(container.dispose);
    final request = _request(period);
    final subscription = container.listen(
      profitabilityReportControllerProvider(request),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await _flush();
    expect(
        container.read(profitabilityReportControllerProvider(request)).snapshot,
        isNotNull);
    pending.complete(const ProfitabilityRefreshResult(
      outcome: ProfitabilityRefreshOutcome.unauthorized,
    ));
    await _flush();
    final state =
        container.read(profitabilityReportControllerProvider(request));
    expect(state.phase, ProfitabilityReportPhase.unauthorized);
    expect(state.snapshot, isNull);
  });

  test('period and branch use distinct provider identities and scopes',
      () async {
    final fake = _FakeProfitabilityService();
    final container = _container(fake, online: false);
    addTearDown(container.dispose);
    final nextPeriod = SalesReportPeriod(
      from: DateTime.utc(2026, 8),
      to: DateTime.utc(2026, 9),
    );
    final requests = [
      _request(period),
      _request(nextPeriod),
      _request(period, branchId: 'branch-b'),
    ];
    final subscriptions = [
      for (final request in requests)
        container.listen(
            profitabilityReportControllerProvider(request), (_, __) {},
            fireImmediately: true),
    ];
    addTearDown(() {
      for (final subscription in subscriptions) {
        subscription.close();
      }
    });
    await _flush();
    expect(fake.readScopes.map((scope) => scope.period.filterKey),
        [period.filterKey, nextPeriod.filterKey, period.filterKey]);
    expect(fake.readScopes.map((scope) => scope.branchId),
        ['branch-a', 'branch-a', 'branch-b']);
  });

  test('a late old-period response cannot replace the selected period',
      () async {
    final started = Completer<void>();
    final release = Completer<ProfitabilityRefreshResult>();
    final nextPeriod = SalesReportPeriod(
      from: DateTime.utc(2026, 8),
      to: DateTime.utc(2026, 9),
    );
    final fake = _FakeProfitabilityService(onRefresh: (scope) {
      if (scope.period.filterKey == period.filterKey) {
        started.complete();
        return release.future;
      }
      return Future.value(ProfitabilityRefreshResult(
        outcome: ProfitabilityRefreshOutcome.refreshed,
        snapshot: _snapshot(nextPeriod, net: 5500000),
      ));
    });
    final container = _container(fake, online: true);
    addTearDown(container.dispose);
    final oldRequest = _request(period);
    final oldSubscription = container.listen(
      profitabilityReportControllerProvider(oldRequest),
      (_, __) {},
      fireImmediately: true,
    );
    await started.future;
    oldSubscription.close();
    await _flush();
    final newRequest = _request(nextPeriod);
    final newSubscription = container.listen(
      profitabilityReportControllerProvider(newRequest),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(newSubscription.close);
    await _flush();
    release.complete(ProfitabilityRefreshResult(
      outcome: ProfitabilityRefreshOutcome.refreshed,
      snapshot: _snapshot(period),
    ));
    await _flush();
    final state =
        container.read(profitabilityReportControllerProvider(newRequest));
    expect(state.snapshot!.summary.periodFrom, nextPeriod.from);
    expect(state.snapshot!.summary.knownNetSalesCents, BigInt.from(5500000));
  });
}

ProviderContainer _container(_FakeProfitabilityService service,
        {required bool online}) =>
    ProviderContainer(overrides: [
      profitabilityReportServiceProvider.overrideWithValue(service),
      salesReportOnlineCheckProvider.overrideWithValue(() async => online),
    ]);

ProfitabilityReportViewRequest _request(
  SalesReportPeriod period, {
  String branchId = 'branch-a',
  Set<String> permissions = const {'reports.sales', 'sales.view_costs'},
}) =>
    ProfitabilityReportViewRequest(
      context: SalesReportViewRequest(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: branchId,
        branchName: branchId,
        effectivePermissions: permissions,
        authorizationContextReady: true,
      ),
      period: period,
    );

ProfitabilityReportSnapshot _snapshot(SalesReportPeriod period,
        {int net = 5400000}) =>
    ProfitabilityReportSnapshot(
      summary: ProfitabilityReportSummary(
        businessId: 'business-a',
        branchId: 'branch-a',
        periodFrom: period.from,
        periodTo: period.to,
        knownNetSalesCents: BigInt.from(net),
        knownCogsCents: BigInt.from(4729000),
        knownGrossProfitCents: BigInt.from(net - 4729000),
        unknownCostItemCount: 0,
        unknownCostNetSalesCents: BigInt.zero,
        costCoverageComplete: true,
        authoritativeAsOf: DateTime.utc(2026, 10, 1),
      ),
      fetchedAt: DateTime.utc(2026, 10, 1),
      authorizationValidatedAt: DateTime.utc(2026, 10, 1),
      capabilityFingerprint: 'reports.sales\u001fsales.view_costs',
      includesSensitiveData: true,
      includesCosts: true,
    );

class _FakeProfitabilityService implements ProfitabilityReportService {
  _FakeProfitabilityService({this.cache, this.onRefresh});

  final ProfitabilityReportSnapshot? cache;
  final Future<ProfitabilityRefreshResult> Function(SalesReportScope)?
      onRefresh;
  final List<SalesReportScope> readScopes = [];
  final List<SalesReportScope> refreshScopes = [];

  @override
  Future<ProfitabilityCacheReadResult> readCached(
      SalesReportScope scope) async {
    readScopes.add(scope);
    return ProfitabilityCacheReadResult(
      outcome: cache == null
          ? ProfitabilityCacheReadOutcome.noCache
          : ProfitabilityCacheReadOutcome.available,
      snapshot: cache,
    );
  }

  @override
  Future<ProfitabilityRefreshResult> refresh(SalesReportScope scope) {
    refreshScopes.add(scope);
    return onRefresh?.call(scope) ??
        Future.value(const ProfitabilityRefreshResult(
          outcome: ProfitabilityRefreshOutcome.remoteFailure,
        ));
  }
}

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
