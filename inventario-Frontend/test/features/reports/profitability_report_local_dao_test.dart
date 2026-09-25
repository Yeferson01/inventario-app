import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/reports/data/datasources/report_snapshot_local_dao.dart';
import 'package:inventario_frontend/features/reports/data/models/profitability_report_models.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';

void main() {
  late AppDatabase database;
  late ReportSnapshotLocalDao dao;

  setUp(() {
    database = AppDatabase.executor(NativeDatabase.memory());
    dao = ReportSnapshotLocalDao(database);
  });
  tearDown(() async => database.close());

  Future<void> write(
    ProfitabilityReportSummary summary, {
    String profileId = 'profile-a',
  }) =>
      dao.replaceProfitability(
        profileId: profileId,
        summary: summary,
        fetchedAt: DateTime.utc(2026, 10, 1, 13),
        authorizationValidatedAt: DateTime.utc(2026, 10, 1, 12),
        capabilityFingerprint: 'reports.sales\u001fsales.view_costs',
      );

  test('profitability and sales summary coexist for the same exact period',
      () async {
    await write(_summary());
    await dao.replaceSalesSummary(
      profileId: 'profile-a',
      summary: SalesReportSummary(
        businessId: 'business-a',
        branchId: 'branch-a',
        periodFrom: DateTime.utc(2026, 9),
        periodTo: DateTime.utc(2026, 10),
        grossSalesCents: BigInt.from(6000000),
        saleCount: 1,
        averageTicketCents: BigInt.from(6000000),
        authoritativeAsOf: DateTime.utc(2026, 10, 1, 12),
      ),
      fetchedAt: DateTime.utc(2026, 10, 1, 13),
      authorizationValidatedAt: DateTime.utc(2026, 10, 1, 12),
      capabilityFingerprint: 'reports.sales',
    );
    expect((await dao.readProfitability(_scope()))!.summary.knownCogsCents,
        BigInt.from(4729000));
    expect((await dao.readSalesSummary(_scope()))!.summary.grossSalesCents,
        BigInt.from(6000000));
    expect(await _count(database), 2);
  });

  test('same scope replaces only profitability, retaining exact ratio',
      () async {
    await write(_summary());
    await write(_summary(net: 10000, cogs: 7000));
    final snapshot = (await dao.readProfitability(_scope()))!;
    expect(await _count(database), 1);
    expect(snapshot.summary.knownNetSalesCents, BigInt.from(10000));
    expect(snapshot.summary.knownGrossMargin!.numerator, BigInt.from(3000));
    expect(snapshot.summary.knownGrossMargin!.denominator, BigInt.from(10000));
    expect(snapshot.includesSensitiveData, isTrue);
    expect(snapshot.includesCosts, isTrue);
    expect(
        snapshot.capabilityFingerprint, 'reports.sales\u001fsales.view_costs');
  });

  test('profile, business, branch, and UTC range isolate snapshots', () async {
    await write(_summary());
    await write(_summary(), profileId: 'profile-b');
    await write(_summary(businessId: 'business-b'));
    await write(_summary(branchId: 'branch-b'));
    await write(
        _summary(from: DateTime.utc(2026, 8), to: DateTime.utc(2026, 9)));
    expect(await _count(database), 5);
    expect(await dao.readProfitability(_scope()), isNotNull);
    expect(
        await dao.readProfitability(_scope(profileId: 'profile-b')), isNotNull);
    expect(await dao.readProfitability(_scope(businessId: 'business-b')),
        isNotNull);
    expect(
        await dao.readProfitability(_scope(branchId: 'branch-b')), isNotNull);
    expect(
        await dao.readProfitability(
            _scope(from: DateTime.utc(2026, 8), to: DateTime.utc(2026, 9))),
        isNotNull);
    expect(
        await dao
            .readProfitability(_scope(from: DateTime.utc(2026, 9, 1, 0, 0, 1))),
        isNull);
  });

  test('cost revocation deletes only profitability in its authorization scope',
      () async {
    await write(_summary());
    await write(_summary(), profileId: 'profile-b');
    await write(_summary(branchId: 'branch-b'));
    await dao.replaceSalesSummary(
      profileId: 'profile-a',
      summary: SalesReportSummary(
        businessId: 'business-a',
        branchId: 'branch-a',
        periodFrom: DateTime.utc(2026, 9),
        periodTo: DateTime.utc(2026, 10),
        grossSalesCents: BigInt.zero,
        saleCount: 0,
        averageTicketCents: null,
        authoritativeAsOf: DateTime.utc(2026, 10, 1, 12),
      ),
      fetchedAt: DateTime.utc(2026, 10, 1, 13),
      authorizationValidatedAt: DateTime.utc(2026, 10, 1, 12),
      capabilityFingerprint: 'reports.sales',
    );
    await dao.invalidateProfitabilityScope(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
    );
    expect(await dao.readProfitability(_scope()), isNull);
    expect(await dao.readSalesSummary(_scope()), isNotNull);
    expect(
        await dao.readProfitability(_scope(profileId: 'profile-b')), isNotNull);
    expect(
        await dao.readProfitability(_scope(branchId: 'branch-b')), isNotNull);
  });

  test('malformed sensitivity flags fail closed and writes create no outbox',
      () async {
    await write(_summary());
    expect(
        (await database
                .customSelect('select count(*) as c from local_sync_mutations')
                .getSingle())
            .read<int>('c'),
        0);
    await database.customUpdate(
      'update local_report_snapshots set includes_costs = 0 '
      'where report_type = \'sales_profitability\'',
    );
    await expectLater(
        dao.readProfitability(_scope()), throwsA(isA<FormatException>()));
  });
}

ProfitabilityReportSummary _summary({
  String businessId = 'business-a',
  String branchId = 'branch-a',
  DateTime? from,
  DateTime? to,
  int net = 5400000,
  int cogs = 4729000,
}) =>
    ProfitabilityReportSummary(
      businessId: businessId,
      branchId: branchId,
      periodFrom: from ?? DateTime.utc(2026, 9),
      periodTo: to ?? DateTime.utc(2026, 10),
      knownNetSalesCents: BigInt.from(net),
      knownCogsCents: BigInt.from(cogs),
      knownGrossProfitCents: BigInt.from(net - cogs),
      unknownCostItemCount: 0,
      unknownCostNetSalesCents: BigInt.zero,
      costCoverageComplete: true,
      authoritativeAsOf: DateTime.utc(2026, 10, 1, 12),
    );

SalesReportScope _scope({
  String profileId = 'profile-a',
  String businessId = 'business-a',
  String branchId = 'branch-a',
  DateTime? from,
  DateTime? to,
}) =>
    SalesReportScope(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
      period: SalesReportPeriod(
        from: from ?? DateTime.utc(2026, 9),
        to: to ?? DateTime.utc(2026, 10),
      ),
    );

Future<int> _count(AppDatabase db) async => (await db
        .customSelect('select count(*) as c from local_report_snapshots')
        .getSingle())
    .read<int>('c');
