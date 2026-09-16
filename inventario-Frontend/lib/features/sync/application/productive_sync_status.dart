class ProductiveSyncScope {
  const ProductiveSyncScope({
    required this.profileId,
    required this.businessId,
    required this.branchId,
  });

  final String profileId;
  final String businessId;
  final String branchId;
}

enum ProductiveSyncConnectivity {
  online,
  offline,
}

class ProductiveSyncStatus {
  const ProductiveSyncStatus({
    required this.scope,
    required this.connectivity,
    required this.isSyncing,
    required this.pendingSales,
    required this.pendingPurchases,
    required this.pendingCashOperations,
    required this.pendingProductOperations,
    required this.pendingInventoryOperations,
    required this.openIssueCount,
    required this.attentionOperationCount,
  });

  final ProductiveSyncScope scope;
  final ProductiveSyncConnectivity connectivity;
  final bool isSyncing;
  final int pendingSales;
  final int pendingPurchases;
  final int pendingCashOperations;
  final int pendingProductOperations;
  final int pendingInventoryOperations;
  final int openIssueCount;
  final int attentionOperationCount;

  bool get isOnline => connectivity == ProductiveSyncConnectivity.online;

  bool get requiresAttention {
    return openIssueCount > 0 || attentionOperationCount > 0;
  }

  int get totalPending {
    return pendingSales +
        pendingPurchases +
        pendingCashOperations +
        pendingProductOperations +
        pendingInventoryOperations;
  }

  bool get allUpToDate {
    return isOnline && !isSyncing && totalPending == 0 && !requiresAttention;
  }
}

typedef ProductivePendingOperationsLoader = Future<List<Map<String, dynamic>>>
    Function({
  required String businessId,
  required String branchId,
});

typedef ProductiveCashReadinessLoader = Future<Map<String, dynamic>> Function({
  required String businessId,
  required String branchId,
});

typedef ProductiveOpenIssuesLoader = Future<List<Map<String, dynamic>>>
    Function({
  required String profileId,
  required String businessId,
  required String branchId,
});

typedef ProductiveOutboxStatusRowsLoader = Future<List<Map<String, dynamic>>>
    Function({
  required String businessId,
  required String branchId,
});

typedef ProductiveBlockedPurchaseDependenciesLoader = Future<int> Function({
  required String businessId,
  required String branchId,
});

class ProductiveSyncStatusService {
  const ProductiveSyncStatusService({
    required ProductivePendingOperationsLoader pendingSalesLoader,
    required ProductivePendingOperationsLoader pendingPurchasesLoader,
    required ProductiveCashReadinessLoader cashReadinessLoader,
    required ProductiveOpenIssuesLoader openIssuesLoader,
    required ProductiveOutboxStatusRowsLoader outboxStatusRowsLoader,
    required ProductiveBlockedPurchaseDependenciesLoader
        blockedPurchaseDependenciesLoader,
  })  : _pendingSalesLoader = pendingSalesLoader,
        _pendingPurchasesLoader = pendingPurchasesLoader,
        _cashReadinessLoader = cashReadinessLoader,
        _openIssuesLoader = openIssuesLoader,
        _outboxStatusRowsLoader = outboxStatusRowsLoader,
        _blockedPurchaseDependenciesLoader = blockedPurchaseDependenciesLoader;

  final ProductivePendingOperationsLoader _pendingSalesLoader;
  final ProductivePendingOperationsLoader _pendingPurchasesLoader;
  final ProductiveCashReadinessLoader _cashReadinessLoader;
  final ProductiveOpenIssuesLoader _openIssuesLoader;
  final ProductiveOutboxStatusRowsLoader _outboxStatusRowsLoader;
  final ProductiveBlockedPurchaseDependenciesLoader
      _blockedPurchaseDependenciesLoader;

  Future<ProductiveSyncStatus> load({
    required ProductiveSyncScope scope,
    required bool isOnline,
    required bool isSyncing,
  }) async {
    final pendingSales = await _pendingSalesLoader(
      businessId: scope.businessId,
      branchId: scope.branchId,
    );
    final pendingPurchases = await _pendingPurchasesLoader(
      businessId: scope.businessId,
      branchId: scope.branchId,
    );
    final cashReadiness = await _cashReadinessLoader(
      businessId: scope.businessId,
      branchId: scope.branchId,
    );
    final openIssues = await _openIssuesLoader(
      profileId: scope.profileId,
      businessId: scope.businessId,
      branchId: scope.branchId,
    );
    final outboxRows = await _outboxStatusRowsLoader(
      businessId: scope.businessId,
      branchId: scope.branchId,
    );
    final blockedPurchaseDependencies =
        await _blockedPurchaseDependenciesLoader(
      businessId: scope.businessId,
      branchId: scope.branchId,
    );

    final outboxSummary = _summarizeOutbox(outboxRows);
    final pendingSalesWithoutCash =
        _int(cashReadiness['pending_sales_without_cash_count']);

    return ProductiveSyncStatus(
      scope: scope,
      connectivity: isOnline
          ? ProductiveSyncConnectivity.online
          : ProductiveSyncConnectivity.offline,
      isSyncing: isSyncing,
      pendingSales: _distinctEntityCount(pendingSales),
      pendingPurchases: _distinctEntityCount(pendingPurchases),
      pendingCashOperations: _int(cashReadiness['dirty_cash_register_count']) +
          _int(cashReadiness['dirty_cash_session_count']),
      pendingProductOperations: outboxSummary.pendingProductOperations,
      pendingInventoryOperations: outboxSummary.pendingInventoryOperations,
      openIssueCount: openIssues.length,
      attentionOperationCount: outboxSummary.attentionOperationCount +
          blockedPurchaseDependencies +
          pendingSalesWithoutCash,
    );
  }
}

_ProductiveOutboxSummary _summarizeOutbox(
  List<Map<String, dynamic>> rows,
) {
  final productBatchIds = <String>{};
  final inventoryBatchIds = <String>{};
  final attentionBatchIds = <String>{};

  for (final row in rows) {
    final batchId = _text(row['batch_id']);
    final domain = _text(row['domain']);
    final batchStatus = _text(row['batch_status']);
    final mutationStatus = _text(row['mutation_status']);
    final entityTable = _text(row['entity_table']);

    if (batchId == null) {
      continue;
    }

    final isPendingTransport = batchStatus == 'pending' ||
        batchStatus == 'uploading' ||
        batchStatus == 'error';
    final isPendingMutation =
        mutationStatus == 'pending' || mutationStatus == 'error';

    if (isPendingTransport && isPendingMutation) {
      if (domain == 'catalog' &&
          (entityTable == 'products' || entityTable == 'product_barcodes')) {
        productBatchIds.add(batchId);
      }
      if (domain == 'inventory') {
        inventoryBatchIds.add(batchId);
      }
    }

    if (batchStatus == 'partial' ||
        batchStatus == 'conflict' ||
        mutationStatus == 'conflict' ||
        mutationStatus == 'rejected') {
      attentionBatchIds.add(batchId);
    }
  }

  return _ProductiveOutboxSummary(
    pendingProductOperations: productBatchIds.length,
    pendingInventoryOperations: inventoryBatchIds.length,
    attentionOperationCount: attentionBatchIds.length,
  );
}

int _distinctEntityCount(List<Map<String, dynamic>> rows) {
  return rows.map((row) => _text(row['id'])).whereType<String>().toSet().length;
}

int _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

class _ProductiveOutboxSummary {
  const _ProductiveOutboxSummary({
    required this.pendingProductOperations,
    required this.pendingInventoryOperations,
    required this.attentionOperationCount,
  });

  final int pendingProductOperations;
  final int pendingInventoryOperations;
  final int attentionOperationCount;
}
