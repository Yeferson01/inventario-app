import 'dart:convert';

import '../../../core/database/app_database.dart';
import '../data/datasources/purchase_product_dependency_local_dao.dart';

enum PurchaseProductDependencyStatus {
  satisfied,
  waiting,
  blocked,
}

class PurchaseProductDependencyIssue {
  const PurchaseProductDependencyIssue({
    required this.code,
    required this.message,
    this.productId,
  });

  final String code;
  final String message;
  final String? productId;

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'message': message,
      'product_id': productId,
    };
  }
}

class PurchaseProductDependencyResolution {
  const PurchaseProductDependencyResolution({
    required this.status,
    required this.requiredProductIds,
    this.waitingProductIds = const [],
    this.blockedProductIds = const [],
    this.issues = const [],
  });

  final PurchaseProductDependencyStatus status;
  final List<String> requiredProductIds;
  final List<String> waitingProductIds;
  final List<String> blockedProductIds;
  final List<PurchaseProductDependencyIssue> issues;

  bool get satisfied => status == PurchaseProductDependencyStatus.satisfied;
}

class PurchaseProductDependencyResolver {
  PurchaseProductDependencyResolver(this._localDao);

  final PurchaseProductDependencyLocalDao _localDao;

  Future<PurchaseProductDependencyResolution> resolve({
    required String businessId,
    required List<Map<String, dynamic>> purchaseMutations,
  }) async {
    final normalizedBusinessId = businessId.trim();
    if (normalizedBusinessId.isEmpty) {
      throw ArgumentError('businessId es requerido.');
    }

    final extraction = _extractRequiredProductIds(
      businessId: normalizedBusinessId,
      mutations: purchaseMutations,
    );
    if (extraction.issues.isNotEmpty) {
      return PurchaseProductDependencyResolution(
        status: PurchaseProductDependencyStatus.blocked,
        requiredProductIds: extraction.productIds.toList()..sort(),
        issues: extraction.issues,
      );
    }

    if (extraction.productIds.isEmpty) {
      return const PurchaseProductDependencyResolution(
        status: PurchaseProductDependencyStatus.satisfied,
        requiredProductIds: [],
      );
    }

    final products = await _localDao.getProducts(
      businessId: normalizedBusinessId,
      productIds: extraction.productIds,
    );
    final evidence = await _localDao.getCatalogProductMutationEvidence(
      businessId: normalizedBusinessId,
      productIds: extraction.productIds,
    );

    final productsById = {
      for (final product in products) _requiredString(product, 'id'): product,
    };
    final evidenceByProduct = <String, List<Map<String, dynamic>>>{};
    for (final row in evidence) {
      final productId = _requiredString(row, 'product_id');
      evidenceByProduct.putIfAbsent(productId, () => []).add(row);
    }

    final waiting = <String>[];
    final blocked = <String>[];
    final issues = <PurchaseProductDependencyIssue>[];

    final sortedIds = extraction.productIds.toList()..sort();
    for (final productId in sortedIds) {
      final product = productsById[productId];
      if (product == null) {
        blocked.add(productId);
        issues.add(
          PurchaseProductDependencyIssue(
            code: 'product_not_in_purchase_business',
            productId: productId,
            message:
                'El Product requerido no existe localmente en el business de la compra.',
          ),
        );
        continue;
      }

      if (product['deleted_at'] != null) {
        blocked.add(productId);
        issues.add(
          PurchaseProductDependencyIssue(
            code: 'product_soft_deleted',
            productId: productId,
            message:
                'El Product requerido está soft-deleted; el backend actual no acepta nuevos purchase_items para Products eliminados.',
          ),
        );
        continue;
      }

      final productEvidence = evidenceByProduct[productId] ?? const [];
      if (_hasAppliedEvidence(productEvidence)) {
        continue;
      }

      if (productEvidence.isEmpty &&
          product['sync_status'] == SyncStatus.synced.index) {
        // Products materialized by an authoritative pull/bootstrap have no
        // local catalog mutation. The absence of outbox history is part of
        // this evidence; a synced flag never overrides pending/error history.
        continue;
      }

      final terminal = productEvidence.where(_isTerminalFailure).toList();
      if (terminal.isNotEmpty) {
        blocked.add(productId);
        final first = terminal.first;
        issues.add(
          PurchaseProductDependencyIssue(
            code: 'product_dependency_${first['mutation_status']}',
            productId: productId,
            message: _string(first['last_error']) ??
                'La mutación del Product no fue aplicada remotamente.',
          ),
        );
        continue;
      }

      if (productEvidence.any(_isClearlyPending)) {
        waiting.add(productId);
        continue;
      }

      blocked.add(productId);
      issues.add(
        PurchaseProductDependencyIssue(
          code: productEvidence.isEmpty
              ? 'dirty_product_without_outbox'
              : 'product_dependency_ambiguous',
          productId: productId,
          message: productEvidence.isEmpty
              ? 'El Product local no tiene evidencia remota ni mutación de catálogo durable.'
              : 'El estado de transporte del Product no demuestra que exista remotamente.',
        ),
      );
    }

    final status = blocked.isNotEmpty
        ? PurchaseProductDependencyStatus.blocked
        : waiting.isNotEmpty
            ? PurchaseProductDependencyStatus.waiting
            : PurchaseProductDependencyStatus.satisfied;

    return PurchaseProductDependencyResolution(
      status: status,
      requiredProductIds: sortedIds,
      waitingProductIds: List.unmodifiable(waiting),
      blockedProductIds: List.unmodifiable(blocked),
      issues: List.unmodifiable(issues),
    );
  }

  _ProductIdExtraction _extractRequiredProductIds({
    required String businessId,
    required List<Map<String, dynamic>> mutations,
  }) {
    final productIds = <String>{};
    final issues = <PurchaseProductDependencyIssue>[];

    for (final mutation in mutations) {
      if (_string(mutation['entity_table']) != 'purchase_items') {
        continue;
      }

      final mutationBusinessId = _string(mutation['business_id']);
      final payload = _decodePayload(mutation);
      final payloadBusinessId = _string(payload['business_id']);
      final productId = _string(payload['product_id']);

      if (mutationBusinessId != businessId ||
          (payloadBusinessId != null && payloadBusinessId != businessId)) {
        issues.add(
          PurchaseProductDependencyIssue(
            code: 'purchase_item_business_scope_mismatch',
            productId: productId,
            message:
                'La mutación purchase_item no pertenece al business solicitado.',
          ),
        );
        continue;
      }

      if (productId == null) {
        issues.add(
          const PurchaseProductDependencyIssue(
            code: 'purchase_item_product_id_missing',
            message: 'La mutación purchase_item no contiene product_id.',
          ),
        );
        continue;
      }

      productIds.add(productId);
    }

    return _ProductIdExtraction(productIds: productIds, issues: issues);
  }

  bool _hasAppliedEvidence(List<Map<String, dynamic>> evidence) {
    return evidence.any((row) {
      final mutationStatus = _string(row['mutation_status']);
      final operation = _string(row['mutation_operation']);
      final batchStatus = _string(row['batch_status']);
      final serverMutationId = _string(row['server_sync_mutation_id']);
      final acknowledgedByCompletedBatch = batchStatus == 'completed';
      final acknowledgedInsidePartialBatch =
          batchStatus == 'partial' && serverMutationId != null;
      return mutationStatus == 'applied' &&
          operation != 'delete' &&
          (acknowledgedByCompletedBatch || acknowledgedInsidePartialBatch);
    });
  }

  bool _isClearlyPending(Map<String, dynamic> evidence) {
    final mutationStatus = _string(evidence['mutation_status']);
    final batchStatus = _string(evidence['batch_status']);
    return mutationStatus == 'pending' &&
        (batchStatus == 'pending' ||
            batchStatus == 'uploading' ||
            batchStatus == 'error');
  }

  bool _isTerminalFailure(Map<String, dynamic> evidence) {
    final status = _string(evidence['mutation_status']);
    return status == 'conflict' || status == 'error' || status == 'skipped';
  }

  Map<String, dynamic> _decodePayload(Map<String, dynamic> mutation) {
    final raw = mutation['payload_json'] ?? mutation['payload'];
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        return const {};
      }
    }
    return const {};
  }

  String _requiredString(Map<String, dynamic> source, String key) {
    final value = _string(source[key]);
    if (value == null) {
      throw StateError('Evidencia local incompleta: $key');
    }
    return value;
  }

  String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class _ProductIdExtraction {
  const _ProductIdExtraction({
    required this.productIds,
    required this.issues,
  });

  final Set<String> productIds;
  final List<PurchaseProductDependencyIssue> issues;
}
