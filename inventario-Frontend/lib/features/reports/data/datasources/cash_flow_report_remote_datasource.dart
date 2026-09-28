import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cash_flow_report_models.dart';
import '../models/sales_report_models.dart';
import 'sales_report_remote_datasource.dart';

class CashFlowReportRemoteDatasource {
  CashFlowReportRemoteDatasource(SupabaseClient client)
      : this.withInvoker((parameters) => client
            .rpc('get_branch_cash_flow_report_summary', params: parameters));

  CashFlowReportRemoteDatasource.withInvoker(this._invoke);

  final SalesReportRpcInvoker _invoke;

  Future<CashFlowReportSummary> loadSummary({
    required String businessId,
    required String branchId,
    required SalesReportPeriod period,
  }) async {
    try {
      final result = await _invoke({
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_from': period.from.toIso8601String(),
        'p_to': period.to.toIso8601String(),
      });
      if (result is! List || result.length != 1 || result.single is! Map) {
        throw const FormatException('Cash report must return one row');
      }
      final summary = CashFlowReportSummary.fromJson(
        (result.single as Map).map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
      if (summary.businessId != businessId ||
          summary.branchId != branchId ||
          summary.periodFrom.microsecondsSinceEpoch !=
              period.from.microsecondsSinceEpoch ||
          summary.periodTo.microsecondsSinceEpoch !=
              period.to.microsecondsSinceEpoch) {
        throw const FormatException('Cash report response scope mismatch');
      }
      return summary;
    } on FormatException catch (error) {
      throw SalesReportRemoteException(
          kind: SalesReportRemoteFailureKind.malformedResponse,
          message: 'Cash report response is invalid.',
          cause: error);
    } on TimeoutException catch (error) {
      throw SalesReportRemoteException(
          kind: SalesReportRemoteFailureKind.network,
          message: 'Cash report request timed out.',
          cause: error);
    } on SocketException catch (error) {
      throw SalesReportRemoteException(
          kind: SalesReportRemoteFailureKind.network,
          message: 'Cash report service is unavailable.',
          cause: error);
    } on PostgrestException catch (error) {
      final unauthorized = error.code == '42501' || error.code == 'PGRST301';
      throw SalesReportRemoteException(
          kind: unauthorized
              ? SalesReportRemoteFailureKind.unauthorized
              : SalesReportRemoteFailureKind.remote,
          message: unauthorized
              ? 'Cash report is not authorized.'
              : 'Cash report request failed.',
          cause: error);
    } on SalesReportRemoteException {
      rethrow;
    } catch (error) {
      throw SalesReportRemoteException(
          kind: SalesReportRemoteFailureKind.remote,
          message: 'Cash report request failed.',
          cause: error);
    }
  }
}
