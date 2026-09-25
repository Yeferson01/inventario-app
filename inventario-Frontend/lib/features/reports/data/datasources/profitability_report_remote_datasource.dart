import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profitability_report_models.dart';
import '../models/sales_report_models.dart';

typedef ProfitabilityReportRpcInvoker = Future<Object?> Function(
  Map<String, Object?> parameters,
);

enum ProfitabilityReportRemoteFailureKind {
  unauthorized,
  network,
  malformedResponse,
  remote,
}

class ProfitabilityReportRemoteException implements Exception {
  const ProfitabilityReportRemoteException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final ProfitabilityReportRemoteFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class ProfitabilityReportRemoteDatasource {
  ProfitabilityReportRemoteDatasource(SupabaseClient client)
      : this.withInvoker(
          (parameters) => client.rpc(
            'get_branch_profitability_report_summary',
            params: parameters,
          ),
        );

  ProfitabilityReportRemoteDatasource.withInvoker(this._invoke);

  final ProfitabilityReportRpcInvoker _invoke;

  Future<ProfitabilityReportSummary> loadSummary({
    required String businessId,
    required String branchId,
    required SalesReportPeriod period,
  }) async {
    if (businessId.trim().isEmpty || branchId.trim().isEmpty) {
      throw const ProfitabilityReportRemoteException(
        kind: ProfitabilityReportRemoteFailureKind.malformedResponse,
        message: 'Profitability report scope is incomplete.',
      );
    }
    try {
      final response = await _invoke({
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_from': period.from.toIso8601String(),
        'p_to': period.to.toIso8601String(),
      });
      if (response is! List ||
          response.length != 1 ||
          response.single is! Map) {
        throw const FormatException('Profitability RPC must return one row.');
      }
      final row = (response.single as Map).map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
      final summary = _parseRow(row);
      if (summary.businessId != businessId ||
          summary.branchId != branchId ||
          summary.periodFrom.microsecondsSinceEpoch !=
              period.from.microsecondsSinceEpoch ||
          summary.periodTo.microsecondsSinceEpoch !=
              period.to.microsecondsSinceEpoch) {
        throw const FormatException('Profitability response scope mismatch.');
      }
      return summary;
    } on ProfitabilityReportRemoteException {
      rethrow;
    } on FormatException catch (error) {
      throw ProfitabilityReportRemoteException(
        kind: ProfitabilityReportRemoteFailureKind.malformedResponse,
        message: 'Profitability report response is invalid.',
        cause: error,
      );
    } on TimeoutException catch (error) {
      throw ProfitabilityReportRemoteException(
        kind: ProfitabilityReportRemoteFailureKind.network,
        message: 'Profitability report request timed out.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw ProfitabilityReportRemoteException(
        kind: ProfitabilityReportRemoteFailureKind.network,
        message: 'Profitability report service is unavailable.',
        cause: error,
      );
    } on PostgrestException catch (error) {
      final unauthorized = error.code == '42501' || error.code == 'PGRST301';
      throw ProfitabilityReportRemoteException(
        kind: unauthorized
            ? ProfitabilityReportRemoteFailureKind.unauthorized
            : ProfitabilityReportRemoteFailureKind.remote,
        message: unauthorized
            ? 'Profitability report is not authorized.'
            : 'Profitability report request failed.',
        cause: error,
      );
    } catch (error) {
      throw ProfitabilityReportRemoteException(
        kind: ProfitabilityReportRemoteFailureKind.remote,
        message: 'Profitability report request failed.',
        cause: error,
      );
    }
  }

  ProfitabilityReportSummary _parseRow(Map<String, Object?> row) {
    final count = parseReportInteger(
      row['unknown_cost_item_count'],
      'unknown_cost_item_count',
    );
    if (count.isNegative || count > BigInt.from(0x7fffffffffffffff)) {
      throw const FormatException('Unknown cost count is invalid.');
    }
    final coverage = row['cost_coverage_complete'];
    if (coverage is! bool) {
      throw const FormatException('Cost coverage is invalid.');
    }
    final revenue =
        parseExactReportMoneyCents(row['known_net_sales'], 'known_net_sales');
    validateRemoteProfitabilityMargin(row['known_gross_margin'], revenue);
    return ProfitabilityReportSummary(
      businessId: _requiredString(row, 'business_id'),
      branchId: _requiredString(row, 'branch_id'),
      periodFrom: parseReportDateTime(row['period_from'], 'period_from'),
      periodTo: parseReportDateTime(row['period_to'], 'period_to'),
      knownNetSalesCents: revenue,
      knownCogsCents:
          parseExactReportMoneyCents(row['known_cogs'], 'known_cogs'),
      knownGrossProfitCents: parseExactReportMoneyCents(
          row['known_gross_profit'], 'known_gross_profit'),
      unknownCostItemCount: count.toInt(),
      unknownCostNetSalesCents: parseExactReportMoneyCents(
          row['unknown_cost_net_sales'], 'unknown_cost_net_sales'),
      costCoverageComplete: coverage,
      authoritativeAsOf: parseReportDateTime(
          row['authoritative_as_of'], 'authoritative_as_of'),
    );
  }

  String _requiredString(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value is String && value.trim().isNotEmpty) return value;
    throw FormatException('Invalid $field in profitability response.');
  }
}
