import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/sales_report_models.dart';

typedef SalesReportRpcInvoker = Future<Object?> Function(
  Map<String, Object?> parameters,
);

enum SalesReportRemoteFailureKind {
  unauthorized,
  network,
  malformedResponse,
  remote,
}

class SalesReportRemoteException implements Exception {
  const SalesReportRemoteException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final SalesReportRemoteFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class SalesReportRemoteDatasource {
  SalesReportRemoteDatasource(SupabaseClient client)
      : this.withInvoker(
          (parameters) => client.rpc(
            'get_branch_sales_report_summary',
            params: parameters,
          ),
        );

  SalesReportRemoteDatasource.withInvoker(this._invoke);

  final SalesReportRpcInvoker _invoke;

  Future<SalesReportSummary> loadSummary({
    required String businessId,
    required String branchId,
    required SalesReportPeriod period,
  }) async {
    if (businessId.trim().isEmpty || branchId.trim().isEmpty) {
      throw const SalesReportRemoteException(
        kind: SalesReportRemoteFailureKind.malformedResponse,
        message: 'Sales report scope is incomplete.',
      );
    }

    try {
      final response = await _invoke({
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_from': period.from.toIso8601String(),
        'p_to': period.to.toIso8601String(),
      });
      if (response is! List || response.length != 1) {
        throw const FormatException(
          'Sales report RPC must return exactly one row.',
        );
      }
      final value = response.single;
      if (value is! Map) {
        throw const FormatException('Sales report row is malformed.');
      }
      final row = value.map<String, Object?>(
        (key, item) => MapEntry(key.toString(), item),
      );
      final summary = _parseRow(row);
      if (summary.businessId != businessId ||
          summary.branchId != branchId ||
          !_sameInstant(summary.periodFrom, period.from) ||
          !_sameInstant(summary.periodTo, period.to)) {
        throw const FormatException(
          'Sales report response is outside the requested scope.',
        );
      }
      return summary;
    } on SalesReportRemoteException {
      rethrow;
    } on FormatException catch (error) {
      throw SalesReportRemoteException(
        kind: SalesReportRemoteFailureKind.malformedResponse,
        message: 'Sales report response is invalid.',
        cause: error,
      );
    } on TimeoutException catch (error) {
      throw SalesReportRemoteException(
        kind: SalesReportRemoteFailureKind.network,
        message: 'Sales report request timed out.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw SalesReportRemoteException(
        kind: SalesReportRemoteFailureKind.network,
        message: 'Sales report service is unavailable.',
        cause: error,
      );
    } on PostgrestException catch (error) {
      throw SalesReportRemoteException(
        kind: error.code == '42501' || error.code == 'PGRST301'
            ? SalesReportRemoteFailureKind.unauthorized
            : SalesReportRemoteFailureKind.remote,
        message: error.code == '42501' || error.code == 'PGRST301'
            ? 'Sales report is not authorized.'
            : 'Sales report request failed.',
        cause: error,
      );
    } catch (error) {
      throw SalesReportRemoteException(
        kind: SalesReportRemoteFailureKind.remote,
        message: 'Sales report request failed.',
        cause: error,
      );
    }
  }

  SalesReportSummary _parseRow(Map<String, Object?> row) {
    final businessId = _requiredString(row, 'business_id');
    final branchId = _requiredString(row, 'branch_id');
    final periodFrom = parseReportDateTime(row['period_from'], 'period_from');
    final periodTo = parseReportDateTime(row['period_to'], 'period_to');
    if (!periodTo.isAfter(periodFrom)) {
      throw const FormatException('Sales report period is invalid.');
    }

    final grossSalesCents = parseReportMoneyCents(
      row['gross_sales'],
      'gross_sales',
    );
    final saleCountValue = parseReportInteger(row['sale_count'], 'sale_count');
    if (grossSalesCents.isNegative ||
        saleCountValue.isNegative ||
        saleCountValue > BigInt.from(0x7fffffffffffffff)) {
      throw const FormatException('Sales report totals are invalid.');
    }

    final averageRaw = row['average_ticket'];
    final averageTicketCents = averageRaw == null
        ? null
        : parseReportMoneyCents(averageRaw, 'average_ticket');
    final saleCount = saleCountValue.toInt();
    if ((saleCount == 0) != (averageTicketCents == null) ||
        (averageTicketCents?.isNegative ?? false) ||
        (saleCount == 0 && grossSalesCents != BigInt.zero)) {
      throw const FormatException(
        'Sales report average does not match its totals.',
      );
    }

    return SalesReportSummary(
      businessId: businessId,
      branchId: branchId,
      periodFrom: periodFrom,
      periodTo: periodTo,
      grossSalesCents: grossSalesCents,
      saleCount: saleCount,
      averageTicketCents: averageTicketCents,
      authoritativeAsOf: parseReportDateTime(
        row['authoritative_as_of'],
        'authoritative_as_of',
      ),
    );
  }

  bool _sameInstant(DateTime left, DateTime right) =>
      left.toUtc().microsecondsSinceEpoch ==
      right.toUtc().microsecondsSinceEpoch;

  String _requiredString(Map<String, Object?> row, String field) {
    final value = row[field];
    if (value is String && value.trim().isNotEmpty) {
      return value;
    }
    throw FormatException('Invalid $field in sales report response.');
  }
}
