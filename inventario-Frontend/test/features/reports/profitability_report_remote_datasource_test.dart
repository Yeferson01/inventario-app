import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/reports/data/datasources/profitability_report_remote_datasource.dart';
import 'package:inventario_frontend/features/reports/data/models/profitability_report_models.dart';
import 'package:inventario_frontend/features/reports/data/models/sales_report_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  final period = SalesReportPeriod(
    from: DateTime.parse('2026-09-01T00:00:00-05:00'),
    to: DateTime.parse('2026-10-01T00:00:00-05:00'),
  );

  Future<ProfitabilityReportSummary> load(
    Object? response, {
    SalesReportPeriod? requestedPeriod,
  }) =>
      ProfitabilityReportRemoteDatasource.withInvoker((_) async => response)
          .loadSummary(
        businessId: 'business-a',
        branchId: 'branch-a',
        period: requestedPeriod ?? period,
      );

  test('valid response preserves exact cents and rational margin', () async {
    Map<String, Object?>? captured;
    final datasource = ProfitabilityReportRemoteDatasource.withInvoker(
      (parameters) async {
        captured = parameters;
        return [_row(period)];
      },
    );
    final summary = await datasource.loadSummary(
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
    expect(summary.knownNetSalesCents, BigInt.from(5400000));
    expect(summary.knownCogsCents, BigInt.from(4729000));
    expect(summary.knownGrossProfitCents, BigInt.from(671000));
    expect(summary.knownGrossMargin!.numerator, BigInt.from(671000));
    expect(summary.knownGrossMargin!.denominator, BigInt.from(5400000));
    expect(summary.costCoverageComplete, isTrue);
    expect(summary.authoritativeAsOf, DateTime.utc(2026, 10, 1, 12));
  });

  test('high precision remote margin never becomes a stored double', () async {
    final row = _row(period);
    row['known_gross_margin'] = '0.124259259259259259259259259259259259259';
    final summary = await load([row]);
    expect(summary.knownGrossMargin!.numerator, BigInt.from(671000));
    expect(summary.knownGrossMargin!.denominator, BigInt.from(5400000));
    expect(summary.toCacheJson()['known_gross_margin'], {
      'numerator': '671000',
      'denominator': '5400000',
    });
  });

  test('zero revenue requires null margin and zero remains distinct', () async {
    final row = _row(period)
      ..['known_net_sales'] = '0.00'
      ..['known_cogs'] = '0.00'
      ..['known_gross_profit'] = '0.00'
      ..['known_gross_margin'] = null;
    expect((await load([row])).knownGrossMargin, isNull);
    row['known_gross_margin'] = '0';
    await expectLater(load([row]), throwsA(_malformed));
  });

  test('mixed costs preserve unknown count, revenue and false coverage',
      () async {
    final row = _row(period)
      ..['unknown_cost_item_count'] = '2'
      ..['unknown_cost_net_sales'] = '125.50'
      ..['cost_coverage_complete'] = false;
    final summary = await load([row]);
    expect(summary.unknownCostItemCount, 2);
    expect(summary.unknownCostNetSalesCents, BigInt.from(12550));
    expect(summary.costCoverageComplete, isFalse);
  });

  test('scope and period mismatches fail closed', () async {
    for (final change in <void Function(Map<String, Object?>)>[
      (row) => row['business_id'] = 'business-b',
      (row) => row['branch_id'] = 'branch-b',
      (row) => row['period_from'] = '2026-09-02T05:00:00Z',
      (row) => row['period_to'] = '2026-10-02T05:00:00Z',
    ]) {
      final row = _row(period);
      change(row);
      await expectLater(load([row]), throwsA(_malformed));
    }
  });

  test('row count and row shape must be exactly one complete map', () async {
    for (final response in <Object?>[
      null,
      const [],
      [_row(period), _row(period)],
      const ['invalid'],
      const [
        <String, Object?>{'business_id': 'business-a'}
      ],
    ]) {
      await expectLater(load(response), throwsA(_malformed));
    }
  });

  test('invalid monetary numeric, sub-cent values and totals fail closed',
      () async {
    for (final change in <void Function(Map<String, Object?>)>[
      (row) => row['known_net_sales'] = 'NaN',
      (row) => row['known_cogs'] = '0.001',
      (row) => row['known_gross_profit'] = '6711.00',
      (row) => row['unknown_cost_net_sales'] = double.infinity,
      (row) => row['known_gross_margin'] = 'not-a-decimal',
    ]) {
      final row = _row(period);
      change(row);
      await expectLater(load([row]), throwsA(_malformed));
    }
  });

  test('invalid count and coverage flag fail closed', () async {
    for (final change in <void Function(Map<String, Object?>)>[
      (row) => row['unknown_cost_item_count'] = -1,
      (row) => row['unknown_cost_item_count'] = '1.5',
      (row) => row['cost_coverage_complete'] = 'true',
      (row) => row['cost_coverage_complete'] = false,
      (row) => row['authoritative_as_of'] = 'invalid',
    ]) {
      final row = _row(period);
      change(row);
      await expectLater(load([row]), throwsA(_malformed));
    }
  });

  test('42501 and network errors are mapped without leaking server detail',
      () async {
    final forbidden = ProfitabilityReportRemoteDatasource.withInvoker(
      (_) async => throw const PostgrestException(
          message: 'private detail', code: '42501'),
    );
    final offline = ProfitabilityReportRemoteDatasource.withInvoker(
      (_) async => throw const SocketException('offline'),
    );
    await expectLater(
      forbidden.loadSummary(
          businessId: 'business-a', branchId: 'branch-a', period: period),
      throwsA(isA<ProfitabilityReportRemoteException>().having((e) => e.kind,
          'kind', ProfitabilityReportRemoteFailureKind.unauthorized)),
    );
    await expectLater(
      offline.loadSummary(
          businessId: 'business-a', branchId: 'branch-a', period: period),
      throwsA(isA<ProfitabilityReportRemoteException>().having(
          (e) => e.kind, 'kind', ProfitabilityReportRemoteFailureKind.network)),
    );
  });

  test('cache JSON retains null margin and all exact amounts', () async {
    final row = _row(period)
      ..['known_net_sales'] = '0.00'
      ..['known_cogs'] = '0.00'
      ..['known_gross_profit'] = '0.00'
      ..['known_gross_margin'] = null;
    final summary = await load([row]);
    final restored =
        ProfitabilityReportSummary.fromCacheJson(summary.toCacheJson());
    expect(restored.knownGrossMargin, isNull);
    expect(restored.unknownCostNetSalesCents, BigInt.zero);
  });
}

Map<String, Object?> _row(SalesReportPeriod period) => {
      'business_id': 'business-a',
      'branch_id': 'branch-a',
      'period_from': period.from.toIso8601String(),
      'period_to': period.to.toIso8601String(),
      'known_net_sales': '54000.00',
      'known_cogs': '47290.00',
      'known_gross_profit': '6710.00',
      'known_gross_margin': '0.12425925925925925926',
      'unknown_cost_item_count': 0,
      'unknown_cost_net_sales': '0.00',
      'cost_coverage_complete': true,
      'authoritative_as_of': '2026-10-01T12:00:00Z',
    };

final Matcher _malformed = isA<ProfitabilityReportRemoteException>().having(
  (error) => error.kind,
  'kind',
  ProfitabilityReportRemoteFailureKind.malformedResponse,
);
