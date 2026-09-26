import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/app_uuid.dart';
import '../../sync/application/app_context_models.dart';
import '../../sync/application/local_sync_outbox_service.dart';
import '../../sync/data/datasources/local_sync_outbox_dao.dart';
import '../../sync/data/models/local_sync_outbox_models.dart';
import '../data/datasources/cash_movement_local_dao.dart';
import '../data/datasources/cash_session_local_dao.dart';
import 'cash_movement_models.dart';

/// Offline-first recording only. Hosted application and acknowledgement are
/// intentionally delegated to the cash sync/recovery pipeline.
class CashMovementService {
  CashMovementService({
    required AppDatabase database,
    required Future<AppCurrentContext?> Function() loadCurrentContext,
  })  : _dao = CashMovementLocalDao(database),
        _sessionDao = CashSessionLocalDao(database),
        _outbox = LocalSyncOutboxService(LocalSyncOutboxDao(database)),
        _loadCurrentContext = loadCurrentContext;

  final CashMovementLocalDao _dao;
  final CashSessionLocalDao _sessionDao;
  final LocalSyncOutboxService _outbox;
  final Future<AppCurrentContext?> Function() _loadCurrentContext;

  Future<BigInt> loadExpectedCashCents({
    required String profileId,
    required String businessId,
    required String branchId,
    required String cashRegisterId,
    required String cashSessionId,
    required CashMovementDirection direction,
  }) async {
    await _validateCurrentScope(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
      cashRegisterId: cashRegisterId,
      cashSessionId: cashSessionId,
      direction: direction,
    );
    return _sessionDao.calculateExpectedCashCentsForSession(
      cashSessionId: cashSessionId,
    );
  }

  Future<CashMovementResult> recordMovement(CashMovementRequest request) async {
    request.validate();
    return _dao.transaction(() async {
      final context = await _validateCurrentScope(
        profileId: request.profileId,
        businessId: request.businessId,
        branchId: request.branchId,
        cashRegisterId: request.cashRegisterId,
        cashSessionId: request.cashSessionId,
        direction: request.direction,
      );

      final existing =
          await _dao.findByKey(request.businessId, request.idempotencyKey);
      if (existing != null) {
        final same = existing.businessId == request.businessId &&
            existing.branchId == request.branchId &&
            existing.cashRegisterId == request.cashRegisterId &&
            existing.cashSessionId == request.cashSessionId &&
            existing.direction == request.direction.name &&
            existing.category == request.category &&
            existing.amountCents == request.amountCents &&
            existing.currency == request.currency &&
            existing.sourceType == request.sourceType &&
            existing.sourceId == request.sourceId &&
            existing.note == request.note &&
            existing.createdBy == context.profileId &&
            existing.metadataJson ==
                jsonEncode(<String, dynamic>{
                  'source': 'cash_movement_service',
                  'requested_occurred_at':
                      request.occurredAt?.toUtc().toIso8601String(),
                });
        if (!same) {
          throw const CashMovementException(
            CashMovementFailure.idempotencyConflict,
          );
        }
        return CashMovementResult(id: existing.id, alreadyRecorded: true);
      }
      if (await _dao.outboxKeyExists(
          request.businessId, request.idempotencyKey)) {
        throw const CashMovementException(
          CashMovementFailure.idempotencyConflict,
        );
      }

      if (request.direction == CashMovementDirection.outflow) {
        final expected = await _sessionDao.calculateExpectedCashCentsForSession(
          cashSessionId: request.cashSessionId,
        );
        if (expected - request.amountCents < BigInt.zero) {
          throw const CashMovementException(
              CashMovementFailure.insufficientCash);
        }
      }

      final now = DateTime.now().toUtc();
      // Drift's DateTime column stores Unix seconds. Keep the payload and
      // local ledger at the same precision so a remote echo matches exactly.
      final requestedAt = request.occurredAt?.toUtc() ?? now;
      final occurredAt = DateTime.fromMillisecondsSinceEpoch(
        (requestedAt.millisecondsSinceEpoch ~/ 1000) * 1000,
        isUtc: true,
      );
      final id = AppUuid.v7();
      final sequence = now.microsecondsSinceEpoch.remainder(1999999999) + 1;
      final metadata = <String, dynamic>{
        'source': 'cash_movement_service',
        'requested_occurred_at': request.occurredAt?.toUtc().toIso8601String(),
      };
      final payload = <String, dynamic>{
        'id': id,
        'business_id': context.businessId,
        'branch_id': context.branchId,
        'cash_register_id': request.cashRegisterId,
        'cash_session_id': request.cashSessionId,
        'direction': request.direction.name,
        'category': request.category,
        'amount': _decimalAmount(request.amountCents),
        'currency': request.currency,
        'source_type': request.sourceType,
        'source_id': request.sourceId,
        'note': request.note,
        'occurred_at': occurredAt.toIso8601String(),
        'idempotency_key': request.idempotencyKey,
        'metadata': metadata,
      };
      await _dao.insert(LocalCashMovementsCompanion.insert(
        id: id,
        businessId: request.businessId,
        branchId: request.branchId,
        cashRegisterId: request.cashRegisterId,
        cashSessionId: request.cashSessionId,
        direction: request.direction.name,
        category: request.category,
        amountCents: request.amountCents,
        currency: request.currency,
        sourceType: request.sourceType,
        sourceId: Value(request.sourceId),
        note: Value(request.note),
        occurredAt: occurredAt,
        createdBy: context.profileId!,
        idempotencyKey: request.idempotencyKey,
        metadataJson: Value(jsonEncode(metadata)),
        localStatus: const Value('dirty'),
        syncStatus: const Value(SyncStatus.pendingInsert),
        createdAt: now,
        updatedAt: now,
      ));
      await _outbox.enqueueUploadBatch(
        businessId: request.businessId,
        branchId: request.branchId,
        profileId: context.profileId,
        appDeviceId: context.appDeviceId,
        deviceInstallationId: context.installationId,
        domain: 'cash',
        mutations: [
          LocalSyncMutationDraft(
            clientMutationId:
                '${context.installationId}:cash_movements:$id:insert',
            clientSequence: sequence,
            entityTable: 'cash_movements',
            entityId: id,
            operation: 'insert',
            payload: payload,
            changedFields: payload.keys.toList(),
            idempotencyKey: request.idempotencyKey,
            businessId: request.businessId,
            branchId: request.branchId,
            profileId: context.profileId,
            appDeviceId: context.appDeviceId,
            metadata: <String, dynamic>{
              'source': 'cash_movement_service',
              'cash_session_id': request.cashSessionId,
              'cash_register_id': request.cashRegisterId,
            },
          ),
        ],
        metadata: <String, dynamic>{
          'source': 'cash_movement_service',
          'cash_session_id': request.cashSessionId,
          'cash_register_id': request.cashRegisterId,
        },
      );
      return CashMovementResult(id: id, alreadyRecorded: false);
    });
  }

  Future<AppCurrentContext> _validateCurrentScope({
    required String profileId,
    required String businessId,
    required String branchId,
    required String cashRegisterId,
    required String cashSessionId,
    required CashMovementDirection direction,
  }) async {
    final context = await _loadCurrentContext();
    if (context == null ||
        !context.authorizationContextReady ||
        context.profileId != profileId ||
        context.businessId != businessId ||
        context.branchId != branchId ||
        context.cashRegisterId != cashRegisterId ||
        context.cashSessionId != cashSessionId ||
        context.installationId.trim().isEmpty ||
        context.appDeviceId?.trim().isNotEmpty != true) {
      throw const CashMovementException(CashMovementFailure.invalidContext);
    }
    final permission = direction == CashMovementDirection.outflow
        ? 'cash.disburse'
        : 'cash.receive';
    if (!context.hasPermission(permission)) {
      throw const CashMovementException(CashMovementFailure.permissionDenied);
    }
    await _dao.validateScope(
      profileId: profileId,
      businessId: businessId,
      branchId: branchId,
      cashRegisterId: cashRegisterId,
      cashSessionId: cashSessionId,
      permission: permission,
    );
    return context;
  }

  String _decimalAmount(BigInt cents) {
    final units = cents ~/ BigInt.from(100);
    final remainder = (cents % BigInt.from(100)).toString().padLeft(2, '0');
    return '$units.$remainder';
  }
}
