import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/reports/application/cash_flow_report_providers.dart';
import 'package:inventario_frontend/features/reports/application/cash_flow_report_controller.dart';
import 'package:inventario_frontend/features/reports/application/cash_flow_report_service.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_providers.dart';
import 'package:inventario_frontend/features/reports/data/models/cash_flow_report_models.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';
import 'package:inventario_frontend/features/reports/presentation/screens/cash_flow_report_screen.dart';

void main() {
  final now = DateTime(2026, 9, 23, 14);

  Future<void> pump(WidgetTester tester, _FakeService service,
      {bool online = false,
      Set<String> permissions = const {'reports.cash'},
      ThemeData? outerTheme}) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          cashFlowReportServiceProvider.overrideWithValue(service),
          salesReportOnlineCheckProvider.overrideWithValue(() async => online),
          salesReportClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp(
            theme: outerTheme,
            home: CashFlowReportScreen(
              profileId: 'p',
              businessId: 'b',
              branchId: 'a',
              branchName: 'Principal',
              effectivePermissions: permissions,
              authorizationContextReady: true,
            ))));
    await tester.pumpAndSettle();
  }

  testWidgets('cash-flow report keeps readable light surface under dark app',
      (tester) async {
    final period = cashFlowPeriodFor(CashFlowPreset.today, now);
    final service =
        _FakeService({period.filterKey: _snapshot(period, pending: false)});
    await pump(tester, service, outerTheme: ThemeData.dark());
    final branch = find.text('Principal');
    expect(Theme.of(tester.element(branch)).brightness, Brightness.light);
    expect(tester.widget<Text>(branch).style?.color, isNot(Colors.white));
    expect(tester.takeException(), null);
  });

  testWidgets('offline cache displays authoritative totals and pending warning',
      (tester) async {
    final period = cashFlowPeriodFor(CashFlowPreset.today, now);
    final service =
        _FakeService({period.filterKey: _snapshot(period, pending: true)});
    await pump(tester, service);
    expect(find.text('Sin conexión · mostrando último reporte guardado'),
        findsOneWidget);
    expect(find.byKey(const Key('cash-flow-pending-warning')), findsOneWidget);
    expect(find.textContaining('puede no incluirlos todavía'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('cash-flow-inflows')),
            matching: find.text(r'$130')),
        findsOneWidget);
    expect(service.refreshCalls, 0);
  });

  testWidgets('pending cash sale warns offline without changing Hosted total',
      (tester) async {
    final period = cashFlowPeriodFor(CashFlowPreset.today, now);
    final service = _FakeService({
      period.filterKey: _snapshot(period, pending: false, pendingSale: true)
    });
    await pump(tester, service);
    expect(find.textContaining('Hay ventas en efectivo pendientes'),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const Key('cash-flow-inflows')),
            matching: find.text(r'$130')),
        findsOneWidget);
  });

  testWidgets('pending sale and cash movement use one combined warning',
      (tester) async {
    final period = cashFlowPeriodFor(CashFlowPreset.today, now);
    final service = _FakeService({
      period.filterKey: _snapshot(period, pending: true, pendingSale: true)
    });
    await pump(tester, service);
    expect(find.byKey(const Key('cash-flow-pending-warning')), findsOneWidget);
    expect(find.textContaining('movimientos o ventas en efectivo pendientes'),
        findsOneWidget);
  });

  testWidgets(
      'offline without compatible period does not reuse previous metrics',
      (tester) async {
    final today = cashFlowPeriodFor(CashFlowPreset.today, now);
    final service =
        _FakeService({today.filterKey: _snapshot(today, pending: false)});
    await pump(tester, service);
    await tester.tap(find.text('Este mes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('no tiene un reporte guardado'), findsOneWidget);
    expect(find.byKey(const Key('cash-flow-inflows')), findsNothing);
  });

  testWidgets('missing reports.cash blocks reading and rendering',
      (tester) async {
    final service = _FakeService({});
    await pump(tester, service, permissions: const {'reports.sales'});
    expect(find.text('No tienes permiso para consultar este reporte.'),
        findsOneWidget);
    expect(service.readCalls, 0);
  });

  testWidgets('online refresh clears pending warning only with new snapshot',
      (tester) async {
    final period = cashFlowPeriodFor(CashFlowPreset.today, now);
    final service = _FakeService(
      {period.filterKey: _snapshot(period, pending: false, pendingSale: true)},
      onRefresh: (_) async => CashFlowRefreshResult(
          CashFlowRefreshOutcome.refreshed,
          snapshot: _snapshot(period, pending: false)),
    );
    await pump(tester, service, online: true);
    expect(find.byKey(const Key('cash-flow-pending-warning')), findsNothing);
    expect(service.refreshCalls, 1);
  });

  testWidgets('cancelled custom date selection retains current period',
      (tester) async {
    final period = cashFlowPeriodFor(CashFlowPreset.today, now);
    final service =
        _FakeService({period.filterKey: _snapshot(period, pending: false)});
    await pump(tester, service);
    await tester.tap(find.text('Personalizado'));
    await tester.pumpAndSettle();
    final picker = find.byType(DateRangePickerDialog);
    expect(picker, findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cash-flow-inflows')), findsOneWidget);
    expect(service.readCalls, 1);
  });
}

class _FakeService implements CashFlowReportService {
  _FakeService(this.cache, {this.onRefresh});
  final Map<String, CashFlowReportSnapshot> cache;
  final Future<CashFlowRefreshResult> Function(SalesReportScope)? onRefresh;
  int readCalls = 0;
  int refreshCalls = 0;

  @override
  Future<CashFlowCacheResult> readCached(SalesReportScope scope) async {
    readCalls++;
    final snapshot = cache[scope.period.filterKey];
    return CashFlowCacheResult(
        snapshot == null
            ? CashFlowCacheOutcome.noCache
            : CashFlowCacheOutcome.available,
        snapshot);
  }

  @override
  Future<CashFlowRefreshResult> refresh(SalesReportScope scope) async {
    refreshCalls++;
    if (onRefresh != null) return onRefresh!(scope);
    return const CashFlowRefreshResult(CashFlowRefreshOutcome.remoteFailure);
  }
}

CashFlowReportSnapshot _snapshot(SalesReportPeriod period,
        {required bool pending, bool pendingSale = false}) =>
    CashFlowReportSnapshot(
      summary: CashFlowReportSummary(
        businessId: 'b',
        branchId: 'a',
        periodFrom: period.from,
        periodTo: period.to,
        cashSalesCents: BigInt.from(10000),
        additionalInflowsCents: BigInt.from(3000),
        totalInflowsCents: BigInt.from(13000),
        totalOutflowsCents: BigInt.from(6500),
        netCashFlowCents: BigInt.from(6500),
        inventoryAcquisitionCents: BigInt.from(4000),
        operatingExpensesCents: BigInt.from(1500),
        ownerWithdrawalsCents: BigInt.from(700),
        otherOutflowsCents: BigInt.from(300),
        outflowByCategory: const {},
        authoritativeAsOf: DateTime.utc(2026, 9, 23),
      ),
      fetchedAt: DateTime.utc(2026, 9, 23),
      authorizationValidatedAt: DateTime.utc(2026, 9, 23),
      hasPendingLocalSync: pending,
      hasPendingLocalCashSales: pendingSale,
    );
