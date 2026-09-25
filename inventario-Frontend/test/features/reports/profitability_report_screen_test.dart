import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/reports/application/profitability_report_controller.dart';
import 'package:inventario_frontend/features/reports/application/profitability_report_providers.dart';
import 'package:inventario_frontend/features/reports/application/profitability_report_service.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_controller.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_providers.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_service.dart';
import 'package:inventario_frontend/features/reports/data/models/profitability_report_models.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';
import 'package:inventario_frontend/features/reports/presentation/screens/sales_report_screen.dart';

void main() {
  final now = DateTime(2026, 9, 23, 14, 30);
  final today = salesReportPeriodFor(SalesReportPreset.today, now);

  testWidgets('complete coverage renders exact money and rounded margin',
      (tester) async {
    final profit = _FakeProfitabilityService()
      ..put(_snapshot(today, net: 5400000, cogs: 4729000));
    await _pumpScreen(tester, profit: profit, now: now);
    await _tapProfitability(tester);
    expect(find.text('Ventas netas analizadas'), findsOneWidget);
    expect(find.text(r'$54.000'), findsOneWidget);
    expect(find.text(r'$47.290'), findsOneWidget);
    expect(find.text(r'$6.710'), findsOneWidget);
    expect(find.text('12,43 %'), findsOneWidget);
    expect(find.text('Cobertura de costos completa'), findsOneWidget);
    expect(find.text('Rentabilidad parcial'), findsNothing);
  });

  testWidgets('partial coverage labels known values and unknown costs',
      (tester) async {
    final profit = _FakeProfitabilityService()
      ..put(_snapshot(today,
          net: 5400000, cogs: 4729000, unknownCount: 2, unknownNet: 250000));
    await _pumpScreen(tester, profit: profit, now: now);
    await _tapProfitability(tester);
    expect(find.text('Rentabilidad parcial'), findsOneWidget);
    expect(find.textContaining('Hay ventas con costo desconocido'),
        findsOneWidget);
    expect(find.text('Utilidad bruta conocida'), findsOneWidget);
    expect(find.text('Margen bruto conocido'), findsOneWidget);
    expect(find.text('Utilidad bruta'), findsNothing);
    expect(find.text('Ítems sin costo'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Ventas asociadas a costo desconocido'), findsOneWidget);
    expect(find.text(r'$2.500'), findsOneWidget);
    expect(find.text('Cobertura de costos completa'), findsNothing);
  });

  testWidgets('empty period renders monetary zero and null margin as dash',
      (tester) async {
    final profit = _FakeProfitabilityService()
      ..put(_snapshot(today, net: 0, cogs: 0));
    await _pumpScreen(tester, profit: profit, now: now);
    await _tapProfitability(tester);
    expect(find.text(r'$0'), findsNWidgets(3));
    expect(find.text('—'), findsOneWidget);
    expect(find.text('0,00 %'), findsNothing);
  });

  testWidgets('sales-only permission hides profitability without reading it',
      (tester) async {
    final profit = _FakeProfitabilityService()
      ..put(_snapshot(today, net: 5400000, cogs: 4729000));
    final sales = _FakeSalesReportService();
    await _pumpScreen(tester,
        profit: profit,
        sales: sales,
        now: now,
        permissions: const {'reports.sales'});
    expect(find.text('Rentabilidad'), findsNothing);
    expect(find.byKey(const Key('report-view-selector')), findsNothing);
    expect(find.text('Reporte no disponible sin conexión'), findsOneWidget);
    expect(find.text(r'$54.000'), findsNothing);
    expect(sales.readScopes, hasLength(1));
    expect(profit.readScopes, isEmpty);
  });

  testWidgets('permission loss while viewing clears sensitive presentation',
      (tester) async {
    final profit = _FakeProfitabilityService()
      ..put(_snapshot(today, net: 5400000, cogs: 4729000));
    final sales = _FakeSalesReportService();
    await tester
        .pumpWidget(_screenTree(profit: profit, sales: sales, now: now));
    await tester.pumpAndSettle();
    await _tapProfitability(tester);
    expect(find.text(r'$54.000'), findsOneWidget);
    await tester.pumpWidget(_screenTree(
      profit: profit,
      sales: sales,
      now: now,
      permissions: const {'reports.sales'},
    ));
    await tester.pumpAndSettle();
    expect(find.text('Rentabilidad'), findsNothing);
    expect(find.text(r'$54.000'), findsNothing);
    expect(
        find.byKey(const Key('profitability-report-known-cogs')), findsNothing);
  });

  testWidgets('reactive local revocation hides an already loaded cost report',
      (tester) async {
    final access = StreamController<bool>.broadcast();
    addTearDown(access.close);
    final profit = _FakeProfitabilityService()
      ..put(_snapshot(today, net: 5400000, cogs: 4729000));
    await tester.pumpWidget(_screenTree(
      profit: profit,
      sales: _FakeSalesReportService(),
      now: now,
      presentationAccess: access.stream,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rentabilidad'));
    await tester.pump();
    access.add(true);
    await tester.pumpAndSettle();
    expect(find.text(r'$54.000'), findsOneWidget);
    access.add(false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profitability-report-unauthorized')),
        findsOneWidget);
    expect(find.text(r'$54.000'), findsNothing);
  });

  testWidgets('without reports.sales the existing sales gate stays closed',
      (tester) async {
    final profit = _FakeProfitabilityService();
    final sales = _FakeSalesReportService();
    await _pumpScreen(tester,
        profit: profit,
        sales: sales,
        now: now,
        permissions: const {'sales.view_costs'});
    await tester.pumpAndSettle();
    expect(find.text('Reporte no autorizado'), findsOneWidget);
    expect(find.text('Rentabilidad'), findsNothing);
    expect(sales.readScopes, isEmpty);
    expect(profit.readScopes, isEmpty);
  });

  testWidgets('both views share the selected preset and UTC period',
      (tester) async {
    final seven = salesReportPeriodFor(SalesReportPreset.lastSevenDays, now);
    final profit = _FakeProfitabilityService()
      ..put(_snapshot(today, net: 5400000, cogs: 4729000))
      ..put(_snapshot(seven, net: 3000000, cogs: 2000000));
    await _pumpScreen(tester, profit: profit, now: now);
    await _tapProfitability(tester);
    expect(find.text(r'$54.000'), findsOneWidget);
    await tester.tap(find.text('Últimos 7 días'));
    await tester.pumpAndSettle();
    expect(find.text(r'$30.000'), findsOneWidget);
    expect(profit.readScopes.last.period.filterKey, seven.filterKey);
    await tester.tap(find.text('Ventas'));
    await tester.pumpAndSettle();
    await _tapProfitability(tester);
    expect(profit.readScopes.last.period.filterKey, seven.filterKey);
  });

  testWidgets('custom range persists across tabs and canceled picker',
      (tester) async {
    final custom = salesReportPeriodForDates(
      startDate: DateTime(2026, 8, 25),
      endDate: DateTime(2026, 8, 31),
    );
    final profit = _FakeProfitabilityService()
      ..put(_snapshot(custom, net: 600000, cogs: 200000));
    await _pumpScreen(tester, profit: profit, now: now);
    await _selectCustomRange(
        tester, DateTime(2026, 8, 25), DateTime(2026, 8, 31));
    await _tapProfitability(tester);
    expect(find.text('25/08/2026 – 31/08/2026'), findsOneWidget);
    expect(find.text(r'$6.000'), findsOneWidget);
    expect(profit.readScopes.last.period.filterKey, custom.filterKey);
    final reads = profit.readScopes.length;
    await tester.tap(find.text('Personalizado'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    final pickerContext = tester.element(find.byType(DateRangePickerDialog));
    final inputModeLabel =
        MaterialLocalizations.of(pickerContext).inputDateModeButtonLabel;
    await tester.tap(find.byTooltip(inputModeLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('25/08/2026 – 31/08/2026'), findsOneWidget);
    expect(find.text(r'$6.000'), findsOneWidget);
    expect(profit.readScopes, hasLength(reads));
  });

  testWidgets('offline cache and offline unavailable stay distinct',
      (tester) async {
    final profit = _FakeProfitabilityService()
      ..put(_snapshot(today, net: 5400000, cogs: 4729000));
    await _pumpScreen(tester, profit: profit, now: now);
    await _tapProfitability(tester);
    expect(find.text('Sin conexión · mostrando último reporte guardado'),
        findsOneWidget);
    await tester.tap(find.text('Últimos 7 días'));
    await tester.pumpAndSettle();
    expect(find.text('Reporte no disponible sin conexión'), findsOneWidget);
    expect(find.text(r'$54.000'), findsNothing);
  });

  testWidgets('network warning preserves cache; unauthorized clears it',
      (tester) async {
    final cached = _snapshot(today, net: 5400000, cogs: 4729000);
    final profit = _FakeProfitabilityService()
      ..put(cached)
      ..onRefresh = (_) async => ProfitabilityRefreshResult(
            outcome: ProfitabilityRefreshOutcome.remoteFailure,
            preservedCache: cached,
          );
    await _pumpScreen(tester, profit: profit, now: now, online: true);
    await _tapProfitability(tester);
    expect(find.text(r'$54.000'), findsOneWidget);
    expect(find.text('No se pudo actualizar · mostrando datos guardados'),
        findsOneWidget);
    profit.onRefresh = (_) async => const ProfitabilityRefreshResult(
          outcome: ProfitabilityRefreshOutcome.unauthorized,
        );
    await tester.tap(find.byKey(const Key('sales-report-refresh')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profitability-report-unauthorized')),
        findsOneWidget);
    expect(find.text(r'$54.000'), findsNothing);
  });

  testWidgets('switching branch never displays the prior branch snapshot',
      (tester) async {
    final profit = _FakeProfitabilityService()
      ..put(_snapshot(today, net: 5400000, cogs: 4729000))
      ..put(_snapshot(today, branchId: 'branch-b', net: 300000, cogs: 200000));
    final sales = _FakeSalesReportService();
    await tester.pumpWidget(_screenTree(
        profit: profit, sales: sales, now: now, branchId: 'branch-a'));
    await tester.pumpAndSettle();
    await _tapProfitability(tester);
    expect(find.text(r'$54.000'), findsOneWidget);
    await tester.pumpWidget(_screenTree(
        profit: profit, sales: sales, now: now, branchId: 'branch-b'));
    await tester.pumpAndSettle();
    expect(find.text(r'$3.000'), findsOneWidget);
    expect(find.text(r'$54.000'), findsNothing);
    expect(profit.readScopes.last.branchId, 'branch-b');
  });

  test('margin formatting does not round the exact model', () {
    final ratio = ExactProfitabilityMargin(
      BigInt.from(671000),
      BigInt.from(5400000),
    );
    expect(formatProfitabilityMargin(ratio), '12,43 %');
    expect(ratio.numerator, BigInt.from(671000));
    expect(formatProfitabilityMargin(null), '—');
  });
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeProfitabilityService profit,
  required DateTime now,
  _FakeSalesReportService? sales,
  bool online = false,
  Set<String> permissions = const {'reports.sales', 'sales.view_costs'},
}) async {
  await tester.pumpWidget(_screenTree(
    profit: profit,
    sales: sales ?? _FakeSalesReportService(),
    now: now,
    online: online,
    permissions: permissions,
  ));
  await tester.pumpAndSettle();
}

Widget _screenTree({
  required _FakeProfitabilityService profit,
  required _FakeSalesReportService sales,
  required DateTime now,
  bool online = false,
  String branchId = 'branch-a',
  Set<String> permissions = const {'reports.sales', 'sales.view_costs'},
  Stream<bool>? presentationAccess,
}) =>
    ProviderScope(
      overrides: [
        profitabilityPresentationAccessProvider.overrideWith(
          (ref, request) => presentationAccess ?? Stream.value(true),
        ),
        profitabilityReportServiceProvider.overrideWithValue(profit),
        salesReportServiceProvider.overrideWithValue(sales),
        salesReportOnlineCheckProvider.overrideWithValue(() async => online),
        salesReportClockProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        home: SalesReportScreen(
          profileId: 'profile-a',
          businessId: 'business-a',
          branchId: branchId,
          branchName: branchId,
          effectivePermissions: permissions,
          authorizationContextReady: true,
        ),
      ),
    );

Future<void> _tapProfitability(WidgetTester tester) async {
  await tester.tap(find.text('Rentabilidad'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _selectCustomRange(
    WidgetTester tester, DateTime start, DateTime end) async {
  await tester.tap(find.text('Personalizado'));
  await tester.pumpAndSettle();
  final element = tester.element(find.byType(DateRangePickerDialog));
  final mode = MaterialLocalizations.of(element).inputDateModeButtonLabel;
  await tester.tap(find.byTooltip(mode));
  await tester.pumpAndSettle();
  final localization = MaterialLocalizations.of(
      tester.element(find.byType(DateRangePickerDialog)));
  await tester.enterText(
      find.byType(TextField).at(0), localization.formatCompactDate(start));
  await tester.enterText(
      find.byType(TextField).at(1), localization.formatCompactDate(end));
  await tester.tap(find.text('Aplicar'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

ProfitabilityReportSnapshot _snapshot(
  SalesReportPeriod period, {
  required int net,
  required int cogs,
  String branchId = 'branch-a',
  int unknownCount = 0,
  int unknownNet = 0,
}) =>
    ProfitabilityReportSnapshot(
      summary: ProfitabilityReportSummary(
        businessId: 'business-a',
        branchId: branchId,
        periodFrom: period.from,
        periodTo: period.to,
        knownNetSalesCents: BigInt.from(net),
        knownCogsCents: BigInt.from(cogs),
        knownGrossProfitCents: BigInt.from(net - cogs),
        unknownCostItemCount: unknownCount,
        unknownCostNetSalesCents: BigInt.from(unknownNet),
        costCoverageComplete: unknownCount == 0,
        authoritativeAsOf: DateTime.utc(2026, 9, 23),
      ),
      fetchedAt: DateTime.utc(2026, 9, 23),
      authorizationValidatedAt: DateTime.utc(2026, 9, 23),
      capabilityFingerprint: 'reports.sales\u001fsales.view_costs',
      includesSensitiveData: true,
      includesCosts: true,
    );

class _FakeProfitabilityService implements ProfitabilityReportService {
  final Map<String, ProfitabilityReportSnapshot> cache = {};
  final List<SalesReportScope> readScopes = [];
  Future<ProfitabilityRefreshResult> Function(SalesReportScope)? onRefresh;

  void put(ProfitabilityReportSnapshot snapshot) {
    cache['${snapshot.summary.branchId}|'
            '${SalesReportPeriod(from: snapshot.summary.periodFrom, to: snapshot.summary.periodTo).filterKey}'] =
        snapshot;
  }

  @override
  Future<ProfitabilityCacheReadResult> readCached(
      SalesReportScope scope) async {
    readScopes.add(scope);
    final snapshot = cache['${scope.branchId}|${scope.period.filterKey}'];
    return ProfitabilityCacheReadResult(
      outcome: snapshot == null
          ? ProfitabilityCacheReadOutcome.noCache
          : ProfitabilityCacheReadOutcome.available,
      snapshot: snapshot,
    );
  }

  @override
  Future<ProfitabilityRefreshResult> refresh(SalesReportScope scope) =>
      onRefresh?.call(scope) ??
      Future.value(const ProfitabilityRefreshResult(
        outcome: ProfitabilityRefreshOutcome.remoteFailure,
      ));
}

class _FakeSalesReportService implements SalesReportService {
  final List<SalesReportScope> readScopes = [];

  @override
  Future<SalesReportCacheReadResult> readCached(SalesReportScope scope) async {
    readScopes.add(scope);
    return const SalesReportCacheReadResult(
      outcome: SalesReportCacheReadOutcome.noCache,
    );
  }

  @override
  Future<SalesReportRefreshResult> refresh(SalesReportScope scope) async =>
      const SalesReportRefreshResult(
        outcome: SalesReportRefreshOutcome.remoteFailure,
      );
}
