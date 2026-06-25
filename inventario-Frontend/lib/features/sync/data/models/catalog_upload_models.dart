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
      'raw': raw,
    };
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
