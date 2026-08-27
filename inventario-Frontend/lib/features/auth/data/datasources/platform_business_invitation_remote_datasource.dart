import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/platform_business_invitation_models.dart';

enum PlatformInvitationFailureKind {
  network,
  unavailable,
  unauthorized,
  malformedResponse,
  remote,
}

class PlatformInvitationException implements Exception {
  const PlatformInvitationException({
    required this.kind,
    required this.message,
    this.cause,
  });

  final PlatformInvitationFailureKind kind;
  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

typedef PlatformInvitationListInvoker = Future<Object?> Function();
typedef PlatformInvitationAcceptInvoker = Future<Object?> Function(String id);

class PlatformBusinessInvitationRemoteDataSource {
  PlatformBusinessInvitationRemoteDataSource(SupabaseClient client)
      : this.withInvokers(
          list: () => client.rpc('list_my_platform_business_invitations'),
          accept: (id) => client.rpc(
            'accept_platform_business_invitation',
            params: {'p_invitation_id': id},
          ),
        );

  PlatformBusinessInvitationRemoteDataSource.withInvokers({
    required PlatformInvitationListInvoker list,
    required PlatformInvitationAcceptInvoker accept,
  })  : _list = list,
        _accept = accept;

  final PlatformInvitationListInvoker _list;
  final PlatformInvitationAcceptInvoker _accept;

  Future<MyPlatformBusinessInvitationsResponse> listMine() async {
    try {
      return MyPlatformBusinessInvitationsResponse.fromRpc(await _list());
    } catch (error) {
      throw _mapError(error, 'No se pudieron consultar las invitaciones.');
    }
  }

  Future<AcceptedPlatformBusinessInvitation> accept(String invitationId) async {
    final id = invitationId.trim();
    if (id.isEmpty) {
      throw const PlatformInvitationException(
        kind: PlatformInvitationFailureKind.malformedResponse,
        message: 'La invitación no tiene una identidad válida.',
      );
    }
    try {
      return AcceptedPlatformBusinessInvitation.fromRpc(await _accept(id));
    } catch (error) {
      throw _mapError(error, 'No se pudo aceptar la invitación.');
    }
  }

  PlatformInvitationException _mapError(Object error, String fallback) {
    if (error is PlatformInvitationException) return error;
    if (error is TimeoutException || error is SocketException) {
      return PlatformInvitationException(
        kind: PlatformInvitationFailureKind.network,
        message: 'No hay conexión para completar esta operación.',
        cause: error,
      );
    }
    if (error is FormatException) {
      return PlatformInvitationException(
        kind: PlatformInvitationFailureKind.malformedResponse,
        message: 'El servidor devolvió una respuesta de invitación inválida.',
        cause: error,
      );
    }
    if (error is PostgrestException) {
      final diagnostic =
          '${error.message} ${error.details} ${error.hint}'.toLowerCase();
      final unavailable = error.code == '42501' ||
          diagnostic.contains('expired') ||
          diagnostic.contains('revoked') ||
          diagnostic.contains('not available');
      return PlatformInvitationException(
        kind: unavailable
            ? PlatformInvitationFailureKind.unavailable
            : PlatformInvitationFailureKind.remote,
        message: unavailable
            ? 'La invitación ya no está disponible para esta cuenta.'
            : fallback,
        cause: error,
      );
    }
    return PlatformInvitationException(
      kind: PlatformInvitationFailureKind.remote,
      message: fallback,
      cause: error,
    );
  }
}
