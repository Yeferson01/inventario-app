import 'dart:convert';

import '../data/datasources/catalog_entity_sync_state_resolver.dart';
import '../data/datasources/operational_bootstrap_seen_record_local_dao.dart';
import '../data/datasources/reconciliation_issue_local_dao.dart';
import '../data/models/catalog_entity_reconciliation_models.dart';
import '../data/models/local_recovery_models.dart';
import '../data/models/operational_bootstrap_models.dart';
import '../data/models/product_operational_snapshot_models.dart';

class ProductOperationalReconciliationSupport {
  ProductOperationalReconciliationSupport({
    required CatalogEntitySyncStateResolver stateResolver,
    required ReconciliationIssueLocalDao issueDao,
    required OperationalBootstrapSeenRecordLocalDao seenRecordDao,
  })  : _stateResolver = stateResolver,
        _issueDao = issueDao,
        _seenRecordDao = seenRecordDao;

  final CatalogEntitySyncStateResolver _stateResolver;
  final ReconciliationIssueLocalDao _issueDao;
  final OperationalBootstrapSeenRecordLocalDao _seenRecordDao;

  void validatePage(
    OperationalBootstrapSnapshotPage snapshot,
    OperationalBootstrapDatasetPage page,
    String expectedDataset,
  ) {
    if (snapshot.bundle != 'product_operational' ||
        page.dataset != expectedDataset ||
        !snapshot.datasets.containsKey(page.dataset) ||
        page.dataset == 'product_stock_balances') {
      throw OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.malformedResponse,
        message:
            'Product operational applier rejected ${snapshot.bundle}/${page.dataset}.',
      );
    }
  }

  void validateBusiness(String expectedBusinessId, String actualBusinessId) {
    if (expectedBusinessId != actualBusinessId) {
      throw const OperationalBootstrapException(
        kind: OperationalBootstrapFailureKind.scopeMismatch,
        message: 'Product operational row belongs to another business.',
      );
    }
  }

  Future<CatalogEntityReconciliationClassification> classify(
    String businessId,
    String entityTable,
    Map<String, dynamic> local,
  ) {
    return _stateResolver.classify(
      businessId: businessId,
      entityTable: entityTable,
      entityId: local['id'].toString(),
      syncStatus: local['sync_status'],
      localStatus: local['local_status'],
      localUpdatedAt: local['updated_at'],
    );
  }

  Future<Set<String>> seenIds({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required String dataset,
  }) async {
    return (await _seenRecordDao.getEntityIds(
      snapshotId: snapshot.snapshotId,
      profileId: profileId,
      businessId: snapshot.businessId,
      branchId: snapshot.branchId,
      bundle: snapshot.bundle,
      dataset: dataset,
    ))
        .toSet();
  }

  Future<void> openIssue({
    required String profileId,
    required OperationalBootstrapSnapshotPage snapshot,
    required String entityType,
    required String entityId,
    required String issueType,
    required String severity,
    required String message,
    required CatalogEntityReconciliationClassification classification,
  }) async {
    await _issueDao.openOrUpdateIssue(
      ReconciliationIssueDraft(
        profileId: profileId,
        businessId: snapshot.businessId,
        branchId: snapshot.branchId,
        domain: 'catalog',
        entityType: entityType,
        entityId: entityId,
        issueType: issueType,
        severity: severity,
        message: message,
        metadataJson: jsonEncode({
          'snapshot_id': snapshot.snapshotId,
          'dataset': entityType,
          'classification': classification.state.name,
        }),
      ),
    );
  }

  bool outsideSnapshotIdentityWindow(
    Map<String, dynamic> local,
    CatalogEntityReconciliationClassification classification,
    DateTime snapshotAt,
  ) {
    final createdAt = dateTime(local['created_at']);
    return (createdAt != null && createdAt.isAfter(snapshotAt)) ||
        (classification.recognizedAt != null &&
            classification.recognizedAt!.isAfter(snapshotAt));
  }

  bool categoryEquivalent(
    Map<String, dynamic> local,
    ProductOperationalCategorySnapshot remote,
  ) {
    return _string(local['business_id']) == remote.businessId &&
        _string(local['name']) == remote.name &&
        _string(local['description']) == remote.description &&
        _sameDate(local['deleted_at'], remote.deletedAt);
  }

  bool productEquivalent(
    Map<String, dynamic> local,
    ProductOperationalProductSnapshot remote,
  ) {
    return _string(local['business_id']) == remote.businessId &&
        _string(local['category_id']) == remote.categoryId &&
        _string(local['barcode']) == remote.barcode &&
        _string(local['name']) == remote.name &&
        _string(local['description']) == remote.description &&
        _double(local['purchase_price']) == remote.purchasePrice &&
        _double(local['sale_price']) == remote.salePrice &&
        _int(local['stock_quantity']) == remote.stockQuantity &&
        _int(local['minimum_stock']) == remote.minimumStock &&
        _string(local['unit']) == remote.unit &&
        _string(local['status']) == remote.status &&
        _string(local['simple_category']) == remote.simpleCategory &&
        _sameDate(local['deleted_at'], remote.deletedAt);
  }

  bool barcodeEquivalent(
    Map<String, dynamic> local,
    ProductOperationalBarcodeSnapshot remote,
  ) {
    return _string(local['scope']) == remote.scope &&
        _string(local['business_id']) == remote.businessId &&
        _string(local['product_id']) == remote.productId &&
        _string(local['master_product_id']) == remote.masterProductId &&
        _string(local['barcode']) == remote.barcode &&
        _string(local['barcode_normalized']) == remote.barcodeNormalized &&
        _string(local['barcode_type']) == remote.barcodeType &&
        _bool(local['is_primary']) == remote.isPrimary &&
        _string(local['status']) == remote.status &&
        _string(local['source']) == remote.source &&
        _double(local['confidence_score']) == remote.confidenceScore &&
        _int(local['version']) == remote.version &&
        _jsonEquivalent(local['metadata_json'], remote.metadata) &&
        _sameDate(local['deleted_at'], remote.deletedAt);
  }

  DateTime? dateTime(Object? value) {
    if (value is DateTime) {
      return value.toUtc();
    }
    if (value is int) {
      final milliseconds = value.abs() < 100000000000 ? value * 1000 : value;
      return DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
    }
    if (value is String) {
      return DateTime.tryParse(value)?.toUtc();
    }
    return null;
  }

  bool _sameDate(Object? local, DateTime? remote) {
    final localDate = dateTime(local);
    if (localDate == null || remote == null) {
      return localDate == null && remote == null;
    }
    return localDate.isAtSameMomentAs(remote);
  }

  String? _string(Object? value) => value?.toString();

  double? _double(Object? value) => value is num ? value.toDouble() : null;

  int? _int(Object? value) => value is num ? value.toInt() : null;

  bool? _bool(Object? value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    return null;
  }

  bool _jsonEquivalent(Object? localValue, Object? remoteValue) {
    Object? decodedLocal = localValue;
    if (localValue is String) {
      try {
        decodedLocal = jsonDecode(localValue);
      } on FormatException {
        return false;
      }
    }
    return jsonEncode(_canonicalJson(decodedLocal)) ==
        jsonEncode(_canonicalJson(remoteValue));
  }

  Object? _canonicalJson(Object? value) {
    if (value is Map) {
      final entries = value.entries
          .map(
            (entry) => MapEntry(
              entry.key.toString(),
              _canonicalJson(entry.value),
            ),
          )
          .toList()
        ..sort((left, right) => left.key.compareTo(right.key));
      return {
        for (final entry in entries) entry.key: entry.value,
      };
    }
    if (value is List) {
      return value.map(_canonicalJson).toList(growable: false);
    }
    return value;
  }
}
