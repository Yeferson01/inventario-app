import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/app/theme/dark_theme.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_controller.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_providers.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_service.dart';
import 'package:inventario_frontend/features/reports/data/datasources/sales_report_remote_datasource.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';
import 'package:inventario_frontend/features/reports/presentation/screens/sales_report_screen.dart';

void main() {
  final now = DateTime(2026, 9, 23, 14, 30);

  test('presets use local calendar boundaries converted to UTC and [from,to)',
      () {
    final today = salesReportPeriodFor(SalesReportPreset.today, now);
    final sevenDays =
        salesReportPeriodFor(SalesReportPreset.lastSevenDays, now);
    final month = salesReportPeriodFor(SalesReportPreset.thisMonth, now);

    expect(today.from, DateTime(2026, 9, 23).toUtc());
    expect(today.to, DateTime(2026, 9, 24).toUtc());
    expect(sevenDays.from, DateTime(2026, 9, 17).toUtc());
    expect(sevenDays.to, DateTime(2026, 9, 24).toUtc());
    expect(month.from, DateTime(2026, 9).toUtc());
    expect(month.to, DateTime(2026, 10).toUtc());
  });

  testWidgets('cached snapshot is visible before online refresh completes',
      (tester) async {
    final period = salesReportPeriodFor(SalesReportPreset.today, now);
    final refresh = Completer<SalesReportRefreshResult>();
    final service = _FakeSalesReportService(
      cache: {period.filterKey: _snapshot(period, gross: 1234, count: 1)},
      onRefresh: (_) => refresh.future,
    );

    await _pumpScreen(tester, service: service, now: now, isOnline: true);
    await tester.pump();
    await tester.pump();

    expect(
      find.descendant(
        of: find.byKey(const Key('sales-report-gross-sales')),
        matching: find.text(r'$12,34'),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('sales-report-loading')), findsNothing);
    expect(service.refreshCalls, 1);

    refresh.complete(
      SalesReportRefreshResult(
        outcome: SalesReportRefreshOutcome.refreshed,
        snapshot: _snapshot(period, gross: 1234, count: 1),
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('successful refresh replaces cached metrics', (tester) async {
    final period = salesReportPeriodFor(SalesReportPreset.today, now);
    final service = _FakeSalesReportService(
      cache: {period.filterKey: _snapshot(period, gross: 100, count: 1)},
      onRefresh: (_) async => SalesReportRefreshResult(
        outcome: SalesReportRefreshOutcome.refreshed,
        snapshot: _snapshot(period, gross: 987654, count: 3),
      ),
    );

    await _pumpScreen(tester, service: service, now: now, isOnline: true);
    await tester.pumpAndSettle();

    expect(find.text(r'$9.876,54'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text(r'$1'), findsNothing);
  });

  testWidgets('network refresh failure preserves cache with notice',
      (tester) async {
    final period = salesReportPeriodFor(SalesReportPreset.today, now);
    final cached = _snapshot(period, gross: 4321, count: 1);
    final service = _FakeSalesReportService(
      cache: {period.filterKey: cached},
      onRefresh: (_) async => SalesReportRefreshResult(
        outcome: SalesReportRefreshOutcome.remoteFailure,
        preservedCache: cached,
        failureKind: SalesReportRemoteFailureKind.network,
      ),
    );

    await _pumpScreen(tester, service: service, now: now, isOnline: true);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('sales-report-gross-sales')),
        matching: find.text(r'$43,21'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('No se pudo actualizar · mostrando datos guardados'),
      findsOneWidget,
    );
  });

  testWidgets('offline with cache shows metrics and offline notice',
      (tester) async {
    final period = salesReportPeriodFor(SalesReportPreset.today, now);
    final service = _FakeSalesReportService(
      cache: {period.filterKey: _snapshot(period, gross: 5000, count: 2)},
    );

    await _pumpScreen(tester, service: service, now: now, isOnline: false);
    await tester.pumpAndSettle();

    expect(find.text(r'$50'), findsOneWidget);
    expect(
      find.text('Sin conexión · mostrando último reporte guardado'),
      findsOneWidget,
    );
    expect(service.refreshCalls, 0);
  });

  testWidgets('offline without cache shows unavailable instead of zeroes',
      (tester) async {
    final service = _FakeSalesReportService();

    await _pumpScreen(tester, service: service, now: now, isOnline: false);
    await tester.pumpAndSettle();

    expect(find.text('Reporte no disponible sin conexión'), findsOneWidget);
    expect(find.byKey(const Key('sales-report-gross-sales')), findsNothing);
  });

  testWidgets('zero sales is valid and null average uses an em dash',
      (tester) async {
    final period = salesReportPeriodFor(SalesReportPreset.today, now);
    final service = _FakeSalesReportService(
      cache: {
        period.filterKey: _snapshot(
          period,
          gross: 0,
          count: 0,
          average: null,
        ),
      },
    );

    await _pumpScreen(tester, service: service, now: now, isOnline: false);
    await tester.pumpAndSettle();

    expect(find.text(r'$0'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
  });

  testWidgets('changing Today to 7 days reads a distinct filter cache',
      (tester) async {
    final today = salesReportPeriodFor(SalesReportPreset.today, now);
    final seven = salesReportPeriodFor(SalesReportPreset.lastSevenDays, now);
    final service = _FakeSalesReportService(
      cache: {
        today.filterKey: _snapshot(today, gross: 100, count: 1),
        seven.filterKey: _snapshot(seven, gross: 700, count: 7),
      },
    );

    await _pumpScreen(tester, service: service, now: now, isOnline: false);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(const Key('sales-report-gross-sales')),
        matching: find.text(r'$1'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Últimos 7 días'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('sales-report-gross-sales')),
        matching: find.text(r'$7'),
      ),
      findsOneWidget,
    );
    expect(service.readScopes.map((scope) => scope.period.filterKey),
        containsAll(<String>[today.filterKey, seven.filterKey]));
  });

  testWidgets('preset without offline cache never retains previous metrics',
      (tester) async {
    final today = salesReportPeriodFor(SalesReportPreset.today, now);
    final service = _FakeSalesReportService(
      cache: {today.filterKey: _snapshot(today, gross: 100, count: 1)},
    );

    await _pumpScreen(tester, service: service, now: now, isOnline: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Últimos 7 días'));
    await tester.pumpAndSettle();

    expect(find.text('Reporte no disponible sin conexión'), findsOneWidget);
    expect(find.text(r'$1'), findsNothing);
  });

  testWidgets('unauthorized request does not read or reveal cached data',
      (tester) async {
    final period = salesReportPeriodFor(SalesReportPreset.today, now);
    final service = _FakeSalesReportService(
      cache: {period.filterKey: _snapshot(period, gross: 9999, count: 1)},
    );

    await _pumpScreen(
      tester,
      service: service,
      now: now,
      isOnline: false,
      permissions: const {'sales.read'},
    );
    await tester.pumpAndSettle();

    expect(find.text('Reporte no autorizado'), findsOneWidget);
    expect(find.text(r'$99,99'), findsNothing);
    expect(service.readCalls, 0);
  });

  testWidgets('authoritative unauthorized refresh removes visible cache',
      (tester) async {
    final period = salesReportPeriodFor(SalesReportPreset.today, now);
    final service = _FakeSalesReportService(
      cache: {period.filterKey: _snapshot(period, gross: 9999, count: 1)},
      onRefresh: (_) async => const SalesReportRefreshResult(
        outcome: SalesReportRefreshOutcome.unauthorized,
      ),
    );

    await _pumpScreen(tester, service: service, now: now, isOnline: true);
    await tester.pumpAndSettle();

    expect(find.text('Reporte no autorizado'), findsOneWidget);
    expect(find.text(r'$99,99'), findsNothing);
  });

  test('money formatter preserves large and fractional cent values', () {
    expect(
      formatSalesReportMoney(BigInt.parse('123456789012345678901')),
      r'$1.234.567.890.123.456.789,01',
    );
    expect(formatSalesReportMoney(BigInt.from(100)), r'$1');
    expect(formatSalesReportMoney(BigInt.from(105)), r'$1,05');
  });

  test('refresh is single-flight', () async {
    var online = false;
    final refreshCompleter = Completer<SalesReportRefreshResult>();
    final service = _FakeSalesReportService(
      onRefresh: (_) => refreshCompleter.future,
    );
    final container = ProviderContainer(
      overrides: [
        salesReportServiceProvider.overrideWithValue(service),
        salesReportOnlineCheckProvider.overrideWithValue(() async => online),
        salesReportClockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(container.dispose);
    final request = _request();
    final subscription = container.listen(
      salesReportControllerProvider(request),
      (_, __) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    await _flushAsync();

    online = true;
    final controller = container.read(
      salesReportControllerProvider(request).notifier,
    );
    final first = controller.refresh();
    final second = controller.refresh();
    await _flushAsync();

    expect(service.refreshCalls, 1);

    refreshCompleter.complete(
      const SalesReportRefreshResult(
        outcome: SalesReportRefreshOutcome.remoteFailure,
      ),
    );
    await Future.wait([first, second]);
  });

  testWidgets(
      'Personalizado opens Material picker; cancel preserves preset and metrics',
      (tester) async {
    final period = salesReportPeriodFor(SalesReportPreset.today, now);
    final service = _FakeSalesReportService(
      cache: {period.filterKey: _snapshot(period, gross: 5000, count: 2)},
    );
    await _pumpScreen(tester, service: service, now: now, isOnline: false);
    await tester.pumpAndSettle();
    final previousLabel = tester
        .widget<Text>(
          find.byKey(const Key('sales-report-period')),
        )
        .data;
    final previousReads = service.readCalls;
    await tester.tap(find.text('Personalizado'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    final picker = tester
        .widget<DateRangePickerDialog>(find.byType(DateRangePickerDialog));
    expect(picker.initialDateRange!.start, DateTime(2026, 9, 23));
    expect(picker.initialDateRange!.end, DateTime(2026, 9, 23));
    await _switchPickerToInput(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text(previousLabel!), findsOneWidget);
    expect(find.text(r'$50'), findsOneWidget);
    expect(
        tester
            .widget<ChoiceChip>(
                find.byKey(const Key('sales-report-preset-today')))
            .selected,
        isTrue);
    expect(service.readCalls, previousReads);
    expect(service.refreshCalls, 0);
    expect(service.readScopes.single.period.filterKey, period.filterKey);
  });

  testWidgets('tablet landscape accepts the calendar range without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeSalesReportService();
    await _pumpScreen(tester,
        service: service, now: now, isOnline: false, useDarkAppTheme: true);
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('Sucursal Principal'))).brightness,
        Brightness.light);
    await tester.tap(find.text('Personalizado'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    expect(tester.takeException(), null);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), null);
    expect(find.byType(DateRangePickerDialog), findsNothing);
  });

  testWidgets('tablet portrait accepts the calendar range without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = _FakeSalesReportService();
    await _pumpScreen(tester,
        service: service, now: now, isOnline: false, useDarkAppTheme: true);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personalizado'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(find.byType(DateRangePickerDialog), findsNothing);
    expect(tester.takeException(), null);
  });

  testWidgets(
      'custom picker submits inclusive range, shows offline cache, and reopens same range',
      (tester) async {
    final custom = salesReportPeriodForDates(
      startDate: DateTime(2026, 8, 25),
      endDate: DateTime(2026, 8, 31),
    );
    final service = _FakeSalesReportService(
      cache: {custom.filterKey: _snapshot(custom, gross: 150000, count: 2)},
    );
    await _pumpScreen(tester, service: service, now: now, isOnline: false);
    await tester.pumpAndSettle();
    await _chooseCustomRange(
        tester, DateTime(2026, 8, 25), DateTime(2026, 8, 31));
    expect(find.text('25/08/2026 – 31/08/2026'), findsOneWidget);
    expect(find.text(r'$1.500'), findsOneWidget);
    expect(find.text('Sin conexión · mostrando último reporte guardado'),
        findsOneWidget);
    expect(service.readScopes.last.period.filterKey, custom.filterKey);

    await tester.tap(find.text('Personalizado'));
    await tester.pumpAndSettle();
    final picker = tester
        .widget<DateRangePickerDialog>(find.byType(DateRangePickerDialog));
    expect(picker.initialDateRange!.start, DateTime(2026, 8, 25));
    expect(picker.initialDateRange!.end, DateTime(2026, 8, 31));
    final previousReads = service.readCalls;
    await _switchPickerToInput(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('25/08/2026 – 31/08/2026'), findsOneWidget);
    expect(find.text(r'$1.500'), findsOneWidget);
    expect(service.readCalls, previousReads);
  });

  testWidgets(
      'uncached single-day custom selection shows one inclusive date and offline unavailable',
      (tester) async {
    final service = _FakeSalesReportService();
    await _pumpScreen(tester, service: service, now: now, isOnline: false);
    await tester.pumpAndSettle();
    await _chooseCustomRange(
        tester, DateTime(2026, 8, 25), DateTime(2026, 8, 25));
    expect(find.text('25/08/2026'), findsOneWidget);
    expect(find.text('26/08/2026'), findsNothing);
    expect(find.text('Reporte no disponible sin conexión'), findsOneWidget);
    expect(find.byKey(const Key('sales-report-gross-sales')), findsNothing);
    expect(service.refreshCalls, 0);
  });

  testWidgets('custom selection cannot bypass reports.sales permission',
      (tester) async {
    final service = _FakeSalesReportService();
    await _pumpScreen(
      tester,
      service: service,
      now: now,
      isOnline: true,
      permissions: const {'sales.read'},
    );
    await tester.pumpAndSettle();
    await _chooseCustomRange(tester, DateTime(2026, 8), DateTime(2026, 8, 31));
    expect(find.text('Reporte no autorizado'), findsOneWidget);
    expect(service.readCalls, 0);
    expect(service.refreshCalls, 0);
  });

  test('presentation screen has no direct Drift or Supabase dependency', () {
    final source = File(
      'lib/features/reports/presentation/screens/sales_report_screen.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('package:drift/')));
    expect(source, isNot(contains('package:supabase_flutter/')));
    expect(source, isNot(contains('ReportSnapshotLocalDao')));
    expect(source, isNot(contains('SalesReportRemoteDatasource')));
  });
}

Future<void> _switchPickerToInput(WidgetTester tester) async {
  final element = tester.element(find.byType(DateRangePickerDialog));
  final label = MaterialLocalizations.of(element).inputDateModeButtonLabel;
  await tester.tap(find.byTooltip(label));
  await tester.pumpAndSettle();
}

Future<void> _chooseCustomRange(
    WidgetTester tester, DateTime start, DateTime end) async {
  await tester.tap(find.text('Personalizado'));
  await tester.pumpAndSettle();
  await _switchPickerToInput(tester);
  final localization = MaterialLocalizations.of(
    tester.element(find.byType(DateRangePickerDialog)),
  );
  await tester.enterText(
      find.byType(TextField).at(0), localization.formatCompactDate(start));
  await tester.enterText(
      find.byType(TextField).at(1), localization.formatCompactDate(end));
  await tester.tap(find.text('Aplicar'));
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  expect(find.byType(DateRangePickerDialog), findsNothing);
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeSalesReportService service,
  required DateTime now,
  required bool isOnline,
  Set<String> permissions = const {salesReportCapability},
  bool useDarkAppTheme = false,
}) async {
  Widget app() => MaterialApp(
        theme: useDarkAppTheme ? AppDarkTheme.theme : null,
        home: SalesReportScreen(
          profileId: 'profile-1',
          businessId: 'business-1',
          branchId: 'branch-1',
          branchName: 'Sucursal Principal',
          effectivePermissions: permissions,
          authorizationContextReady: true,
          authorizationValidatedAt: DateTime.utc(2026, 9, 23, 12),
        ),
      );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        salesReportServiceProvider.overrideWithValue(service),
        salesReportOnlineCheckProvider.overrideWithValue(() async => isOnline),
        salesReportClockProvider.overrideWithValue(() => now),
      ],
      child: useDarkAppTheme
          ? ScreenUtilInit(
              designSize: const Size(390, 844),
              minTextAdapt: true,
              builder: (context, child) => app(),
            )
          : app(),
    ),
  );
}

SalesReportViewRequest _request() {
  return SalesReportViewRequest(
    profileId: 'profile-1',
    businessId: 'business-1',
    branchId: 'branch-1',
    branchName: 'Sucursal Principal',
    effectivePermissions: const {salesReportCapability},
    authorizationContextReady: true,
    authorizationValidatedAt: DateTime.utc(2026, 9, 23, 12),
  );
}

SalesReportSnapshot _snapshot(
  SalesReportPeriod period, {
  required int gross,
  required int count,
  int? average,
}) {
  return SalesReportSnapshot(
    summary: SalesReportSummary(
      businessId: 'business-1',
      branchId: 'branch-1',
      periodFrom: period.from,
      periodTo: period.to,
      grossSalesCents: BigInt.from(gross),
      saleCount: count,
      averageTicketCents:
          count == 0 ? null : BigInt.from(average ?? (gross ~/ count)),
      authoritativeAsOf: DateTime.utc(2026, 9, 23, 18),
    ),
    fetchedAt: DateTime.utc(2026, 9, 23, 18),
    authorizationValidatedAt: DateTime.utc(2026, 9, 23, 12),
    capabilityFingerprint: salesReportCapability,
    includesSensitiveData: false,
    includesCosts: false,
  );
}

class _FakeSalesReportService implements SalesReportService {
  _FakeSalesReportService({
    Map<String, SalesReportSnapshot>? cache,
    Future<SalesReportRefreshResult> Function(SalesReportScope scope)?
        onRefresh,
  })  : cache = cache ?? {},
        _onRefresh = onRefresh;

  final Map<String, SalesReportSnapshot> cache;
  final Future<SalesReportRefreshResult> Function(SalesReportScope scope)?
      _onRefresh;
  final List<SalesReportScope> readScopes = [];
  int readCalls = 0;
  int refreshCalls = 0;

  @override
  Future<SalesReportCacheReadResult> readCached(
    SalesReportScope scope,
  ) async {
    readCalls += 1;
    readScopes.add(scope);
    final snapshot = cache[scope.period.filterKey];
    return SalesReportCacheReadResult(
      outcome: snapshot == null
          ? SalesReportCacheReadOutcome.noCache
          : SalesReportCacheReadOutcome.available,
      snapshot: snapshot,
    );
  }

  @override
  Future<SalesReportRefreshResult> refresh(SalesReportScope scope) {
    refreshCalls += 1;
    return _onRefresh?.call(scope) ??
        Future.value(
          const SalesReportRefreshResult(
            outcome: SalesReportRefreshOutcome.remoteFailure,
          ),
        );
  }
}

Future<void> _flushAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
