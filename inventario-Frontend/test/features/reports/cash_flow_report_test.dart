import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/reports/application/cash_flow_report_controller.dart';
import 'package:inventario_frontend/features/reports/data/datasources/cash_flow_report_remote_datasource.dart';
import 'package:inventario_frontend/features/reports/data/datasources/report_snapshot_local_dao.dart';
import 'package:inventario_frontend/features/reports/data/datasources/sales_report_remote_datasource.dart';
import 'package:inventario_frontend/features/reports/data/models/cash_flow_report_models.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final period = SalesReportPeriod(
    from: DateTime.utc(2026, 9, 1),
    to: DateTime.utc(2026, 10, 1),
  );
  SalesReportScope scope(
          {String profile = 'p',
          String branch = 'a',
          SalesReportPeriod? range}) =>
      SalesReportScope(
        profileId: profile,
        businessId: 'b',
        branchId: branch,
        period: range ?? period,
      );

  test('exact cash metrics, category classification and cache roundtrip', () {
    final summary = CashFlowReportSummary.fromJson(_row(period));
    expect(summary.cashSalesCents, BigInt.parse('9007199254740993'));
    expect(summary.additionalInflowsCents, BigInt.from(3000));
    expect(summary.totalInflowsCents, BigInt.parse('9007199254743993'));
    expect(summary.totalOutflowsCents, BigInt.from(6500));
    expect(summary.netCashFlowCents, BigInt.parse('9007199254737493'));
    expect(summary.inventoryAcquisitionCents, BigInt.from(4000));
    expect(summary.operatingExpensesCents, BigInt.from(1500));
    expect(summary.ownerWithdrawalsCents, BigInt.from(700));
    expect(summary.otherOutflowsCents, BigInt.from(300));
    expect(CashFlowReportSummary.fromJson(summary.toJson()).netCashFlowCents,
        summary.netCashFlowCents);
  });

  test('malformed monetary amount, category and arithmetic fail closed', () {
    for (final mutate in <void Function(Map<String, Object?>)>[
      (row) => row['cash_sales_cents'] = '1.5',
      (row) => row['cash_sales_cents'] = double.infinity,
      (row) => row['total_cash_inflows_cents'] = '0',
      (row) => row['operating_expenses_cents'] = '4000',
      (row) => row['outflow_by_category'] = {
            'unknown': {'count': 1, 'total_cents': '6500'}
          },
    ]) {
      final row = _row(period);
      mutate(row);
      expect(() => CashFlowReportSummary.fromJson(row), throwsFormatException);
    }
  });

  test('remote request is UTC scoped; wrong scope and network fail closed',
      () async {
    Map<String, Object?>? sent;
    final remote = CashFlowReportRemoteDatasource.withInvoker((params) async {
      sent = params;
      return [_row(period)];
    });
    expect(
        (await remote.loadSummary(
                businessId: 'b', branchId: 'a', period: period))
            .cashSalesCents,
        BigInt.parse('9007199254740993'));
    expect(sent, {
      'p_business_id': 'b',
      'p_branch_id': 'a',
      'p_from': '2026-09-01T00:00:00.000Z',
      'p_to': '2026-10-01T00:00:00.000Z',
    });
    await expectLater(
      CashFlowReportRemoteDatasource.withInvoker(
              (_) async => [_row(period)..['branch_id'] = 'z'])
          .loadSummary(businessId: 'b', branchId: 'a', period: period),
      throwsA(isA<SalesReportRemoteException>().having((e) => e.kind, 'kind',
          SalesReportRemoteFailureKind.malformedResponse)),
    );
    await expectLater(
      CashFlowReportRemoteDatasource.withInvoker(
              (_) async => throw const SocketException('offline'))
          .loadSummary(businessId: 'b', branchId: 'a', period: period),
      throwsA(isA<SalesReportRemoteException>()
          .having((e) => e.kind, 'kind', SalesReportRemoteFailureKind.network)),
    );
    await expectLater(
      CashFlowReportRemoteDatasource.withInvoker((_) async =>
              throw const PostgrestException(message: 'secret', code: '42501'))
          .loadSummary(businessId: 'b', branchId: 'a', period: period),
      throwsA(isA<SalesReportRemoteException>().having(
          (e) => e.kind, 'kind', SalesReportRemoteFailureKind.unauthorized)),
    );
  });

  test('snapshot is isolated by profile, branch and period', () async {
    final db = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = ReportSnapshotLocalDao(db);
    final summary = CashFlowReportSummary.fromJson(_row(period));
    await dao.replaceCashFlow(
        profileId: 'p',
        summary: summary,
        fetchedAt: DateTime.utc(2026, 10, 1),
        authorizationValidatedAt: DateTime.utc(2026, 9, 30),
        capabilityFingerprint: 'reports.cash');
    expect((await dao.readCashFlow(scope()))!.summary.cashSalesCents,
        summary.cashSalesCents);
    expect(await dao.readCashFlow(scope(profile: 'other')), isNull);
    expect(await dao.readCashFlow(scope(branch: 'z')), isNull);
    expect(
        await dao.readCashFlow(scope(
            range: SalesReportPeriod(
                from: DateTime.utc(2026, 8), to: DateTime.utc(2026, 9)))),
        isNull);
    await dao.invalidateCashFlowScope(
        profileId: 'p', businessId: 'b', branchId: 'a');
    expect(await dao.readCashFlow(scope()), isNull);
  });

  test('malformed cached payload is rejected without creating outbox',
      () async {
    final db = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = ReportSnapshotLocalDao(db);
    await dao.replaceCashFlow(
        profileId: 'p',
        summary: CashFlowReportSummary.fromJson(_row(period)),
        fetchedAt: DateTime.utc(2026, 10, 1),
        authorizationValidatedAt: DateTime.utc(2026, 9, 30),
        capabilityFingerprint: 'reports.cash');
    expect(
        await db
            .customSelect('select count(*) n from local_sync_batches')
            .getSingle()
            .then((row) => row.read<int>('n')),
        0);
    expect(
        await db
            .customSelect('select count(*) n from local_sync_mutations')
            .getSingle()
            .then((row) => row.read<int>('n')),
        0);
    await db.customStatement(
        "update local_report_snapshots set payload_json = '{' where report_type = ?",
        [cashFlowReportType]);
    await expectLater(dao.readCashFlow(scope()), throwsFormatException);
  });

  test('pending local movement warns without changing authoritative totals',
      () async {
    final db = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = ReportSnapshotLocalDao(db);
    await db
        .into(db.businesses)
        .insert(BusinessesCompanion.insert(id: 'b', name: 'B'));
    await db.into(db.profiles).insert(ProfilesCompanion.insert(id: 'p'));
    await db.customStatement(
        'insert into branches (id,business_id,name) values (?,?,?)',
        ['a', 'b', 'A']);
    await db.into(db.cashRegisters).insert(CashRegistersCompanion.insert(
        id: 'r', businessId: const Value('b'), branchId: const Value('a')));
    await db.into(db.cashSessions).insert(CashSessionsCompanion.insert(
        id: 's',
        businessId: const Value('b'),
        branchId: const Value('a'),
        cashRegisterId: const Value('r')));
    final summary = CashFlowReportSummary.fromJson(_row(period));
    await dao.replaceCashFlow(
        profileId: 'p',
        summary: summary,
        fetchedAt: DateTime.utc(2026, 10, 1),
        authorizationValidatedAt: DateTime.utc(2026, 9, 30),
        capabilityFingerprint: 'reports.cash');
    expect((await dao.readCashFlow(scope()))!.hasPendingLocalSync, isFalse);
    await db.into(db.localCashMovements).insert(
        LocalCashMovementsCompanion.insert(
            id: 'm',
            businessId: 'b',
            branchId: 'a',
            cashRegisterId: 'r',
            cashSessionId: 's',
            direction: 'outflow',
            category: 'utilities',
            amountCents: BigInt.from(50),
            currency: 'COP',
            sourceType: 'manual',
            occurredAt: DateTime.utc(2026, 9, 15),
            createdBy: 'p',
            idempotencyKey: 'm',
            createdAt: DateTime.utc(2026, 9, 15),
            updatedAt: DateTime.utc(2026, 9, 15)));
    final snapshot = (await dao.readCashFlow(scope()))!;
    expect(snapshot.hasPendingLocalSync, isTrue);
    expect(snapshot.summary.totalOutflowsCents, BigInt.from(6500));
  });

  test('pending cash payment is scoped and recomputed from local state',
      () async {
    final db = AppDatabase.executor(NativeDatabase.memory());
    addTearDown(db.close);
    final dao = ReportSnapshotLocalDao(db);
    for (final business in ['b', 'other-business']) {
      await db
          .into(db.businesses)
          .insert(BusinessesCompanion.insert(id: business, name: business));
    }
    for (final (branch, business) in [
      ('a', 'b'),
      ('other-branch', 'b'),
      ('foreign', 'other-business'),
    ]) {
      await db.customStatement(
          'insert into branches (id,business_id,name) values (?,?,?)',
          [branch, business, branch]);
    }
    final summary = CashFlowReportSummary.fromJson(_row(period));
    await dao.replaceCashFlow(
        profileId: 'p',
        summary: summary,
        fetchedAt: DateTime.utc(2026, 10, 1),
        authorizationValidatedAt: DateTime.utc(2026, 9, 30),
        capabilityFingerprint: 'reports.cash');

    Future<void> sale(
      String id, {
      String business = 'b',
      String branch = 'a',
      String method = 'cash',
      DateTime? at,
    }) async {
      final time = at ?? DateTime.utc(2026, 9, 15);
      await db.into(db.sales).insert(SalesCompanion.insert(
            id: id,
            total: 10,
            businessId: Value(business),
            branchId: Value(branch),
            paymentMethod: Value(method),
            createdAt: Value(time),
            localStatus: const Value('dirty'),
            syncStatus: const Value(SyncStatus.pendingInsert),
          ));
      await db.into(db.salePayments).insert(SalePaymentsCompanion.insert(
            id: 'payment-$id',
            businessId: business,
            saleId: id,
            branchId: Value(branch),
            paymentMethod: method,
            amount: 10,
            createdAt: Value(time),
            localStatus: const Value('dirty'),
            syncStatus: const Value(SyncStatus.pendingInsert),
          ));
    }

    expect(
        (await dao.readCashFlow(scope()))!.hasPendingLocalCashSales, isFalse);
    await sale('card', method: 'card');
    await sale('other-branch-sale', branch: 'other-branch');
    await sale('other-business-sale',
        business: 'other-business', branch: 'foreign');
    await sale('before', at: DateTime.utc(2026, 8, 31, 23, 59, 59));
    await sale('upper', at: DateTime.utc(2026, 10, 1));
    expect(
        (await dao.readCashFlow(scope()))!.hasPendingLocalCashSales, isFalse);

    await sale('cash');
    final pending = (await dao.readCashFlow(scope()))!;
    expect(pending.hasPendingLocalCashSales, isTrue);
    expect(pending.summary.cashSalesCents, summary.cashSalesCents);
    expect(pending.summary.totalInflowsCents, summary.totalInflowsCents);
    await (db.update(db.sales)..where((row) => row.id.equals('cash'))).write(
        const SalesCompanion(
            localStatus: Value('synced'),
            syncStatus: Value(SyncStatus.synced)));
    expect((await dao.readCashFlow(scope()))!.hasPendingLocalCashSales, isTrue);
    await (db.update(db.salePayments)
          ..where((row) => row.saleId.equals('cash')))
        .write(const SalePaymentsCompanion(
            localStatus: Value('synced'),
            syncStatus: Value(SyncStatus.synced)));
    expect(
        (await dao.readCashFlow(scope()))!.hasPendingLocalCashSales, isFalse);

    // Oct 31 at 23:58 Bogotá is Nov 1 at 04:58 UTC. The same durable
    // payment.created_at becomes remote paid_at, irrespective of upload time.
    await sale('oct31', at: DateTime.utc(2026, 11, 1, 4, 58));
    final october = SalesReportPeriod(
      from: DateTime.utc(2026, 10, 1, 5),
      to: DateTime.utc(2026, 11, 1, 5),
    );
    final november = SalesReportPeriod(
      from: october.to,
      to: DateTime.utc(2026, 12, 1, 5),
    );
    expect(await dao.hasPendingCashSales(scope(range: october)), isTrue);
    expect(await dao.hasPendingCashSales(scope(range: november)), isFalse);
    await (db.update(db.sales)..where((row) => row.id.equals('oct31'))).write(
        const SalesCompanion(
            localStatus: Value('synced'),
            syncStatus: Value(SyncStatus.synced)));
    await (db.update(db.salePayments)
          ..where((row) => row.saleId.equals('oct31')))
        .write(const SalePaymentsCompanion(
            localStatus: Value('synced'),
            syncStatus: Value(SyncStatus.synced)));
    expect(await dao.hasPendingCashSales(scope(range: october)), isFalse);
  });

  test('presets use half-open local calendar periods and distinct keys', () {
    final now = DateTime(2026, 9, 16, 15);
    final periods = [
      for (final preset in CashFlowPreset.values
          .where((preset) => preset != CashFlowPreset.custom))
        cashFlowPeriodFor(preset, now),
    ];
    expect(periods.map((p) => p.filterKey).toSet(), hasLength(4));
    expect(periods.first.from.toLocal(), DateTime(2026, 9, 16));
    expect(periods.first.to.toLocal(), DateTime(2026, 9, 17));
    expect(periods.last.from.toLocal(), DateTime(2026));
    expect(periods.last.to.toLocal(), DateTime(2027));
  });
}

Map<String, Object?> _row(SalesReportPeriod period) => {
      'business_id': 'b',
      'branch_id': 'a',
      'period_from': period.from.toIso8601String(),
      'period_to': period.to.toIso8601String(),
      'cash_sales_cents': '9007199254740993',
      'additional_cash_inflows_cents': '3000',
      'total_cash_inflows_cents': '9007199254743993',
      'total_cash_outflows_cents': '6500',
      'net_cash_flow_cents': '9007199254737493',
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
