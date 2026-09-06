import 'dart:convert';

import '../../sync/application/local_sync_outbox_service.dart';
import '../../sync/data/models/local_sync_outbox_models.dart';
import '../data/datasources/purchase_local_dao.dart';

class PurchaseSyncOutboxResult {
  const PurchaseSyncOutboxResult({
    required this.businessId,
    required this.branchId,
    required this.purchasesChecked,
    required this.purchasesEnqueued,
    required this.batchesCreated,
    required this.mutationsEnqueued,
    required this.results,
  });

  final String businessId;
  final String branchId;
  final int purchasesChecked;
  final int purchasesEnqueued;
  final int batchesCreated;
  final int mutationsEnqueued;
  final List<Map<String, dynamic>> results;

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      'purchases_checked': purchasesChecked,
      'purchases_enqueued': purchasesEnqueued,
      'batches_created': batchesCreated,
      'mutations_enqueued': mutationsEnqueued,
      'results': results,
    };
  }
}

class PurchaseSyncOutboxService {
  PurchaseSyncOutboxService({
    required PurchaseLocalDao dao,
    required LocalSyncOutboxService outboxService,
  })  : _dao = dao,
        _outboxService = outboxService;

  final PurchaseLocalDao _dao;
  final LocalSyncOutboxService _outboxService;

  Future<PurchaseSyncOutboxResult> enqueuePendingPurchases({
    required String businessId,
    required String branchId,
    required String profileId,
    String? appDeviceId,
    String? deviceInstallationId,
    int limit = 10,
  }) async {
    final pendingPurchases = await _dao.getPendingDirtyPurchases(
      businessId: businessId,
      branchId: branchId,
      limit: limit,
    );

    return _enqueuePurchases(
      businessId: businessId,
      branchId: branchId,
      profileId: profileId,
      appDeviceId: appDeviceId,
      deviceInstallationId: deviceInstallationId,
      purchases: pendingPurchases,
    );
  }

  Future<PurchaseSyncOutboxResult> enqueuePurchaseForRetry({
    required String businessId,
    required String branchId,
    required String profileId,
    required String appDeviceId,
    required String deviceInstallationId,
    required String purchaseId,
  }) async {
    final purchase = await _dao.getPendingDirtyPurchase(
      businessId: businessId,
      branchId: branchId,
      purchaseId: purchaseId,
    );
    return _enqueuePurchases(
      businessId: businessId,
      branchId: branchId,
      profileId: profileId,
      appDeviceId: appDeviceId,
      deviceInstallationId: deviceInstallationId,
      purchases: purchase == null ? const [] : [purchase],
    );
  }

  Future<PurchaseSyncOutboxResult> _enqueuePurchases({
    required String businessId,
    required String branchId,
    required String profileId,
    required String? appDeviceId,
    required String? deviceInstallationId,
    required List<Map<String, dynamic>> purchases,
  }) async {
    var purchasesEnqueued = 0;
    var batchesCreated = 0;
    var mutationsEnqueued = 0;
    final results = <Map<String, dynamic>>[];

    for (final purchase in purchases) {
      final purchaseId = _requiredString(purchase, 'id');

      final items = await _dao.getPurchaseItemsForSync(
        purchaseId: purchaseId,
      );

      final localMovements =
          await _dao.getPurchaseInventoryMovementsForSyncContext(
        purchaseId: purchaseId,
      );

      if (items.isEmpty) {
        results.add({
          'purchase_id': purchaseId,
          'status': 'skipped',
          'reason': 'purchase_without_items',
        });
        continue;
      }

      final mutations = <LocalSyncMutationDraft>[];
      var sequence = _safeClientSequence();

      final purchasePayload = _purchasePayload(purchase);

      mutations.add(
        LocalSyncMutationDraft(
          clientMutationId: _clientMutationId(
            deviceInstallationId: deviceInstallationId,
            profileId: profileId,
            entityTable: 'purchases',
            entityId: purchaseId,
          ),
          clientSequence: sequence++,
          entityTable: 'purchases',
          entityId: purchaseId,
          operation: 'insert',
          payload: purchasePayload,
          changedFields: purchasePayload.keys.toList(),
          idempotencyKey: _idempotencyKey(
            purchase,
            fallback:
                '${deviceInstallationId ?? profileId}:purchases:$purchaseId:insert',
          ),
          businessId: businessId,
          branchId: branchId,
          profileId: profileId,
          appDeviceId: appDeviceId,
          metadata: {
            'source': 'purchase_sync_outbox_service',
            'domain': 'purchases',
            'purchase_id': purchaseId,
          },
        ),
      );

      for (final item in items) {
        final itemId = _requiredString(item, 'id');
        final payload = _purchaseItemPayload(
          item,
          businessId: businessId,
          branchId: branchId,
        );

        mutations.add(
          LocalSyncMutationDraft(
            clientMutationId: _clientMutationId(
              deviceInstallationId: deviceInstallationId,
              profileId: profileId,
              entityTable: 'purchase_items',
              entityId: itemId,
            ),
            clientSequence: sequence++,
            entityTable: 'purchase_items',
            entityId: itemId,
            operation: 'insert',
            payload: payload,
            changedFields: payload.keys.toList(),
            idempotencyKey: _idempotencyKey(
              item,
              fallback:
                  '${deviceInstallationId ?? profileId}:purchase_items:$itemId:insert',
            ),
            businessId: businessId,
            branchId: branchId,
            profileId: profileId,
            appDeviceId: appDeviceId,
            metadata: {
              'source': 'purchase_sync_outbox_service',
              'domain': 'purchases',
              'purchase_id': purchaseId,
              'purchase_item_id': itemId,
            },
          ),
        );
      }

      final enqueueResult = await _outboxService.enqueueUploadBatch(
        businessId: businessId,
        branchId: branchId,
        profileId: profileId,
        appDeviceId: appDeviceId,
        deviceInstallationId: deviceInstallationId,
        domain: 'purchases',
        mutations: mutations,
        metadata: {
          'source': 'purchase_sync_outbox_service',
          'domain': 'purchases',
          'purchase_id': purchaseId,
          'item_count': items.length,
          'local_inventory_movement_count': localMovements.length,
          'inventory_note':
              'Local purchase inventory movements are offline UI ledger only. Remote inventory is applied by backend purchases trigger from purchase_items.',
        },
      );

      purchasesEnqueued++;
      batchesCreated++;
      mutationsEnqueued += mutations.length;

      results.add({
        'purchase_id': purchaseId,
        'status': 'enqueued',
        'item_count': items.length,
        'local_inventory_movement_count': localMovements.length,
        'mutation_count': mutations.length,
        'outbox_result': enqueueResult.toJson(),
      });
    }

    return PurchaseSyncOutboxResult(
      businessId: businessId,
      branchId: branchId,
      purchasesChecked: purchases.length,
      purchasesEnqueued: purchasesEnqueued,
      batchesCreated: batchesCreated,
      mutationsEnqueued: mutationsEnqueued,
      results: results,
    );
  }

  Map<String, dynamic> _purchasePayload(Map<String, dynamic> purchase) {
    return {
      'id': _requiredString(purchase, 'id'),
      'business_id': _requiredString(purchase, 'business_id'),
      'branch_id': _nullableString(purchase['branch_id']),
      'supplier_id': _nullableString(purchase['supplier_id']),
      'user_id': _nullableString(purchase['user_id']),
      'total': _double(purchase['total']),
      'status': _nullableString(purchase['status']) ?? 'completed',
      'invoice_photo_url': _nullableString(purchase['invoice_photo_url']),
      'processing_status':
          _nullableString(purchase['processing_status']) ?? 'completed',
      'supplier_name': _nullableString(purchase['supplier_name']),
      'idempotency_key': _idempotencyKey(
        purchase,
        fallback: 'purchases:${_requiredString(purchase, 'id')}:insert',
      ),
      'sync_status': 'pending',
      'metadata': _metadata(purchase['metadata_json']),
      'created_at': _iso(purchase['created_at']),
      'updated_at': _iso(purchase['updated_at']),
      'deleted_at': _nullableIso(purchase['deleted_at']),
    };
  }

  Map<String, dynamic> _purchaseItemPayload(
    Map<String, dynamic> item, {
    required String businessId,
    required String branchId,
  }) {
    return {
      'id': _requiredString(item, 'id'),
      'purchase_id': _requiredString(item, 'purchase_id'),
      'business_id': _nullableString(item['business_id']) ?? businessId,
      'branch_id': _nullableString(item['branch_id']) ?? branchId,
      'product_id': _requiredString(item, 'product_id'),
      'quantity': _int(item['quantity']),
      'unit_cost': _double(item['unit_cost']),
      'subtotal': _double(item['subtotal']),
      'idempotency_key': _idempotencyKey(
        item,
        fallback: 'purchase_items:${_requiredString(item, 'id')}:insert',
      ),
      'sync_status': 'pending',
      'metadata': _metadata(item['metadata_json']),
      'created_at': _iso(item['created_at']),
      'updated_at': _iso(item['updated_at']),
      'deleted_at': _nullableIso(item['deleted_at']),
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

  int _int(Object? value) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
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
