import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

enum SelfServiceBusinessCreationFailureKind {
  network,
  invalidInput,
  idempotencyConflict,
  unauthorized,
  malformedResponse,
  remote,
}

class SelfServiceBusinessCreationException implements Exception {
  const SelfServiceBusinessCreationException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final SelfServiceBusinessCreationFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class SelfServiceBusinessCreationResult {
  const SelfServiceBusinessCreationResult({
    required this.businessId,
    required this.branchId,
  });

  final String businessId;
  final String branchId;

  factory SelfServiceBusinessCreationResult.fromRpc(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid self-service creation response.');
    }
    final json = Map<String, dynamic>.from(value);
    final businessId = (json['business_id'] as String?)?.trim() ?? '';
    final branchId = (json['branch_id'] as String?)?.trim() ?? '';
    if (businessId.isEmpty || branchId.isEmpty) {
      throw const FormatException('Missing canonical business identifiers.');
    }
    return SelfServiceBusinessCreationResult(
      businessId: businessId,
      branchId: branchId,
    );
  }
}

typedef SelfServiceBusinessCreationRpcInvoker = Future<Object?> Function(
  Map<String, dynamic> params,
);

class SelfServiceBusinessCreationRemoteDataSource {
  SelfServiceBusinessCreationRemoteDataSource(SupabaseClient client)
      : this.withInvoker(
          (params) => client.rpc(
            'create_self_service_business',
            params: params,
          ),
        );

  SelfServiceBusinessCreationRemoteDataSource.withInvoker(
    SelfServiceBusinessCreationRpcInvoker invoke,
  ) : _invoke = invoke;

  final SelfServiceBusinessCreationRpcInvoker _invoke;

  Future<SelfServiceBusinessCreationResult> create({
    required String businessName,
    required String branchName,
    required String idempotencyKey,
  }) async {
    try {
      final response = await _invoke({
        'p_business_name': businessName,
        'p_idempotency_key': idempotencyKey,
        'p_branch_name': branchName,
      });
      return SelfServiceBusinessCreationResult.fromRpc(response);
    } on SelfServiceBusinessCreationException {
      rethrow;
    } on TimeoutException catch (error) {
      throw SelfServiceBusinessCreationException(
        kind: SelfServiceBusinessCreationFailureKind.network,
        message: 'Necesitas conexión a internet para crear un negocio.',
        cause: error,
      );
    } on SocketException catch (error) {
      throw SelfServiceBusinessCreationException(
        kind: SelfServiceBusinessCreationFailureKind.network,
        message: 'Necesitas conexión a internet para crear un negocio.',
        cause: error,
      );
    } on PostgrestException catch (error) {
      throw _mapPostgrest(error);
    } on FormatException catch (error) {
      throw SelfServiceBusinessCreationException(
        kind: SelfServiceBusinessCreationFailureKind.malformedResponse,
        message: 'No fue posible crear el negocio. Intenta nuevamente.',
        cause: error,
      );
    } catch (error) {
      throw SelfServiceBusinessCreationException(
        kind: SelfServiceBusinessCreationFailureKind.remote,
        message: 'No fue posible crear el negocio. Intenta nuevamente.',
        cause: error,
      );
    }
  }

  SelfServiceBusinessCreationException _mapPostgrest(
    PostgrestException error,
  ) {
    if (error.code == '23505' ||
        error.message.contains(
          'self_service_business_creation_idempotency_conflict',
        )) {
      return SelfServiceBusinessCreationException(
        kind: SelfServiceBusinessCreationFailureKind.idempotencyConflict,
        message:
            'No pudimos completar la creación porque esta solicitud cambió. Intenta nuevamente.',
        cause: error,
      );
    }
    if (error.code == '22023') {
      return SelfServiceBusinessCreationException(
        kind: SelfServiceBusinessCreationFailureKind.invalidInput,
        message: 'Revisa los datos del negocio e intenta nuevamente.',
        cause: error,
      );
    }
    if (error.code == '42501') {
      return SelfServiceBusinessCreationException(
        kind: SelfServiceBusinessCreationFailureKind.unauthorized,
        message: 'Tu sesión ya no está disponible.',
        cause: error,
      );
    }
    return SelfServiceBusinessCreationException(
      kind: SelfServiceBusinessCreationFailureKind.remote,
      message: 'No fue posible crear el negocio. Intenta nuevamente.',
      cause: error,
    );
  }
}
