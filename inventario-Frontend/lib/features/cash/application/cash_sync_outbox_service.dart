import 'dart:convert';

import '../../sync/application/local_sync_outbox_service.dart';
import '../../sync/data/models/local_sync_outbox_models.dart';
import '../data/datasources/cash_session_local_dao.dart';

class CashSyncOutboxResult {
  const CashSyncOutboxResult({
    required this.businessId,
    required this.branchId,
    required this.cashRegistersChecked,
    required this.cashSessionsChecked,
    required this.batchesCreated,
    required this.mutationsEnqueued,
    required this.results,
  });

  final String businessId;
  final String branchId;
  final int cashRegistersChecked;
  final int cashSessionsChecked;
  final int batchesCreated;
  final int mutationsEnqueued;
  final List<Map<String, dynamic>> results;

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      'cash_registers_checked': cashRegistersChecked,
      'cash_sessions_checked': cashSessionsChecked,
      'batches_created': batchesCreated,
      'mutations_enqueued': mutationsEnqueued,
      'results': results,
    };
  }
}

class CashSyncOutboxService {
  CashSyncOutboxService({
    required CashSessionLocalDao dao,
    required LocalSyncOutboxService outboxService,
  })  : _dao = dao,
        _outboxService = outboxService;

  final CashSessionLocalDao _dao;
  final LocalSyncOutboxService _outboxService;

  Future<CashSyncOutboxResult> enqueuePendingCash({
    required String businessId,
    required String branchId,
    required String profileId,
    String? appDeviceId,
    String? deviceInstallationId,
    int limit = 10,
  }) async {
    await _dao.deleteOrphanCashOutboxBatches(
      businessId: businessId,
      branchId: branchId,
    );

    final registers = await _dao.getPendingDirtyCashRegisters(
      businessId: businessId,
      branchId: branchId,
      limit: limit,
    );

    final sessions = await _dao.getPendingDirtyCashSessions(
      businessId: businessId,
      branchId: branchId,
      limit: limit,
    );

    final mutations = <LocalSyncMutationDraft>[];
    final results = <Map<String, dynamic>>[];
    var sequence = _safeClientSequence();

    for (final register in registers) {
      final id = _requiredString(register, 'id');
      final payload = _cashRegisterPayload(register, profileId: profileId);

      mutations.add(
        LocalSyncMutationDraft(
          clientMutationId: _clientMutationId(
            deviceInstallationId: deviceInstallationId,
            profileId: profileId,
            entityTable: 'cash_registers',
            entityId: id,
          ),
          clientSequence: sequence++,
          entityTable: 'cash_registers',
          entityId: id,
          operation: 'insert',
          payload: payload,
          changedFields: payload.keys.toList(),
          idempotencyKey: _idempotencyKey(
            register,
            fallback:
                '${deviceInstallationId ?? profileId}:cash_registers:$id:insert',
          ),
          businessId: businessId,
          branchId: branchId,
          profileId: profileId,
          appDeviceId: appDeviceId,
          metadata: {
            'source': 'cash_sync_outbox_service',
            'domain': 'cash',
            'entity_table': 'cash_registers',
            'cash_register_id': id,
          },
        ),
      );

      results.add({
        'entity_table': 'cash_registers',
        'entity_id': id,
        'status': 'prepared',
      });
    }

    for (final session in sessions) {
      final id = _requiredString(session, 'id');
      final payload = _cashSessionPayload(session, profileId: profileId);

      mutations.add(
        LocalSyncMutationDraft(
          clientMutationId: _cashSessionClientMutationId(
            session,
            profileId: profileId,
            deviceInstallationId: deviceInstallationId,
            id: id,
          ),
          clientSequence: sequence++,
          entityTable: 'cash_sessions',
          entityId: id,
          operation: _cashSessionOperation(session),
          payload: payload,
          changedFields: payload.keys.toList(),
          idempotencyKey: _cashSessionIdempotencyKey(
            session,
            profileId: profileId,
            deviceInstallationId: deviceInstallationId,
            id: id,
          ),
          businessId: businessId,
          branchId: branchId,
          profileId: profileId,
          appDeviceId: appDeviceId,
          metadata: {
            'source': 'cash_sync_outbox_service',
            'domain': 'cash',
            'entity_table': 'cash_sessions',
            'cash_session_id': id,
            'cash_register_id': _nullableString(session['cash_register_id']),
          },
        ),
      );

      results.add({
        'entity_table': 'cash_sessions',
        'entity_id': id,
        'cash_register_id': _nullableString(session['cash_register_id']),
        'status': 'prepared',
      });
    }

    if (mutations.isEmpty) {
      return CashSyncOutboxResult(
        businessId: businessId,
        branchId: branchId,
        cashRegistersChecked: registers.length,
        cashSessionsChecked: sessions.length,
        batchesCreated: 0,
        mutationsEnqueued: 0,
        results: [
          {
            'status': 'nothing_to_enqueue',
            'reason': 'no_dirty_cash_registers_or_sessions',
          },
        ],
      );
    }

    final enqueueResult = await _outboxService.enqueueUploadBatch(
      businessId: businessId,
      branchId: branchId,
      profileId: profileId,
      appDeviceId: appDeviceId,
      deviceInstallationId: deviceInstallationId,
      domain: 'cash',
      mutations: mutations,
      metadata: {
        'source': 'cash_sync_outbox_service',
        'domain': 'cash',
        'cash_register_count': registers.length,
        'cash_session_count': sessions.length,
        'upload_order': [
          'cash_registers',
          'cash_sessions',
          'pos_after_cash',
        ],
      },
    );

    results.add({
      'status': 'enqueued',
      'mutation_count': mutations.length,
      'outbox_result': enqueueResult.toJson(),
    });

    return CashSyncOutboxResult(
      businessId: businessId,
      branchId: branchId,
      cashRegistersChecked: registers.length,
      cashSessionsChecked: sessions.length,
      batchesCreated: 1,
      mutationsEnqueued: mutations.length,
      results: results,
    );
  }

  String _cashSessionClientMutationId(
    Map<String, dynamic> session, {
    required String profileId,
    required String? deviceInstallationId,
    required String id,
  }) {
    final status = _nullableString(session['status']);
    final lastSyncedAt = _nullableString(session['last_synced_at']);
    final version = _int(session['version'], fallback: 1);
    final base = deviceInstallationId ?? profileId;

    // Si nunca se ha sincronizado al servidor, sigue siendo una mutación insert,
    // aunque localmente la sesión ya esté cerrada.
    if (lastSyncedAt == null || lastSyncedAt.trim().isEmpty) {
      return '$base:cash_sessions:$id:insert:v$version';
    }

    // Si ya existía en servidor y ahora se cerró/canceló, es mutación de cierre.
    if (status == 'closed' || status == 'cancelled') {
      return '$base:cash_sessions:$id:close:v$version';
    }

    return '$base:cash_sessions:$id:insert:v$version';
  }

  String _cashSessionOperation(Map<String, dynamic> session) {
    final status = _nullableString(session['status']);
    final lastSyncedAt = _nullableString(session['last_synced_at']);

    // Si nunca se ha sincronizado al servidor, debe ir como insert,
    // aunque localmente ya esté cerrada.
    if (lastSyncedAt == null || lastSyncedAt.trim().isEmpty) {
      return 'insert';
    }

    // Si ya existía en servidor y ahora está cerrada/cancelada, es update.
    if (status == 'closed' || status == 'cancelled') {
      return 'update';
    }

    return 'insert';
  }

  String _cashSessionIdempotencyKey(
    Map<String, dynamic> session, {
    required String profileId,
    required String? deviceInstallationId,
    required String id,
  }) {
    final status = _nullableString(session['status']);
    final lastSyncedAt = _nullableString(session['last_synced_at']);
    final version = _int(session['version'], fallback: 1);
    final base = deviceInstallationId ?? profileId;

    if ((status == 'closed' || status == 'cancelled') &&
        lastSyncedAt != null &&
        lastSyncedAt.trim().isNotEmpty) {
      return '$base:cash_sessions:$id:close:v$version';
    }

    return _idempotencyKey(
      session,
      fallback: '$base:cash_sessions:$id:insert',
    );
  }

  Map<String, dynamic> _cashRegisterPayload(
    Map<String, dynamic> register, {
    required String profileId,
  }) {
    return {
      'id': _requiredString(register, 'id'),
      'business_id': _requiredString(register, 'business_id'),
      'branch_id': _requiredString(register, 'branch_id'),
      'name': _nullableString(register['name']) ?? 'Caja principal',
      'code': _nullableString(register['code']),
      'status': _nullableString(register['status']) ?? 'active',
      'profile_id': profileId,
      'created_by': profileId,
      'updated_by': profileId,
      'version': _int(register['version'], fallback: 1),
      'sync_status': 'pending',
      'metadata': _metadata(register['metadata_json']),
      'created_at': _iso(register['created_at']),
      'updated_at': _iso(register['updated_at']),
      'deleted_at': _nullableIso(register['deleted_at']),
    };
  }

  Map<String, dynamic> _cashSessionPayload(
    Map<String, dynamic> session, {
    required String profileId,
  }) {
    return {
      'id': _requiredString(session, 'id'),
      'business_id': _requiredString(session, 'business_id'),
      'branch_id': _requiredString(session, 'branch_id'),
      'cash_register_id': _requiredString(session, 'cash_register_id'),
      'opened_by':
          _nullableString(session['opened_by_profile_id']) ?? profileId,
      'opened_by_profile_id':
          _nullableString(session['opened_by_profile_id']) ?? profileId,
      'closed_by': _nullableString(session['closed_by_profile_id']),
      'closed_by_profile_id': _nullableString(session['closed_by_profile_id']),
      'opening_amount': _double(session['opening_cash_amount']),
      'opening_cash_amount': _double(session['opening_cash_amount']),
      'expected_closing_amount': _nullableDouble(
        session['expected_cash_amount'],
      ),
      'expected_cash_amount': _nullableDouble(session['expected_cash_amount']),
      'actual_closing_amount': _nullableDouble(
        session['closing_cash_amount'],
      ),
      'closing_cash_amount': _nullableDouble(session['closing_cash_amount']),
      'difference_amount': _nullableDouble(session['difference_amount']),
      'status': _nullableString(session['status']) ?? 'open',
      'opened_at': _iso(session['opened_at']),
      'closed_at': _nullableIso(session['closed_at']),
      'profile_id': profileId,
      'version': _int(session['version'], fallback: 1),
      'sync_status': 'pending',
      'metadata': _metadata(session['metadata_json']),
      'created_at': _iso(session['created_at']),
      'updated_at': _iso(session['updated_at']),
      'deleted_at': _nullableIso(session['deleted_at']),
    };
  }

  String _clientMutationId({
    required String? deviceInstallationId,
    required String profileId,
    required String entityTable,
    required String entityId,
  }) {
    return '${deviceInstallationId ?? profileId}:$entityTable:$entityId:mutation';
  }

  String _idempotencyKey(
    Map<String, dynamic> map, {
    required String fallback,
  }) {
    return _nullableString(map['idempotency_key']) ?? fallback;
  }

  Map<String, dynamic> _metadata(Object? value) {
    if (value == null) {
      return {};
    }

    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);

      if (decoded is Map<String, dynamic>) {
        return decoded;
      }

      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    }

    return {};
  }

  int _safeClientSequence() {
    final value =
        DateTime.now().toUtc().microsecondsSinceEpoch.remainder(2000000000);

    if (value < 1) {
      return 1;
    }

    return value;
  }

  String _requiredString(Map<String, dynamic> source, String key) {
    final value = _nullableString(source[key]);

    if (value == null) {
      throw ArgumentError('Campo requerido ausente: $key');
    }

    return value;
  }

  String? _nullableString(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }

  int _int(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  double _double(Object? value) {
    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  double? _nullableDouble(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is double) {
      return value;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString());
  }

  String _iso(Object? value) {
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }

    final parsed = DateTime.tryParse(value?.toString() ?? '');

    if (parsed == null) {
      return DateTime.now().toUtc().toIso8601String();
    }

    return parsed.toUtc().toIso8601String();
  }

  String? _nullableIso(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }

    return DateTime.tryParse(value.toString())?.toUtc().toIso8601String();
  }
}
