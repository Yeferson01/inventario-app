import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cash_session_remote_models.dart';

typedef CashSessionRpcInvoker = Future<Object?> Function(
  String functionName,
  Map<String, Object?> parameters,
);

class CashSessionRemoteDataSource {
  CashSessionRemoteDataSource(SupabaseClient client)
      : this.withInvoker(
          (functionName, parameters) => client.rpc(
            functionName,
            params: parameters,
          ),
        );

  CashSessionRemoteDataSource.withInvoker(this._invoke);

  final CashSessionRpcInvoker _invoke;

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
