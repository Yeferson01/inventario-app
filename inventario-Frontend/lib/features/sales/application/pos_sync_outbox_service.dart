import 'dart:convert';

import '../../sync/application/local_sync_outbox_service.dart';
import '../../sync/data/models/local_sync_outbox_models.dart';
import '../data/datasources/pos_local_sale_dao.dart';

class PosSyncOutboxResult {
  const PosSyncOutboxResult({
    required this.businessId,
    required this.branchId,
    required this.salesChecked,
    required this.salesEnqueued,
    required this.batchesCreated,
    required this.mutationsEnqueued,
    required this.results,
  });

  final String businessId;
  final String branchId;
  final int salesChecked;
  final int salesEnqueued;
  final int batchesCreated;
  final int mutationsEnqueued;
  final List<Map<String, dynamic>> results;

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      'sales_checked': salesChecked,
      'sales_enqueued': salesEnqueued,
      'batches_created': batchesCreated,
      'mutations_enqueued': mutationsEnqueued,
      'results': results,
    };
  }
}

class PosSyncOutboxService {
  PosSyncOutboxService({
    required PosLocalSaleDao dao,
    required LocalSyncOutboxService outboxService,
  })  : _dao = dao,
        _outboxService = outboxService;

  final PosLocalSaleDao _dao;
  final LocalSyncOutboxService _outboxService;

  Future<PosSyncOutboxResult> enqueuePendingPosSales({
    required String businessId,
    required String branchId,
    required String profileId,
    String? appDeviceId,
    String? deviceInstallationId,
    int limit = 10,
  }) async {
    final pendingSales = await _dao.getPendingDirtySales(
      businessId: businessId,
      branchId: branchId,
      limit: limit,
    );

    var salesEnqueued = 0;
    var batchesCreated = 0;
    var mutationsEnqueued = 0;
    final results = <Map<String, dynamic>>[];

    for (final sale in pendingSales) {
      final saleId = _requiredString(sale, 'id');

      final items = await _dao.getSaleItemsForSync(saleId: saleId);
      final payments = await _dao.getSalePaymentsForSync(saleId: saleId);
      final localMovements =
          await _dao.getSaleInventoryMovementsForSyncContext(saleId: saleId);

      if (items.isEmpty) {
        results.add({
          'sale_id': saleId,
          'status': 'skipped',
          'reason': 'sale_without_items',
        });
        continue;
      }

      if (payments.isEmpty) {
        results.add({
          'sale_id': saleId,
          'status': 'skipped',
          'reason': 'sale_without_payments',
        });
        continue;
      }

      final mutations = <LocalSyncMutationDraft>[];
      var sequence = _safeClientSequence();

      final salePayload = _salePayload(sale);

      mutations.add(
        LocalSyncMutationDraft(
          clientMutationId: _clientMutationId(
            deviceInstallationId: deviceInstallationId,
            profileId: profileId,
            entityTable: 'sales',
            entityId: saleId,
          ),
          clientSequence: sequence++,
          entityTable: 'sales',
          entityId: saleId,
          operation: 'insert',
          payload: salePayload,
          changedFields: salePayload.keys.toList(),
          idempotencyKey: _idempotencyKey(
            sale,
            fallback:
                '${deviceInstallationId ?? profileId}:sales:$saleId:insert',
          ),
          businessId: businessId,
          branchId: branchId,
          profileId: profileId,
          appDeviceId: appDeviceId,
          metadata: {
            'source': 'pos_sync_outbox_service',
            'domain': 'pos',
            'sale_id': saleId,
          },
        ),
      );

      for (final item in items) {
        final itemId = _requiredString(item, 'id');
        final payload = _saleItemPayload(
          item,
          businessId: businessId,
          branchId: branchId,
        );

        mutations.add(
          LocalSyncMutationDraft(
            clientMutationId: _clientMutationId(
              deviceInstallationId: deviceInstallationId,
              profileId: profileId,
              entityTable: 'sale_items',
              entityId: itemId,
            ),
            clientSequence: sequence++,
            entityTable: 'sale_items',
            entityId: itemId,
            operation: 'insert',
            payload: payload,
            changedFields: payload.keys.toList(),
            idempotencyKey:
                '${deviceInstallationId ?? profileId}:sale_items:$itemId:insert',
            businessId: businessId,
            branchId: branchId,
            profileId: profileId,
            appDeviceId: appDeviceId,
            metadata: {
              'source': 'pos_sync_outbox_service',
              'domain': 'pos',
              'sale_id': saleId,
              'sale_item_id': itemId,
            },
          ),
        );
      }

      for (final payment in payments) {
        final paymentId = _requiredString(payment, 'id');
        final payload = _salePaymentPayload(payment);

        mutations.add(
          LocalSyncMutationDraft(
            clientMutationId: _clientMutationId(
              deviceInstallationId: deviceInstallationId,
              profileId: profileId,
              entityTable: 'sale_payments',
              entityId: paymentId,
            ),
            clientSequence: sequence++,
            entityTable: 'sale_payments',
            entityId: paymentId,
            operation: 'insert',
            payload: payload,
            changedFields: payload.keys.toList(),
            idempotencyKey:
                '${deviceInstallationId ?? profileId}:sale_payments:$paymentId:insert',
            businessId: businessId,
            branchId: branchId,
            profileId: profileId,
            appDeviceId: appDeviceId,
            metadata: {
              'source': 'pos_sync_outbox_service',
              'domain': 'pos',
              'sale_id': saleId,
              'sale_payment_id': paymentId,
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
        domain: 'pos',
        mutations: mutations,
        metadata: {
          'source': 'pos_sync_outbox_service',
          'domain': 'pos',
          'sale_id': saleId,
          'item_count': items.length,
          'payment_count': payments.length,
          'local_inventory_movement_count': localMovements.length,
          'inventory_note':
              'Local inventory movements are offline UI ledger only. Remote inventory is applied by backend POS from sale_items.',
        },
      );

      salesEnqueued++;
      batchesCreated++;
      mutationsEnqueued += mutations.length;

      results.add({
        'sale_id': saleId,
        'status': 'enqueued',
        'item_count': items.length,
        'payment_count': payments.length,
        'local_inventory_movement_count': localMovements.length,
        'mutation_count': mutations.length,
        'outbox_result': enqueueResult.toJson(),
      });
    }

    return PosSyncOutboxResult(
      businessId: businessId,
      branchId: branchId,
      salesChecked: pendingSales.length,
      salesEnqueued: salesEnqueued,
      batchesCreated: batchesCreated,
      mutationsEnqueued: mutationsEnqueued,
      results: results,
    );
  }

  Map<String, dynamic> _salePayload(Map<String, dynamic> sale) {
    return {
      'id': _requiredString(sale, 'id'),
      'business_id': _requiredString(sale, 'business_id'),
      'branch_id': _nullableString(sale['branch_id']),
      'user_id': _nullableString(sale['user_id']),
      'customer_id': _nullableString(sale['customer_id']),
      'cash_register_id': _nullableString(sale['cash_register_id']),
      'cash_session_id': _nullableString(sale['cash_session_id']),
      'subtotal': _double(sale['subtotal']),
      'discount_total': _double(sale['discount_total']),
      'tax_total': _double(sale['tax_total']),
      'total': _double(sale['total']),
      'payment_method': _nullableString(sale['payment_method']),
      'payment_status': _nullableString(sale['payment_status']) ?? 'paid',
      'status': _nullableString(sale['status']) ?? 'completed',
      'idempotency_key': _idempotencyKey(
        sale,
        fallback: 'sales:${_requiredString(sale, 'id')}:insert',
      ),
      'sync_status': 'pending',
      'metadata': _metadata(sale['metadata_json']),
      'created_at': _iso(sale['created_at']),
      'updated_at': _iso(sale['updated_at']),
      'deleted_at': _nullableIso(sale['deleted_at']),
    };
  }

  Map<String, dynamic> _saleItemPayload(
    Map<String, dynamic> item, {
    required String businessId,
    required String branchId,
  }) {
    return {
      'id': _requiredString(item, 'id'),
      'business_id': businessId,
      'branch_id': branchId,
      'sale_id': _requiredString(item, 'sale_id'),
      'product_id': _nullableString(item['product_id']),
      'product_name_snapshot': _nullableString(item['product_name_snapshot']),
      'barcode_snapshot': _nullableString(item['barcode_snapshot']),
      'quantity': _int(item['quantity']),
      'unit_price': _double(item['unit_price']),
      'discount_amount': _double(item['discount_total']),
      'tax_amount': _double(item['tax_total']),
      'subtotal': _double(item['subtotal']),
      'total': _double(item['line_total']),
      'idempotency_key': 'sale_items:${_requiredString(item, 'id')}:insert',
      'sync_status': 'pending',
      'metadata': _metadata(item['metadata_json']),
      'created_at': _iso(item['created_at']),
      'updated_at': _iso(item['updated_at']),
    };
  }

  Map<String, dynamic> _salePaymentPayload(Map<String, dynamic> payment) {
    return {
      'id': _requiredString(payment, 'id'),
      'business_id': _requiredString(payment, 'business_id'),
      'branch_id': _nullableString(payment['branch_id']),
      'sale_id': _requiredString(payment, 'sale_id'),
      'payment_method': _requiredString(payment, 'payment_method'),
      'amount': _double(payment['amount']),
      'currency': _nullableString(payment['currency']) ?? 'COP',
      'status': _nullableString(payment['status']) ?? 'completed',
      'reference': _nullableString(payment['reference']),
      'idempotency_key':
          'sale_payments:${_requiredString(payment, 'id')}:insert',
      'sync_status': 'pending',
      'metadata': _metadata(payment['metadata_json']),
      'created_at': _iso(payment['created_at']),
      'updated_at': _iso(payment['updated_at']),
      'deleted_at': _nullableIso(payment['deleted_at']),
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
