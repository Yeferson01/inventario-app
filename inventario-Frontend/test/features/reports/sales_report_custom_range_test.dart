import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_controller.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_providers.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_service.dart';
import 'package:inventario_frontend/features/reports/data/datasources/report_snapshot_local_dao.dart';
import 'package:inventario_frontend/features/reports/data/datasources/sales_report_remote_datasource.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';

void main() {
  final examples = [
    (
      'one day',
      DateTime(2026, 8, 25),
      DateTime(2026, 8, 25),
      DateTime(2026, 8, 26)
    ),
    (
      'last August week',
      DateTime(2026, 8, 25),
      DateTime(2026, 8, 31),
      DateTime(2026, 9)
    ),
    (
      'full August',
      DateTime(2026, 8),
      DateTime(2026, 8, 31),
      DateTime(2026, 9)
    ),
    ('full 2025', DateTime(2025), DateTime(2025, 12, 31), DateTime(2026)),
  ];
  for (final (name, start, end, exclusiveEnd) in examples) {
    test('$name becomes inclusive local dates and exclusive UTC bounds', () {
      final period = salesReportPeriodForDates(startDate: start, endDate: end);
      expect(period.from, start.toUtc());
      expect(period.to, exclusiveEnd.toUtc());
      expect(period.from.isUtc, isTrue);
      expect(period.to.isUtc, isTrue);
      expect(period.from.toLocal(), start);
      expect(period.to.toLocal(), exclusiveEnd);
    });
  }

  test('same calendar range canonicalizes time and uses the existing key', () {
    final first = salesReportPeriodForDates(
      startDate: DateTime(2026, 8, 25, 14),
      endDate: DateTime(2026, 8, 31, 23),
    );
    final second = salesReportPeriodForDates(
      startDate: DateTime(2026, 8, 25),
      endDate: DateTime(2026, 8, 31),
    );
    final existing = SalesReportPeriod(
      from: DateTime(2026, 8, 25).toUtc(),
      to: DateTime(2026, 9).toUtc(),
    );
    expect(first.filterKey, second.filterKey);
    expect(first.filterKey, existing.filterKey);
  });

  test('different calendar ranges have different keys', () {
    final full = salesReportPeriodForDates(
      startDate: DateTime(2026, 8),
      endDate: DateTime(2026, 8, 31),
    );
    final week = salesReportPeriodForDates(
      startDate: DateTime(2026, 8, 25),
      endDate: DateTime(2026, 8, 31),
    );
    expect(full.filterKey, isNot(week.filterKey));
  });

  group('custom controller with real service and in-memory snapshot DAO', () {
    late AppDatabase database;
    late AuthorizedOperationalContextLocalDao auth;
    late ReportSnapshotLocalDao snapshots;
    late ProviderContainer container;
    late SalesReportViewRequest request;
    late SalesReportController controller;
    late bool online;
    late bool networkFailure;
    late String gross;
    late List<Map<String, Object?>> rpcCalls;
    Future<void> Function()? beforeResponse;

    Future<void> authorize(List<String> permissions) => auth.replaceContext(
          AuthorizedOperationalContextProjection(
            profileId: 'profile-a',
            businessId: 'business-a',
            branchId: 'branch-a',
            effectivePermissions: permissions,
            effectiveRoles: const ['custom-role'],
            applicableMembershipIds: const ['membership-a'],
            authorizationValidatedAt: DateTime.utc(2026, 9, 24),
            snapshotId: 'core',
            status: 'active',
          ),
        );

    SalesReportScreenState current() =>
        container.read(salesReportControllerProvider(request));

    Future<bool> select(int firstDay, [int lastDay = 31]) =>
        controller.selectCustomRange(
          startDate: DateTime(2026, 8, firstDay),
          endDate: DateTime(2026, 8, lastDay),
        );

    setUp(() async {
      database = AppDatabase.executor(NativeDatabase.memory());
      auth = AuthorizedOperationalContextLocalDao(database);
      snapshots = ReportSnapshotLocalDao(database);
      online = false;
      networkFailure = false;
      gross = '1500.50';
      beforeResponse = null;
      rpcCalls = [];
      await authorize(const ['reports.sales']);
      final service = SalesReportService(
        authenticatedProfileId: () => 'profile-a',
        authorizationDao: auth,
        snapshotDao: snapshots,
        remoteDatasource:
            SalesReportRemoteDatasource.withInvoker((params) async {
          rpcCalls.add(params);
          await beforeResponse?.call();
          if (networkFailure) throw const SocketException('offline');
          return [
            {
              'business_id': params['p_business_id'],
              'branch_id': params['p_branch_id'],
              'period_from': params['p_from'],
              'period_to': params['p_to'],
              'gross_sales': gross,
              'sale_count': 1,
              'average_ticket': gross,
              'authoritative_as_of': '2026-09-24T12:00:00Z',
            },
          ];
        }),
      );
      container = ProviderContainer(overrides: [
        salesReportServiceProvider.overrideWithValue(service),
        salesReportOnlineCheckProvider.overrideWithValue(() async => online),
        salesReportClockProvider.overrideWithValue(() => DateTime(2026, 9, 24)),
      ]);
      request = SalesReportViewRequest(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: 'branch-a',
        branchName: 'Principal',
        effectivePermissions: const ['reports.sales'],
        authorizationContextReady: true,
      );
      final initialized = Completer<void>();
      container.listen(salesReportControllerProvider(request), (_, next) {
        if (next.phase != SalesReportScreenPhase.initialLoading &&
            !initialized.isCompleted) {
          initialized.complete();
        }
      }, fireImmediately: true);
      controller =
          container.read(salesReportControllerProvider(request).notifier);
      await initialized.future;
    });

    tearDown(() async {
      container.dispose();
      await database.close();
    });

    test('online custom refresh persists the exact scope and UTC snapshot',
        () async {
      online = true;
      await select(25);
      final state = current();
      expect(state.preset, SalesReportPreset.custom);
      expect(state.selectedStartDate, DateTime(2026, 8, 25));
      expect(state.selectedEndDate, DateTime(2026, 8, 31));
      expect(rpcCalls.single['p_from'],
          DateTime(2026, 8, 25).toUtc().toIso8601String());
      expect(
          rpcCalls.single['p_to'], DateTime(2026, 9).toUtc().toIso8601String());
      final cached = await snapshots.readSalesSummary(SalesReportScope(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
        period: state.period,
      ));
      expect(cached!.summary.grossSalesCents, BigInt.from(150050));
    });

    test('previously fetched custom range is available offline', () async {
      online = true;
      await select(1);
      online = false;
      await controller.selectPreset(SalesReportPreset.today);
      await select(1);
      expect(current().phase, SalesReportScreenPhase.ready);
      expect(current().snapshot!.summary.grossSalesCents, BigInt.from(150050));
      expect(current().notice, SalesReportScreenNotice.offlineCache);
      expect(rpcCalls, hasLength(1));
    });

    test(
        'uncached custom range is unavailable offline without fabricated totals',
        () async {
      await select(25);
      expect(current().phase, SalesReportScreenPhase.unavailableOffline);
      expect(current().snapshot, isNull);
      expect(rpcCalls, isEmpty);
    });

    test('switching between cached custom ranges does not mix snapshots',
        () async {
      online = true;
      await select(1);
      gross = '100.25';
      await select(25);
      online = false;
      await select(1);
      expect(current().snapshot!.summary.grossSalesCents, BigInt.from(150050));
      await select(25);
      expect(current().snapshot!.summary.grossSalesCents, BigInt.from(10025));
      await select(15);
      expect(current().snapshot, isNull);
      expect(current().phase, SalesReportScreenPhase.unavailableOffline);
      expect(rpcCalls, hasLength(2));
    });

    test('remote error preserves the selected custom snapshot', () async {
      online = true;
      await select(1);
      networkFailure = true;
      await controller.refresh();
      expect(current().preset, SalesReportPreset.custom);
      expect(current().snapshot!.summary.grossSalesCents, BigInt.from(150050));
      expect(current().notice, SalesReportScreenNotice.refreshFailed);
    });

    test('null or reversed ranges preserve state and never invoke RPC',
        () async {
      online = true;
      final previous = current();
      for (final (start, end) in <(DateTime?, DateTime?)>[
        (null, DateTime(2026, 8, 31)),
        (DateTime(2026, 8), null),
        (DateTime(2026, 9), DateTime(2026, 8)),
      ]) {
        expect(
            await controller.selectCustomRange(startDate: start, endDate: end),
            isFalse);
        expect(current(), same(previous));
      }
      expect(rpcCalls, isEmpty);
      expect(() => SalesReportPeriod(from: DateTime(2026), to: DateTime(2026)),
          throwsArgumentError);
    });

    test('custom range still requires current reports.sales authorization',
        () async {
      await authorize(const ['sales.read']);
      online = true;
      await select(1);
      expect(current().phase, SalesReportScreenPhase.unauthorized);
      expect(current().snapshot, isNull);
      expect(rpcCalls, isEmpty);
    });

    test('a late response cannot replace a newer custom range', () async {
      online = true;
      final started = Completer<void>();
      final release = Completer<void>();
      beforeResponse = () {
        started.complete();
        return release.future;
      };
      final first = select(1);
      await started.future;
      final second = select(25);
      expect(current().selectedStartDate, DateTime(2026, 8, 25));
      expect(current().snapshot, isNull);
      beforeResponse = null;
      release.complete();
      await Future.wait([first, second]);
      expect(rpcCalls, hasLength(2));
      expect(current().snapshot!.summary.periodFrom,
          DateTime(2026, 8, 25).toUtc());
      expect(current().isRefreshing, isFalse);
    });
  });
}
