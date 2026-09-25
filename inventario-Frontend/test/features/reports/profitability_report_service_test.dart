import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/reports/application/profitability_report_service.dart';
import 'package:inventario_frontend/features/reports/data/datasources/profitability_report_remote_datasource.dart';
import 'package:inventario_frontend/features/reports/data/datasources/report_snapshot_local_dao.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase database;
  late AuthorizedOperationalContextLocalDao authorizationDao;
  late ReportSnapshotLocalDao snapshotDao;
  late String? authenticatedProfileId;

  setUp(() {
    database = AppDatabase.executor(NativeDatabase.memory());
    authorizationDao = AuthorizedOperationalContextLocalDao(database);
    snapshotDao = ReportSnapshotLocalDao(database);
    authenticatedProfileId = 'profile-a';
  });
  tearDown(() async => database.close());

  ProfitabilityReportService service(ProfitabilityReportRpcInvoker invoker) =>
      ProfitabilityReportService(
        authenticatedProfileId: () => authenticatedProfileId,
        authorizationDao: authorizationDao,
        snapshotDao: snapshotDao,
        remoteDatasource:
            ProfitabilityReportRemoteDatasource.withInvoker(invoker),
        now: () => DateTime.utc(2026, 10, 1, 13),
      );

  test('both capabilities permit refresh and a sensitive cost snapshot',
      () async {
    await _authorize(authorizationDao);
    final result = await service((_) async => [_row()]).refresh(_scope());
    expect(result.outcome, ProfitabilityRefreshOutcome.refreshed);
    expect(result.snapshot!.summary.knownGrossProfitCents, BigInt.from(671000));
    expect(result.snapshot!.includesSensitiveData, isTrue);
    expect(result.snapshot!.includesCosts, isTrue);
    expect(result.snapshot!.capabilityFingerprint,
        'reports.sales\u001fsales.view_costs');
  });

  test('each capability alone is insufficient and clears only cost cache',
      () async {
    await _authorize(authorizationDao);
    final current = service((_) async => [_row()]);
    await current.refresh(_scope());
    await _authorize(authorizationDao, permissions: const ['reports.sales']);
    expect((await current.readCached(_scope())).outcome,
        ProfitabilityCacheReadOutcome.unauthorized);
    expect(await snapshotDao.readProfitability(_scope()), isNull);
    expect((await current.refresh(_scope())).outcome,
        ProfitabilityRefreshOutcome.unauthorized);
    await _authorize(authorizationDao, permissions: const ['sales.view_costs']);
    expect((await current.refresh(_scope())).outcome,
        ProfitabilityRefreshOutcome.unauthorized);
  });

  test('offline cache hit and no cache remain distinct', () async {
    await _authorize(authorizationDao);
    final current = service((_) async => [_row()]);
    expect((await current.readCached(_scope())).outcome,
        ProfitabilityCacheReadOutcome.noCache);
    await current.refresh(_scope());
    expect((await current.readCached(_scope())).outcome,
        ProfitabilityCacheReadOutcome.available);
  });

  test('network failure preserves prior authorized cache, no new zeros',
      () async {
    await _authorize(authorizationDao);
    await service((_) async => [_row()]).refresh(_scope());
    final result = await service((_) async {
      throw const SocketException('offline');
    }).refresh(_scope());
    expect(result.outcome, ProfitabilityRefreshOutcome.remoteFailure);
    expect(result.failureKind, ProfitabilityReportRemoteFailureKind.network);
    expect(result.preservedCache!.summary.knownNetSalesCents,
        BigInt.from(5400000));
  });

  test('42501 invalidates the current cost cache without a fallback', () async {
    await _authorize(authorizationDao);
    await service((_) async => [_row()]).refresh(_scope());
    final result = await service((_) async {
      throw const PostgrestException(message: 'denied', code: '42501');
    }).refresh(_scope());
    expect(result.outcome, ProfitabilityRefreshOutcome.unauthorized);
    expect(result.preservedCache, isNull);
    expect(await snapshotDao.readProfitability(_scope()), isNull);
  });

  test('revoked authorization invalidates cached profitability', () async {
    await _authorize(authorizationDao);
    final current = service((_) async => [_row()]);
    await current.refresh(_scope());
    await _authorize(authorizationDao, status: 'revoked');
    expect((await current.readCached(_scope())).outcome,
        ProfitabilityCacheReadOutcome.unauthorized);
    expect(await snapshotDao.readProfitability(_scope()), isNull);
  });

  test('permission is rechecked after RPC before persisting', () async {
    await _authorize(authorizationDao);
    final current = service((_) async {
      await _authorize(authorizationDao, permissions: const ['reports.sales']);
      return [_row()];
    });
    expect((await current.refresh(_scope())).outcome,
        ProfitabilityRefreshOutcome.unauthorized);
    expect(await snapshotDao.readProfitability(_scope()), isNull);
  });

  test('network failure after local revocation cannot expose prior cache',
      () async {
    await _authorize(authorizationDao);
    await service((_) async => [_row()]).refresh(_scope());
    final current = service((_) async {
      await _authorize(authorizationDao, permissions: const ['reports.sales']);
      throw const SocketException('offline');
    });
    final result = await current.refresh(_scope());
    expect(result.outcome, ProfitabilityRefreshOutcome.unauthorized);
    expect(result.preservedCache, isNull);
    expect(await snapshotDao.readProfitability(_scope()), isNull);
  });

  test('response from another scope or period is never persisted', () async {
    await _authorize(authorizationDao);
    for (final row in [
      _row(branchId: 'branch-b'),
      _row()..['period_to'] = '2026-11-01T00:00:00Z',
    ]) {
      final result = await service((_) async => [row]).refresh(_scope());
      expect(result.outcome, ProfitabilityRefreshOutcome.remoteFailure);
      expect(result.failureKind,
          ProfitabilityReportRemoteFailureKind.malformedResponse);
      expect(await snapshotDao.readProfitability(_scope()), isNull);
    }
  });

  test('profile switch cannot read or erase another profile cost cache',
      () async {
    await _authorize(authorizationDao);
    final current = service((_) async => [_row()]);
    await current.refresh(_scope());
    authenticatedProfileId = 'profile-b';
    expect((await current.readCached(_scope())).outcome,
        ProfitabilityCacheReadOutcome.unauthorized);
    expect(await snapshotDao.readProfitability(_scope()), isNotNull);
  });

  test(
      'server 42501 invalidates the original request scope after profile switch',
      () async {
    await _authorize(authorizationDao);
    await service((_) async => [_row()]).refresh(_scope());
    final current = service((_) async {
      authenticatedProfileId = 'profile-b';
      throw const PostgrestException(message: 'denied', code: '42501');
    });
    final result = await current.refresh(_scope());
    expect(result.outcome, ProfitabilityRefreshOutcome.unauthorized);
    expect(await snapshotDao.readProfitability(_scope()), isNull);
  });

  test('two ranges coexist and refresh replaces only the requested range',
      () async {
    await _authorize(authorizationDao);
    final current = service((parameters) async => [
          _row(
              periodFrom: parameters['p_from']! as String,
              periodTo: parameters['p_to']! as String),
        ]);
    final second =
        _scope(from: DateTime.utc(2026, 8), to: DateTime.utc(2026, 9));
    await current.refresh(_scope());
    await current.refresh(second);
    expect(await snapshotDao.readProfitability(_scope()), isNotNull);
    expect(await snapshotDao.readProfitability(second), isNotNull);
    expect(
        await snapshotDao
            .readProfitability(_scope(from: DateTime.utc(2026, 9, 1, 0, 0, 1))),
        isNull);
  });

  test('branch revocation does not block another authorized branch', () async {
    await _authorize(authorizationDao);
    await _authorize(authorizationDao, branchId: 'branch-b');
    final current = service((parameters) async => [
          _row(branchId: parameters['p_branch_id']! as String),
        ]);
    await current.refresh(_scope());
    await current.refresh(_scope(branchId: 'branch-b'));
    await _authorize(authorizationDao, branchId: 'branch-b', status: 'revoked');
    expect((await current.readCached(_scope())).outcome,
        ProfitabilityCacheReadOutcome.available);
    expect((await current.readCached(_scope(branchId: 'branch-b'))).outcome,
        ProfitabilityCacheReadOutcome.unauthorized);
  });
}

Future<void> _authorize(
  AuthorizedOperationalContextLocalDao dao, {
  String branchId = 'branch-a',
  List<String> permissions = const ['reports.sales', 'sales.view_costs'],
  String status = 'active',
}) =>
    dao.replaceContext(AuthorizedOperationalContextProjection(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: branchId,
      effectivePermissions: permissions,
      effectiveRoles: const ['custom-role'],
      applicableMembershipIds: const ['membership-a'],
      authorizationValidatedAt: DateTime.utc(2026, 10, 1, 11),
      snapshotId: 'core-snapshot',
      status: status,
    ));

SalesReportScope _scope({
  String branchId = 'branch-a',
  DateTime? from,
  DateTime? to,
}) =>
    SalesReportScope(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: branchId,
      period: SalesReportPeriod(
        from: from ?? DateTime.utc(2026, 9),
        to: to ?? DateTime.utc(2026, 10),
      ),
    );

Map<String, Object?> _row({
  String branchId = 'branch-a',
  String periodFrom = '2026-09-01T00:00:00.000Z',
  String periodTo = '2026-10-01T00:00:00.000Z',
}) =>
    {
      'business_id': 'business-a',
      'branch_id': branchId,
      'period_from': periodFrom,
      'period_to': periodTo,
      'known_net_sales': '54000.00',
      'known_cogs': '47290.00',
      'known_gross_profit': '6710.00',
      'known_gross_margin': '0.12425925925925925926',
      'unknown_cost_item_count': 0,
      'unknown_cost_net_sales': '0.00',
      'cost_coverage_complete': true,
      'authoritative_as_of': '2026-10-01T12:00:00Z',
    };
