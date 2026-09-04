import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cash_session_remote_models.dart';

typedef CashSessionRpcInvoker = Future<Object?> Function(
  String functionName,
  Map<String, Object?> parameters,
);

typedef CashSessionRowsLoader = Future<Object?> Function({
  required String businessId,
  required String branchId,
  required String cashRegisterId,
  required Set<String> cashSessionIds,
});

class CashSessionRemoteDataSource {
  CashSessionRemoteDataSource(SupabaseClient client)
      : this.withInvoker(
          (functionName, parameters) => client.rpc(
            functionName,
            params: parameters,
          ),
          rowsLoader: ({
            required businessId,
            required branchId,
            required cashRegisterId,
            required cashSessionIds,
          }) {
            return client
                .from('cash_sessions')
                .select(
                  'id,business_id,branch_id,cash_register_id,opened_by,'
                  'closed_by,opening_amount,expected_closing_amount,'
                  'actual_closing_amount,difference_amount,status,opened_at,'
                  'closed_at,notes,version,created_at,updated_at,deleted_at',
                )
                .eq('business_id', businessId)
                .eq('branch_id', branchId)
                .eq('cash_register_id', cashRegisterId)
                .inFilter('id', cashSessionIds.toList(growable: false));
          },
        );

  CashSessionRemoteDataSource.withInvoker(
    this._invoke, {
    CashSessionRowsLoader? rowsLoader,
  }) : _rowsLoader = rowsLoader;

  final CashSessionRpcInvoker _invoke;
  final CashSessionRowsLoader? _rowsLoader;

  Future<List<AuthoritativeCashSessionSnapshot>> loadSessionsById({
    required String businessId,
    required String branchId,
    required String cashRegisterId,
    required Set<String> cashSessionIds,
  }) async {
    if (cashSessionIds.isEmpty) return const [];
    final loader = _rowsLoader;
    if (loader == null) {
      throw const CashRemoteStateUnavailableException(
        'No se puede consultar el estado autoritativo de las sesiones locales.',
      );
    }
    try {
      final response = await loader(
        businessId: businessId,
        branchId: branchId,
        cashRegisterId: cashRegisterId,
        cashSessionIds: cashSessionIds,
      );
      if (response is! List) {
        throw const FormatException('Cash session query must return a list.');
      }
      final sessions = response
          .map(AuthoritativeCashSessionSnapshot.fromTableRow)
          .toList(growable: false);
      for (final session in sessions) {
        if (session.businessId != businessId ||
            session.branchId != branchId ||
            session.cashRegisterId != cashRegisterId ||
            !cashSessionIds.contains(session.id)) {
          throw const FormatException(
            'Cash session query returned a row outside the requested scope.',
          );
        }
      }
      return sessions;
    } on CashRemoteStateUnavailableException {
      rethrow;
    } on TimeoutException catch (error) {
      throw CashRemoteStateUnavailableException(
        'No se pudo verificar el estado remoto de caja.',
        error,
      );
    } on SocketException catch (error) {
      throw CashRemoteStateUnavailableException(
        'No se pudo verificar el estado remoto de caja.',
        error,
      );
    } on PostgrestException catch (error) {
      throw CashRemoteStateUnavailableException(
        'El servidor rechazó la consulta autoritativa de caja.',
        error,
      );
    } on FormatException catch (error) {
      throw CashRemoteStateUnavailableException(
        'La consulta remota de caja no tiene el contrato esperado.',
        error,
      );
    }
  }

  Future<AuthoritativeCashSessionSnapshot> openOrReuse({
    required String businessId,
    required String branchId,
    required String cashRegisterId,
    required double openingAmount,
  }) {
    return _call(
      'open_or_reuse_cash_session',
      {
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_cash_register_id': cashRegisterId,
        'p_opening_amount': openingAmount,
      },
    );
  }

  Future<AuthoritativeCashSessionSnapshot> closeAuthoritatively({
    required String businessId,
    required String branchId,
    required String cashRegisterId,
    required String cashSessionId,
    required double actualClosingAmount,
    String? notes,
  }) {
    return _call(
      'close_cash_session_authoritatively',
      {
        'p_business_id': businessId,
        'p_branch_id': branchId,
        'p_cash_register_id': cashRegisterId,
        'p_cash_session_id': cashSessionId,
        'p_actual_closing_amount': actualClosingAmount,
        'p_notes': notes,
      },
    );
  }

  Future<AuthoritativeCashSessionSnapshot> _call(
    String functionName,
    Map<String, Object?> parameters,
  ) async {
    try {
      return AuthoritativeCashSessionSnapshot.fromJson(
        await _invoke(functionName, parameters),
      );
    } on CashRemoteStateUnavailableException {
      rethrow;
    } on TimeoutException catch (error) {
      throw CashRemoteStateUnavailableException(
        'No se pudo verificar el estado remoto de caja.',
        error,
      );
    } on SocketException catch (error) {
      throw CashRemoteStateUnavailableException(
        'No se pudo verificar el estado remoto de caja.',
        error,
      );
    } on PostgrestException catch (error) {
      throw CashRemoteStateUnavailableException(
        'El servidor rechazó o no pudo resolver la operación de caja.',
        error,
      );
    } on FormatException catch (error) {
      throw CashRemoteStateUnavailableException(
        'La respuesta remota de caja no tiene el contrato esperado.',
        error,
      );
    }
  }
}
