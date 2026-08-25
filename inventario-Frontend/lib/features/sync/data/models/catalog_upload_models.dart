class CatalogUploadBatchResult {
  const CatalogUploadBatchResult({
    required this.localBatchId,
    required this.serverBatchId,
    required this.status,
    required this.mutationCount,
    required this.appliedCount,
    required this.skippedCount,
    required this.conflictCount,
    required this.errorCount,
    required this.raw,
    this.mutationResults = const [],
  });

  final String localBatchId;
  final String serverBatchId;
  final String status;
  final int mutationCount;
  final int appliedCount;
  final int skippedCount;
  final int conflictCount;
  final int errorCount;
  final Map<String, dynamic> raw;
  final List<CatalogUploadMutationResult> mutationResults;

  bool get completed =>
      status == 'completed' && errorCount == 0 && conflictCount == 0;

  bool get partial =>
      status == 'partial' || conflictCount > 0 || errorCount > 0;

  Map<String, dynamic> toJson() {
    return {
      'local_batch_id': localBatchId,
      'server_batch_id': serverBatchId,
      'status': status,
      'mutation_count': mutationCount,
      'applied_count': appliedCount,
      'skipped_count': skippedCount,
      'conflict_count': conflictCount,
      'error_count': errorCount,
      'mutation_results': mutationResults
          .map((result) => result.toJson())
          .toList(growable: false),
      'raw': raw,
    };
  }

  CatalogUploadBatchResult withMutationResults(
    List<CatalogUploadMutationResult> results,
  ) {
    return CatalogUploadBatchResult(
      localBatchId: localBatchId,
      serverBatchId: serverBatchId,
      status: status,
      mutationCount: mutationCount,
      appliedCount: appliedCount,
      skippedCount: skippedCount,
      conflictCount: conflictCount,
      errorCount: errorCount,
      raw: raw,
      mutationResults: List.unmodifiable(results),
    );
  }

  factory CatalogUploadBatchResult.fromProcessResult({
    required String localBatchId,
    required String serverBatchId,
    required int fallbackMutationCount,
    required dynamic value,
  }) {
    final map = _asMap(value);

    final status = _string(map['status']) ?? 'completed';
    final mutationCount = _int(map['mutation_count']) ?? fallbackMutationCount;
    final appliedCount = _int(map['applied_count']) ?? mutationCount;
    final skippedCount = _int(map['skipped_count']) ?? 0;
    final conflictCount = _int(map['conflict_count']) ?? 0;
    final errorCount = _int(map['error_count']) ?? 0;

    return CatalogUploadBatchResult(
      localBatchId: localBatchId,
      serverBatchId: serverBatchId,
      status: status,
      mutationCount: mutationCount,
      appliedCount: appliedCount,
      skippedCount: skippedCount,
      conflictCount: conflictCount,
      errorCount: errorCount,
      raw: map,
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return {
      'status': 'completed',
      'raw_value': value?.toString(),
    };
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
}

class CatalogUploadMutationResult {
  const CatalogUploadMutationResult({
    required this.serverMutationId,
    required this.idempotencyKey,
    required this.entityTable,
    required this.entityId,
    required this.status,
    this.errorCode,
    this.errorMessage,
  });

  final String serverMutationId;
  final String idempotencyKey;
  final String entityTable;
  final String entityId;
  final String status;
  final String? errorCode;
  final String? errorMessage;

  Map<String, dynamic> toJson() {
    return {
      'server_mutation_id': serverMutationId,
      'idempotency_key': idempotencyKey,
      'entity_table': entityTable,
      'entity_id': entityId,
      'status': status,
      'error_code': errorCode,
      'error_message': errorMessage,
    };
  }
}

class CatalogUploadRunResult {
  const CatalogUploadRunResult({
    required this.batchesChecked,
    required this.batchesUploaded,
    required this.batchesCompleted,
    required this.batchesPartial,
    required this.batchesFailed,
    required this.mutationsUploaded,
  });

  final int batchesChecked;
  final int batchesUploaded;
  final int batchesCompleted;
  final int batchesPartial;
  final int batchesFailed;
  final int mutationsUploaded;

  Map<String, dynamic> toJson() {
    return {
      'batches_checked': batchesChecked,
      'batches_uploaded': batchesUploaded,
      'batches_completed': batchesCompleted,
      'batches_partial': batchesPartial,
      'batches_failed': batchesFailed,
      'mutations_uploaded': mutationsUploaded,
    };
  }
}
