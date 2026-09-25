import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/reports/application/sales_report_service.dart';
import 'package:inventario_frontend/features/reports/data/datasources/report_snapshot_local_dao.dart';
import 'package:inventario_frontend/features/reports/data/datasources/sales_report_remote_datasource.dart';
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

  tearDown(() async {
    await database.close();
  });

  SalesReportService service(SalesReportRpcInvoker invoke) =>
      SalesReportService(
        authenticatedProfileId: () => authenticatedProfileId,
        authorizationDao: authorizationDao,
        snapshotDao: snapshotDao,
        remoteDatasource: SalesReportRemoteDatasource.withInvoker(invoke),
        now: () => DateTime.utc(2026, 10, 1, 13),
      );

  test('authorized scope without a snapshot returns noCache', () async {
    await _authorize(authorizationDao);

    final result = await service((_) async => [_row()]).readCached(_scope());

    expect(result.outcome, SalesReportCacheReadOutcome.noCache);
    expect(result.snapshot, isNull);
  });

  test('refresh stores an authoritative sensitive non-cost snapshot', () async {
    await _authorize(
      authorizationDao,
      permissions: const ['z.permission', 'reports.sales', 'a.permission'],
    );

    final result = await service((_) async => [_row()]).refresh(_scope());

    expect(result.outcome, SalesReportRefreshOutcome.refreshed);
    expect(result.snapshot!.summary.grossSalesCents, BigInt.from(150050));
    expect(result.snapshot!.includesSensitiveData, isTrue);
    expect(result.snapshot!.includesCosts, isFalse);
    expect(
      result.snapshot!.capabilityFingerprint,
      'a.permission\u001freports.sales\u001fz.permission',
    );
    expect(result.snapshot!.fetchedAt, DateTime.utc(2026, 10, 1, 13));
  });

  test('cached snapshot is exposed only while reports.sales remains active',
      () async {
    await _authorize(authorizationDao);
    final currentService = service((_) async => [_row()]);
    await currentService.refresh(_scope());

    final available = await currentService.readCached(_scope());
    expect(available.outcome, SalesReportCacheReadOutcome.available);

    await _authorize(
      authorizationDao,
      permissions: const ['inventory.read'],
    );
    final denied = await currentService.readCached(_scope());
    expect(denied.outcome, SalesReportCacheReadOutcome.unauthorized);
    expect(await snapshotDao.readSalesSummary(_scope()), isNull);
  });

  test('revoked context invalidates the snapshot fail-closed', () async {
    await _authorize(authorizationDao);
    final currentService = service((_) async => [_row()]);
    await currentService.refresh(_scope());
    await _authorize(authorizationDao, status: 'revoked');

    final result = await currentService.readCached(_scope());

    expect(result.outcome, SalesReportCacheReadOutcome.unauthorized);
    expect(await snapshotDao.readSalesSummary(_scope()), isNull);
  });

  test('cross-profile caller cannot read or erase another profile cache',
      () async {
    await _authorize(authorizationDao);
    final currentService = service((_) async => [_row()]);
    await currentService.refresh(_scope());
    authenticatedProfileId = 'profile-b';

    final result = await currentService.readCached(_scope());

    expect(result.outcome, SalesReportCacheReadOutcome.unauthorized);
    expect(await snapshotDao.readSalesSummary(_scope()), isNotNull);
  });

  test('network refresh failure preserves the last authorized cache', () async {
    await _authorize(authorizationDao);
    await service((_) async => [_row()]).refresh(_scope());

    final result = await service((_) async {
      throw const SocketException('offline');
    }).refresh(_scope());

    expect(result.outcome, SalesReportRefreshOutcome.remoteFailure);
    expect(result.failureKind, SalesReportRemoteFailureKind.network);
    expect(result.preservedCache, isNotNull);
    expect(result.preservedCache!.summary.grossSalesCents, BigInt.from(150050));
  });

  test('authoritative forbidden response invalidates cached sensitive data',
      () async {
    await _authorize(authorizationDao);
    await service((_) async => [_row()]).refresh(_scope());

    final result = await service((_) async {
      throw const PostgrestException(message: 'denied', code: '42501');
    }).refresh(_scope());

    expect(result.outcome, SalesReportRefreshOutcome.unauthorized);
    expect(await snapshotDao.readSalesSummary(_scope()), isNull);
  });

  test('permission is rechecked after RPC before writing the snapshot',
      () async {
    await _authorize(authorizationDao);
    final currentService = service((_) async {
      await _authorize(
        authorizationDao,
        permissions: const ['inventory.read'],
      );
      return [_row()];
    });

    final result = await currentService.refresh(_scope());

    expect(result.outcome, SalesReportRefreshOutcome.unauthorized);
    expect(await snapshotDao.readSalesSummary(_scope()), isNull);
  });

  test('authorization and cache remain branch-scoped', () async {
    await _authorize(authorizationDao);
    await _authorize(authorizationDao, branchId: 'branch-b');
    final currentService = service((parameters) async => [
          _row(branchId: parameters['p_branch_id']! as String),
        ]);

    await currentService.refresh(_scope());
    await currentService.refresh(_scope(branchId: 'branch-b'));
    await _authorize(
      authorizationDao,
      branchId: 'branch-b',
      status: 'revoked',
    );

    expect(
      (await currentService.readCached(_scope())).outcome,
      SalesReportCacheReadOutcome.available,
    );
    expect(
      (await currentService.readCached(_scope(branchId: 'branch-b'))).outcome,
      SalesReportCacheReadOutcome.unauthorized,
    );
  });
}

Future<void> _authorize(
  AuthorizedOperationalContextLocalDao dao, {
  String branchId = 'branch-a',
  List<String> permissions = const ['reports.sales'],
  String status = 'active',
}) =>
    dao.replaceContext(
      AuthorizedOperationalContextProjection(
        profileId: 'profile-a',
        businessId: 'business-a',
        branchId: branchId,
        effectivePermissions: permissions,
        effectiveRoles: const ['custom-role'],
        applicableMembershipIds: const ['membership-a'],
        authorizationValidatedAt: DateTime.utc(2026, 10, 1, 11),
        snapshotId: 'core-snapshot',
        status: status,
      ),
    );

SalesReportScope _scope({String branchId = 'branch-a'}) => SalesReportScope(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: branchId,
      period: SalesReportPeriod(
        from: DateTime.utc(2026, 9),
        to: DateTime.utc(2026, 10),
      ),
    );

Map<String, Object?> _row({String branchId = 'branch-a'}) => {
      'business_id': 'business-a',
      'branch_id': branchId,
      'period_from': '2026-09-01T00:00:00.000Z',
      'period_to': '2026-10-01T00:00:00.000Z',
      'gross_sales': '1500.50',
      'sale_count': 2,
      'average_ticket': '750.25',
      'authoritative_as_of': '2026-10-01T12:00:00.000Z',
    };
