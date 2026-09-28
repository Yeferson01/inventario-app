import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/reports/application/cash_flow_report_service.dart';
import 'package:inventario_frontend/features/reports/data/datasources/cash_flow_report_remote_datasource.dart';
import 'package:inventario_frontend/features/reports/data/datasources/report_snapshot_local_dao.dart';
import 'package:inventario_frontend/features/reports/data/datasources/sales_report_remote_datasource.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';
import 'package:inventario_frontend/features/sync/data/datasources/authorized_operational_context_local_dao.dart';
import 'package:inventario_frontend/features/sync/data/models/local_recovery_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late AppDatabase db;
  late AuthorizedOperationalContextLocalDao authorization;
  late ReportSnapshotLocalDao snapshots;
  String? signedIn = 'p';
  final scope = SalesReportScope(
      profileId: 'p',
      businessId: 'b',
      branchId: 'a',
      period: SalesReportPeriod(
          from: DateTime.utc(2026, 9), to: DateTime.utc(2026, 10)));

  setUp(() {
    db = AppDatabase.executor(NativeDatabase.memory());
    authorization = AuthorizedOperationalContextLocalDao(db);
    snapshots = ReportSnapshotLocalDao(db);
    signedIn = 'p';
  });
  tearDown(() async => db.close());

  Future<void> authorize(
          {String status = 'active',
          List<String> permissions = const ['reports.cash']}) =>
      authorization.replaceContext(AuthorizedOperationalContextProjection(
        profileId: 'p',
        businessId: 'b',
        branchId: 'a',
        effectivePermissions: permissions,
        effectiveRoles: const ['custom'],
        applicableMembershipIds: const ['member'],
        authorizationValidatedAt: DateTime.utc(2026, 9, 30),
        snapshotId: 'core',
        status: status,
      ));

  CashFlowReportService service(SalesReportRpcInvoker invoke) =>
      CashFlowReportService(
        authenticatedProfileId: () => signedIn,
        authorizationDao: authorization,
        snapshotDao: snapshots,
        remoteDatasource: CashFlowReportRemoteDatasource.withInvoker(invoke),
        now: () => DateTime.utc(2026, 10, 1),
      );

  test('online refresh caches and offline read reuses exact snapshot',
      () async {
    await authorize();
    final online = await service((_) async => [_row()]).refresh(scope);
    expect(online.outcome, CashFlowRefreshOutcome.refreshed);
    expect(online.snapshot!.summary.totalInflowsCents, BigInt.from(13000));
    final cached =
        await service((_) async => throw const SocketException('offline'))
            .readCached(scope);
    expect(cached.outcome, CashFlowCacheOutcome.available);
    expect(cached.snapshot!.summary.netCashFlowCents, BigInt.from(6500));
  });

  test('network failure preserves cache; server denial invalidates it',
      () async {
    await authorize();
    await service((_) async => [_row()]).refresh(scope);
    final unavailable =
        await service((_) async => throw const SocketException('offline'))
            .refresh(scope);
    expect(unavailable.outcome, CashFlowRefreshOutcome.remoteFailure);
    expect(unavailable.snapshot, isNotNull);
    final denied = await service((_) async =>
            throw const PostgrestException(message: 'secret', code: '42501'))
        .refresh(scope);
    expect(denied.outcome, CashFlowRefreshOutcome.unauthorized);
    expect(await snapshots.readCashFlow(scope), isNull);
  });

  test('revocation and absent capability fail closed', () async {
    await authorize();
    await service((_) async => [_row()]).refresh(scope);
    await authorize(permissions: const ['reports.sales']);
    expect((await service((_) async => [_row()]).readCached(scope)).outcome,
        CashFlowCacheOutcome.unauthorized);
    expect(await snapshots.readCashFlow(scope), isNull);
    await authorize(status: 'revoked');
    expect((await service((_) async => [_row()]).refresh(scope)).outcome,
        CashFlowRefreshOutcome.unauthorized);
  });

  test('different authenticated profile cannot read or erase cache', () async {
    await authorize();
    await service((_) async => [_row()]).refresh(scope);
    signedIn = 'other';
    expect((await service((_) async => [_row()]).readCached(scope)).outcome,
        CashFlowCacheOutcome.unauthorized);
    expect(await snapshots.readCashFlow(scope), isNotNull);
  });

  test('authorization is rechecked after RPC before persisting', () async {
    await authorize();
    final result = await service((_) async {
      await authorize(permissions: const []);
      return [_row()];
    }).refresh(scope);
    expect(result.outcome, CashFlowRefreshOutcome.unauthorized);
    expect(await snapshots.readCashFlow(scope), isNull);
  });
}

Map<String, Object?> _row() => {
      'business_id': 'b',
      'branch_id': 'a',
      'period_from': '2026-09-01T00:00:00Z',
      'period_to': '2026-10-01T00:00:00Z',
      'cash_sales_cents': '10000',
      'additional_cash_inflows_cents': '3000',
      'total_cash_inflows_cents': '13000',
      'total_cash_outflows_cents': '6500',
      'net_cash_flow_cents': '6500',
      'inventory_acquisition_outflows_cents': '4000',
      'operating_expenses_cents': '1500',
      'owner_withdrawals_cents': '700',
      'other_outflows_cents': '300',
      'outflow_by_category': {
        'supplier_purchase': {'count': 1, 'total_cents': '4000'},
        'payroll': {'count': 1, 'total_cents': '1000'},
        'utilities': {'count': 1, 'total_cents': '500'},
        'owner_withdrawal': {'count': 1, 'total_cents': '700'},
        'other': {'count': 1, 'total_cents': '300'},
      },
      'authoritative_as_of': '2026-10-01T12:00:00Z',
    };
