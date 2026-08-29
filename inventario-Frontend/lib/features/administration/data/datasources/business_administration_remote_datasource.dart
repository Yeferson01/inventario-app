import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/business_administration_models.dart';

enum BusinessAdministrationFailureKind {
  network,
  unauthorized,
  duplicate,
  invalidState,
  unavailable,
  malformedResponse,
  remote,
}

class BusinessAdministrationException implements Exception {
  const BusinessAdministrationException(this.kind, this.message);

  final BusinessAdministrationFailureKind kind;
  final String message;

  @override
  String toString() => message;
}

typedef BusinessAdministrationRpcInvoker = Future<Object?> Function(
  String functionName,
  Map<String, dynamic> parameters,
);
typedef BusinessInvitationEdgeInvoker = Future<Object?> Function(
  Map<String, dynamic> body,
);

class BusinessAdministrationRemoteDatasource {
  BusinessAdministrationRemoteDatasource(SupabaseClient client)
      : this.withInvokers(
          rpc: (name, parameters) => client.rpc(name, params: parameters),
          edge: (body) async {
            final response = await client.functions.invoke(
              'business-member-invitations',
              body: body,
            );
            return response.data;
          },
        );

  BusinessAdministrationRemoteDatasource.withInvokers({
    required BusinessAdministrationRpcInvoker rpc,
    required BusinessInvitationEdgeInvoker edge,
  })  : _rpc = rpc,
        _edge = edge;

  final BusinessAdministrationRpcInvoker _rpc;
  final BusinessInvitationEdgeInvoker _edge;

  Future<List<BusinessBranchSummary>> listBranches(String businessId) async {
    final json = await _execute(
      () => _rpc('list_business_branches', {'p_business_id': businessId}),
    );
    return _decode(
      () => _mapList(json['branches'], BusinessBranchSummary.fromJson),
    );
  }

  Future<BusinessBranchCreationResult> createBranch(
    CreateBusinessBranchRequest request, {
    required String idempotencyKey,
  }) async {
    final json = await _execute(
      () => _rpc('create_business_branch', {
        'p_business_id': request.businessId,
        'p_name': request.name.trim(),
        'p_address': _optional(request.address),
        'p_phone': _optional(request.phone),
        'p_idempotency_key': idempotencyKey,
      }),
      duplicateMessage: 'Ya existe una sucursal con esos datos.',
    );
    return _decode(() => BusinessBranchCreationResult.fromJson(json));
  }

  Future<BusinessMemberInvitationOptions> listInvitationOptions(
    String businessId,
  ) async {
    final json = await _execute(
      () => _rpc(
        'list_business_member_invitation_options',
        {'p_business_id': businessId},
      ),
    );
    return _decode(() => BusinessMemberInvitationOptions.fromJson(json));
  }

  Future<AdminBusinessMemberInvitationsResponse> listBusinessInvitations(
    String businessId,
  ) async {
    final json = await _execute(
      () => _rpc(
        'list_business_member_invitations',
        {'p_business_id': businessId},
      ),
    );
    return _decode(
      () => AdminBusinessMemberInvitationsResponse.fromJson(json),
    );
  }

  Future<BusinessMemberInvitationsResponse> listMyInvitations() async {
    final json = await _execute(
      () => _rpc('list_my_business_member_invitations', const {}),
    );
    return _decode(() => BusinessMemberInvitationsResponse.fromJson(json));
  }

  Future<IssueBusinessMemberInvitationResult> issueInvitation(
    IssueBusinessMemberInvitationRequest request, {
    required String idempotencyKey,
  }) async {
    final json = await _execute(
      () => _edge({
        'business_id': request.businessId,
        'email': request.email.trim().toLowerCase(),
        'role_id': request.roleId,
        'branch_id': request.branchId,
        'idempotency_key': idempotencyKey,
      }),
      duplicateMessage: 'Ya existe una invitación pendiente equivalente.',
    );
    return _decode(() => IssueBusinessMemberInvitationResult.fromJson(json));
  }

  Future<AcceptedBusinessMemberInvitation> acceptInvitation(
    String invitationId,
  ) async {
    final json = await _execute(
      () => _rpc(
        'accept_business_member_invitation',
        {'p_invitation_id': invitationId},
      ),
      unavailableMessage: 'La invitación ya no está disponible.',
    );
    return _decode(() => AcceptedBusinessMemberInvitation.fromJson(json));
  }

  Future<BusinessMemberInvitation> revokeInvitation(
    String invitationId, {
    String? reason,
  }) async {
    final json = await _execute(
      () => _rpc('revoke_business_member_invitation', {
        'p_invitation_id': invitationId,
        'p_reason': _optional(reason),
      }),
      unavailableMessage: 'La invitación ya no puede revocarse.',
    );
    return _decode(() => BusinessMemberInvitation.fromJson(json));
  }

  Future<Map<String, dynamic>> _execute(
    Future<Object?> Function() operation, {
    String duplicateMessage = 'La operación ya existe.',
    String unavailableMessage = 'La operación ya no está disponible.',
  }) async {
    try {
      final value = await operation();
      if (value is! Map) {
        throw const FormatException('Respuesta administrativa inválida.');
      }
      return Map<String, dynamic>.from(value);
    } on BusinessAdministrationException {
      rethrow;
    } on PostgrestException catch (error) {
      throw _mapPostgrest(error, duplicateMessage, unavailableMessage);
    } on FunctionException catch (error) {
      throw _mapFunction(error, duplicateMessage);
    } on TimeoutException {
      throw const BusinessAdministrationException(
        BusinessAdministrationFailureKind.network,
        'No fue posible comunicarse con el servidor.',
      );
    } on SocketException {
      throw const BusinessAdministrationException(
        BusinessAdministrationFailureKind.network,
        'No fue posible comunicarse con el servidor.',
      );
    } on FormatException {
      throw const BusinessAdministrationException(
        BusinessAdministrationFailureKind.malformedResponse,
        'El servidor devolvió una respuesta administrativa inválida.',
      );
    } catch (_) {
      throw const BusinessAdministrationException(
        BusinessAdministrationFailureKind.remote,
        'No fue posible completar la operación administrativa.',
      );
    }
  }

  BusinessAdministrationException _mapPostgrest(
    PostgrestException error,
    String duplicateMessage,
    String unavailableMessage,
  ) {
    final normalized = error.message.toLowerCase();
    if (normalized.contains('expired') ||
        normalized.contains('revoked') ||
        normalized.contains('not available')) {
      return BusinessAdministrationException(
        BusinessAdministrationFailureKind.unavailable,
        unavailableMessage,
      );
    }
    if (error.code == '42501') {
      return const BusinessAdministrationException(
        BusinessAdministrationFailureKind.unauthorized,
        'No tienes permisos para realizar esta operación.',
      );
    }
    if (error.code == '23505') {
      return BusinessAdministrationException(
        BusinessAdministrationFailureKind.duplicate,
        duplicateMessage,
      );
    }
    if (error.code == '23514') {
      return const BusinessAdministrationException(
        BusinessAdministrationFailureKind.invalidState,
        'La operación no cumple las reglas del negocio.',
      );
    }
    return const BusinessAdministrationException(
      BusinessAdministrationFailureKind.remote,
      'No fue posible completar la operación administrativa.',
    );
  }

  BusinessAdministrationException _mapFunction(
    FunctionException error,
    String duplicateMessage,
  ) {
    if (error.status == 401 || error.status == 403) {
      return const BusinessAdministrationException(
        BusinessAdministrationFailureKind.unauthorized,
        'No tienes permisos para emitir esta invitación.',
      );
    }
    if (error.status == 409) {
      return BusinessAdministrationException(
        BusinessAdministrationFailureKind.duplicate,
        duplicateMessage,
      );
    }
    if (error.status == 400 || error.status == 422) {
      return const BusinessAdministrationException(
        BusinessAdministrationFailureKind.invalidState,
        'Revisa el correo, el rol y el alcance de la invitación.',
      );
    }
    return const BusinessAdministrationException(
      BusinessAdministrationFailureKind.remote,
      'No fue posible emitir la invitación.',
    );
  }

  T _decode<T>(T Function() decode) {
    try {
      return decode();
    } on BusinessAdministrationException {
      rethrow;
    } catch (_) {
      throw const BusinessAdministrationException(
        BusinessAdministrationFailureKind.malformedResponse,
        'El servidor devolvió una respuesta administrativa inválida.',
      );
    }
  }
}

String? _optional(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

List<T> _mapList<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
  if (raw is! List) throw const FormatException('Respuesta inválida.');
  return raw
      .map((item) => parse(Map<String, dynamic>.from(item as Map)))
      .toList();
}
