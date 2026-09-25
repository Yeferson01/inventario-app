import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/reports/data/datasources/sales_report_remote_datasource.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final period = SalesReportPeriod(
    from: DateTime.parse('2026-09-01T00:00:00-05:00'),
    to: DateTime.parse('2026-10-01T00:00:00-05:00'),
  );

  test('RPC parameters use the requested scope and canonical UTC period',
      () async {
    Map<String, Object?>? captured;
    final datasource =
        SalesReportRemoteDatasource.withInvoker((parameters) async {
      captured = parameters;
      return [_row(period: period)];
    });

    final result = await datasource.loadSummary(
      businessId: 'business-a',
      branchId: 'branch-a',
      period: period,
    );

    expect(captured, {
      'p_business_id': 'business-a',
      'p_branch_id': 'branch-a',
      'p_from': '2026-09-01T05:00:00.000Z',
      'p_to': '2026-10-01T05:00:00.000Z',
    });
    expect(result.grossSalesCents, BigInt.from(12346));
    expect(result.averageTicketCents, BigInt.from(4115));
    expect(result.saleCount, 3);
  });

  test('zero-sale response preserves null average ticket', () async {
    final datasource = SalesReportRemoteDatasource.withInvoker((_) async {
      return [
        _row(
          period: period,
          grossSales: 0,
          saleCount: 0,
          averageTicket: null,
        ),
      ];
    });

    final result = await datasource.loadSummary(
      businessId: 'business-a',
      branchId: 'branch-a',
      period: period,
    );

    expect(result.grossSalesCents, BigInt.zero);
    expect(result.saleCount, 0);
    expect(result.averageTicketCents, isNull);
  });

  test('a real zero average remains zero rather than null', () async {
    final datasource = SalesReportRemoteDatasource.withInvoker((_) async {
      return [
        _row(
          period: period,
          grossSales: '0.00',
          saleCount: '2',
          averageTicket: '0.00',
        ),
      ];
    });

    final result = await datasource.loadSummary(
      businessId: 'business-a',
      branchId: 'branch-a',
      period: period,
    );

    expect(result.averageTicketCents, BigInt.zero);
  });

  test('scope mismatch is rejected as malformed', () async {
    final datasource = SalesReportRemoteDatasource.withInvoker((_) async {
      return [_row(period: period, businessId: 'business-b')];
    });

    await expectLater(
      datasource.loadSummary(
        businessId: 'business-a',
        branchId: 'branch-a',
        period: period,
      ),
      throwsA(_failure(SalesReportRemoteFailureKind.malformedResponse)),
    );
  });

  test('period mismatch is rejected as malformed', () async {
    final datasource = SalesReportRemoteDatasource.withInvoker((_) async {
      final row = _row(period: period);
      row['period_to'] = '2026-10-02T05:00:00Z';
      return [row];
    });

    await expectLater(
      datasource.loadSummary(
        businessId: 'business-a',
        branchId: 'branch-a',
        period: period,
      ),
      throwsA(_failure(SalesReportRemoteFailureKind.malformedResponse)),
    );
  });

  test('missing, duplicate, and non-row responses fail closed', () async {
    for (final response in <Object?>[
      null,
      const [],
      [_row(period: period), _row(period: period)],
      const ['not-a-row'],
      const [
        {'business_id': 'business-a'},
      ],
    ]) {
      final datasource = SalesReportRemoteDatasource.withInvoker(
        (_) async => response,
      );
      await expectLater(
        datasource.loadSummary(
          businessId: 'business-a',
          branchId: 'branch-a',
          period: period,
        ),
        throwsA(_failure(SalesReportRemoteFailureKind.malformedResponse)),
      );
    }
  });

  test('invalid total and average combinations fail closed', () async {
    final invalidRows = <Map<String, Object?>>[
      _row(period: period, grossSales: -1),
      _row(period: period, saleCount: -1),
      _row(period: period, saleCount: 0, averageTicket: 0),
      _row(period: period, saleCount: 2, averageTicket: null),
      _row(period: period, grossSales: 1, saleCount: 0, averageTicket: null),
    ];
    for (final row in invalidRows) {
      final datasource = SalesReportRemoteDatasource.withInvoker(
        (_) async => [row],
      );
      await expectLater(
        datasource.loadSummary(
          businessId: 'business-a',
          branchId: 'branch-a',
          period: period,
        ),
        throwsA(_failure(SalesReportRemoteFailureKind.malformedResponse)),
      );
    }
  });

  test('PostgREST 42501 maps to unauthorized without exposing details',
      () async {
    final datasource = SalesReportRemoteDatasource.withInvoker((_) async {
      throw const PostgrestException(message: 'denied', code: '42501');
    });

    await expectLater(
      datasource.loadSummary(
        businessId: 'business-a',
        branchId: 'branch-a',
        period: period,
      ),
      throwsA(_failure(SalesReportRemoteFailureKind.unauthorized)),
    );
  });
}

Map<String, Object?> _row({
  required SalesReportPeriod period,
  String businessId = 'business-a',
  String branchId = 'branch-a',
  Object grossSales = '123.456',
  Object saleCount = 3,
  Object? averageTicket = '41.152',
}) =>
    {
      'business_id': businessId,
      'branch_id': branchId,
      'period_from': period.from.toIso8601String(),
      'period_to': period.to.toIso8601String(),
      'gross_sales': grossSales,
      'sale_count': saleCount,
      'average_ticket': averageTicket,
      'authoritative_as_of': '2026-10-01T12:00:00Z',
    };

Matcher _failure(SalesReportRemoteFailureKind kind) =>
    isA<SalesReportRemoteException>()
        .having((error) => error.kind, 'kind', kind);
