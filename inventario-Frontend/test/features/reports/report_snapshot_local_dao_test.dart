import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/core/database/app_database.dart';
import 'package:inventario_frontend/features/reports/data/datasources/report_snapshot_local_dao.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';

void main() {
  late AppDatabase database;
  late ReportSnapshotLocalDao dao;

  setUp(() {
    database = AppDatabase.executor(NativeDatabase.memory());
    dao = ReportSnapshotLocalDao(database);
  });

  tearDown(() async {
    await database.close();
  });

  test('current schema 18 contains scoped report table and unique index',
      () async {
    expect(database.schemaVersion, 18);
    final columns = await database
        .customSelect('pragma table_info(local_report_snapshots)')
        .get();
    expect(
      columns.map((row) => row.data['name']),
      containsAll(<String>[
        'profile_id',
        'business_id',
        'branch_id',
        'report_type',
        'filter_key',
        'payload_json',
        'fetched_at',
        'authoritative_as_of',
        'authorization_validated_at',
        'capability_fingerprint',
        'includes_sensitive_data',
        'includes_costs',
      ]),
    );
    final index = await database
        .customSelect(
          "select name from sqlite_master where type = 'index' "
          "and name = 'ux_local_report_snapshots_scope'",
        )
        .getSingleOrNull();
    expect(index, isNotNull);
  });

  test('round-trips exact cents and snapshot provenance', () async {
    final summary = _summary();
    await dao.replaceSalesSummary(
      profileId: 'profile-a',
      summary: summary,
      fetchedAt: DateTime.utc(2026, 10, 1, 12, 1),
      authorizationValidatedAt: DateTime.utc(2026, 10, 1, 11),
      capabilityFingerprint: 'reports.sales',
    );

    final snapshot = await dao.readSalesSummary(_scope());

    expect(snapshot, isNotNull);
    expect(snapshot!.summary.grossSalesCents, BigInt.parse('123456789012345'));
    expect(snapshot.summary.averageTicketCents, BigInt.from(4115));
    expect(snapshot.summary.saleCount, 3);
    expect(snapshot.includesSensitiveData, isTrue);
    expect(snapshot.includesCosts, isFalse);
    expect(snapshot.capabilityFingerprint, 'reports.sales');
    expect(snapshot.summary.authoritativeAsOf, DateTime.utc(2026, 10, 1, 12));
  });

  test('replace is atomic and keeps one row for the same scope', () async {
    await dao.replaceSalesSummary(
      profileId: 'profile-a',
      summary: _summary(grossSalesCents: BigInt.from(100)),
      fetchedAt: DateTime.utc(2026, 10, 1, 12),
      authorizationValidatedAt: DateTime.utc(2026, 10, 1, 11),
      capabilityFingerprint: 'first',
    );
    final firstId = (await database
            .customSelect(
              'select id from local_report_snapshots',
            )
            .getSingle())
        .data['id'];

    await dao.replaceSalesSummary(
      profileId: 'profile-a',
      summary: _summary(grossSalesCents: BigInt.from(200)),
      fetchedAt: DateTime.utc(2026, 10, 1, 13),
      authorizationValidatedAt: DateTime.utc(2026, 10, 1, 12),
      capabilityFingerprint: 'second',
    );

    final rows = await database
        .customSelect(
          'select id from local_report_snapshots',
        )
        .get();
    expect(rows, hasLength(1));
    expect(rows.single.data['id'], firstId);
    final snapshot = await dao.readSalesSummary(_scope());
    expect(snapshot!.summary.grossSalesCents, BigInt.from(200));
    expect(snapshot.capabilityFingerprint, 'second');
  });

  test('cache is isolated by profile, branch, and canonical period', () async {
    final base = _summary(grossSalesCents: BigInt.from(100));
    await _write(dao, 'profile-a', base);
    await _write(
      dao,
      'profile-b',
      _summary(grossSalesCents: BigInt.from(200)),
    );
    await _write(
      dao,
      'profile-a',
      _summary(branchId: 'branch-b', grossSalesCents: BigInt.from(300)),
    );
    await _write(
      dao,
      'profile-a',
      _summary(businessId: 'business-b', grossSalesCents: BigInt.from(350)),
    );
    await _write(
      dao,
      'profile-a',
      _summary(
        from: DateTime.utc(2026, 8),
        to: DateTime.utc(2026, 9),
        grossSalesCents: BigInt.from(400),
      ),
    );

    expect((await dao.readSalesSummary(_scope()))!.summary.grossSalesCents,
        BigInt.from(100));
    expect(
      (await dao.readSalesSummary(_scope(profileId: 'profile-b')))!
          .summary
          .grossSalesCents,
      BigInt.from(200),
    );
    expect(
      (await dao.readSalesSummary(_scope(branchId: 'branch-b')))!
          .summary
          .grossSalesCents,
      BigInt.from(300),
    );
    expect(
      (await dao.readSalesSummary(_scope(businessId: 'business-b')))!
          .summary
          .grossSalesCents,
      BigInt.from(350),
    );
    expect(
      (await dao.readSalesSummary(
        _scope(from: DateTime.utc(2026, 8), to: DateTime.utc(2026, 9)),
      ))!
          .summary
          .grossSalesCents,
      BigInt.from(400),
    );
  });

  test('null and real zero average ticket remain distinct in cache', () async {
    await _write(
      dao,
      'profile-a',
      _summary(
        from: DateTime.utc(2026, 7),
        to: DateTime.utc(2026, 8),
        grossSalesCents: BigInt.zero,
        saleCount: 0,
        averageTicketCents: null,
        useDefaultAverage: false,
      ),
    );
    await _write(
      dao,
      'profile-a',
      _summary(
        from: DateTime.utc(2026, 8),
        to: DateTime.utc(2026, 9),
        grossSalesCents: BigInt.zero,
        saleCount: 1,
        averageTicketCents: BigInt.zero,
        useDefaultAverage: false,
      ),
    );

    final nullAverage = await dao.readSalesSummary(
      _scope(from: DateTime.utc(2026, 7), to: DateTime.utc(2026, 8)),
    );
    final zeroAverage = await dao.readSalesSummary(
      _scope(from: DateTime.utc(2026, 8), to: DateTime.utc(2026, 9)),
    );
    expect(nullAverage!.summary.averageTicketCents, isNull);
    expect(zeroAverage!.summary.averageTicketCents, BigInt.zero);
  });

  test('snapshot writes do not create sync batches or mutations', () async {
    final beforeBatches = await _count(database, 'local_sync_batches');
    final beforeMutations = await _count(database, 'local_sync_mutations');

    await _write(dao, 'profile-a', _summary());

    expect(await _count(database, 'local_sync_batches'), beforeBatches);
    expect(await _count(database, 'local_sync_mutations'), beforeMutations);
  });

  test('invalidate removes only the requested authorization scope', () async {
    await _write(dao, 'profile-a', _summary());
    await _write(dao, 'profile-b', _summary());

    await dao.invalidateScope(
      profileId: 'profile-a',
      businessId: 'business-a',
      branchId: 'branch-a',
    );

    expect(await dao.readSalesSummary(_scope()), isNull);
    expect(
      await dao.readSalesSummary(_scope(profileId: 'profile-b')),
      isNotNull,
    );
  });
}

Future<void> _write(
  ReportSnapshotLocalDao dao,
  String profileId,
  SalesReportSummary summary,
) =>
    dao.replaceSalesSummary(
      profileId: profileId,
      summary: summary,
      fetchedAt: DateTime.utc(2026, 10, 1, 12, 1),
      authorizationValidatedAt: DateTime.utc(2026, 10, 1, 11),
      capabilityFingerprint: 'reports.sales',
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

SalesReportSummary _summary({
  String businessId = 'business-a',
  String branchId = 'branch-a',
  DateTime? from,
  DateTime? to,
  BigInt? grossSalesCents,
  int saleCount = 3,
  BigInt? averageTicketCents,
  bool useDefaultAverage = true,
}) =>
    SalesReportSummary(
      businessId: businessId,
      branchId: branchId,
      periodFrom: from ?? DateTime.utc(2026, 9),
      periodTo: to ?? DateTime.utc(2026, 10),
      grossSalesCents: grossSalesCents ?? BigInt.parse('123456789012345'),
      saleCount: saleCount,
      averageTicketCents:
          useDefaultAverage ? BigInt.from(4115) : averageTicketCents,
      authoritativeAsOf: DateTime.utc(2026, 10, 1, 12),
    );

Future<int> _count(AppDatabase database, String table) async {
  final row = await database
      .customSelect('select count(*) as c from $table')
      .getSingle();
  return row.read<int>('c');
}
