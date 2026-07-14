import 'dart:convert';

class LocalSyncMutationDraft {
  const LocalSyncMutationDraft({
    required this.clientMutationId,
    required this.clientSequence,
    required this.entityTable,
    required this.entityId,
    required this.operation,
    required this.payload,
    required this.changedFields,
    required this.idempotencyKey,
    this.businessId,
    this.branchId,
    this.profileId,
    this.appDeviceId,
    this.beforePayload,
    this.baseVersion,
    this.baseUpdatedAt,
    this.metadata,
  });

  final String clientMutationId;
  final int clientSequence;
  final String entityTable;
  final String entityId;
  final String operation;
  final Map<String, dynamic> payload;
  final List<String> changedFields;
  final String idempotencyKey;

  final String? businessId;
  final String? branchId;
  final String? profileId;
  final String? appDeviceId;

  final Map<String, dynamic>? beforePayload;
  final int? baseVersion;
  final DateTime? baseUpdatedAt;
  final Map<String, dynamic>? metadata;

  factory LocalSyncMutationDraft.fromJson(Map<String, dynamic> json) {
    return LocalSyncMutationDraft(
      clientMutationId: _requiredString(json, 'client_mutation_id'),
      clientSequence: _int(json['client_sequence']) ?? 1,
      entityTable: _requiredString(json, 'entity_table'),
      entityId: _requiredString(json, 'entity_id'),
      operation: _requiredString(json, 'operation'),
      payload: _map(json['payload']),
      changedFields: _stringList(json['changed_fields']),
      idempotencyKey: _requiredString(json, 'idempotency_key'),
      businessId: _string(json['business_id']),
      branchId: _string(json['branch_id']),
      profileId: _string(json['profile_id']),
      appDeviceId: _string(json['app_device_id']),
      beforePayload: _nullableMap(json['before_payload']),
      baseVersion: _int(json['base_version']),
      baseUpdatedAt: _dateTime(json['base_updated_at']),
      metadata: _nullableMap(json['metadata']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'client_mutation_id': clientMutationId,
      'client_sequence': clientSequence,
      'entity_table': entityTable,
      'entity_id': entityId,
      'operation': operation,
      'payload': payload,
      'changed_fields': changedFields,
      'idempotency_key': idempotencyKey,
      'business_id': businessId,
      'branch_id': branchId,
      'profile_id': profileId,
      'app_device_id': appDeviceId,
      'before_payload': beforePayload,
      'base_version': baseVersion,
      'base_updated_at': baseUpdatedAt?.toUtc().toIso8601String(),
      'metadata': metadata,
    };
  }

  String get payloadJson => jsonEncode(payload);

  String? get beforePayloadJson {
    if (beforePayload == null) {
      return null;
    }

    return jsonEncode(beforePayload);
  }

  String get changedFieldsJson => jsonEncode(changedFields);

  String? get metadataJson {
    if (metadata == null) {
      return null;
    }

    return jsonEncode(metadata);
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = _string(json[key]);

    if (value == null) {
      throw ArgumentError('Campo requerido ausente en mutation draft: $key');
    }

    return value;
  }

  static String? _string(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }

  static int? _int(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString());
  }

  static DateTime? _dateTime(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value.toUtc();
    }

    return DateTime.tryParse(value.toString())?.toUtc();
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    throw ArgumentError('payload debe ser Map<String, dynamic>.');
  }

  static Map<String, dynamic>? _nullableMap(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return null;
  }

  static List<String> _stringList(Object? value) {
    if (value is List) {
      return value.map((item) => item.toString()).toList();
    }

    return <String>[];
  }
}

class LocalSyncEnqueueResult {
  const LocalSyncEnqueueResult({
    required this.localBatchId,
    required this.clientBatchId,
    required this.domain,
    required this.mutationCount,
  });

  final String localBatchId;
  final String clientBatchId;
  final String domain;
  final int mutationCount;

  Map<String, dynamic> toJson() {
    return {
      'local_batch_id': localBatchId,
      'client_batch_id': clientBatchId,
      'domain': domain,
      'mutation_count': mutationCount,
    };
  }
}
