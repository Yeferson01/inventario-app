import 'dart:convert';

import '../../../core/money/exact_basis_money.dart';
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

      final saleMetadata = _metadata(sale['metadata_json']);
      final exactSale =
          saleMetadata['monetary_contract_version'] == 'exact_weight_sale_v1';
      final hasWeightedItem = items.any(
        (item) => item['sale_mode_snapshot'] == 'weight',
      );
      if (exactSale != hasWeightedItem) {
        throw StateError('Weighted sale contract/item mode mismatch.');
      }
      if (exactSale) {
        final total = _requiredExactInt(saleMetadata, 'total_cents');
        final itemTotal = items.fold<BigInt>(
          BigInt.zero,
          (sum, item) =>
              sum + BigInt.from(_requiredExactInt(item, 'line_total_cents')),
        );
        final paymentTotal = payments.fold<BigInt>(
          BigInt.zero,
          (sum, payment) =>
              sum +
              BigInt.from(_requiredExactInt(
                _metadata(payment['metadata_json']),
                'amount_cents',
              )),
        );
        if (itemTotal != BigInt.from(total) ||
            paymentTotal != BigInt.from(total)) {
          throw StateError('Weighted sale exact totals mismatch.');
        }
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
          exactSale: exactSale,
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
        final payload = _salePaymentPayload(payment, exactSale: exactSale);

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

      Future<LocalSyncEnqueueResult?> existingBatch() =>
          _outboxService.findExistingPosSaleBatch(
            businessId: businessId,
            branchId: branchId,
            profileId: profileId,
            saleId: saleId,
            mutations: mutations,
            itemCount: items.length,
            paymentCount: payments.length,
          );
      var reused = await existingBatch();
      LocalSyncEnqueueResult enqueueResult;
      if (reused != null) {
        enqueueResult = reused;
      } else {
        try {
          enqueueResult = await _outboxService.enqueueUploadBatch(
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
              if (exactSale)
                'monetary_contract_version': 'exact_weight_sale_v1',
              'item_count': items.length,
              'payment_count': payments.length,
              'local_inventory_movement_count': localMovements.length,
              'inventory_note':
                  'Local inventory movements are offline UI ledger only. Remote inventory is applied by backend POS from sale_items.',
            },
          );
        } on StateError catch (error) {
          if (error.message != 'mutation_batch_identity_conflict') rethrow;
          // Another enqueue may have committed after the first lookup.
          reused = await existingBatch();
          if (reused == null) rethrow;
          enqueueResult = reused;
        }
      }

      if (reused == null) {
        salesEnqueued++;
        batchesCreated++;
        mutationsEnqueued += mutations.length;
      }

      results.add({
        'sale_id': saleId,
        'status': reused == null ? 'enqueued' : 'reused',
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
    final metadata = _metadata(sale['metadata_json']);
    final exactSale =
        metadata['monetary_contract_version'] == 'exact_weight_sale_v1';
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
      if (exactSale) ...{
        'monetary_contract_version': 'exact_weight_sale_v1',
        'total_cents': _requiredExactInt(metadata, 'total_cents'),
        'subtotal_cents': _requiredExactInt(metadata, 'subtotal_cents'),
      },
      'metadata': metadata,
      'created_at': _iso(sale['created_at']),
      'updated_at': _iso(sale['updated_at']),
      'deleted_at': _nullableIso(sale['deleted_at']),
    };
  }

  Map<String, dynamic> _saleItemPayload(
    Map<String, dynamic> item, {
    required String businessId,
    required String branchId,
    required bool exactSale,
  }) {
    final mode = _nullableString(item['sale_mode_snapshot']) ?? 'unit';
    if (exactSale) {
      final quantity = _int(item['quantity']);
      final basis = _requiredExactInt(item, 'price_basis_quantity_snapshot');
      final price = _requiredExactInt(item, 'price_cents_snapshot');
      final total = _requiredExactInt(item, 'line_total_cents');
      if (quantity <= 0 ||
          price <= 0 ||
          (mode == 'weight' && basis != 500) ||
          (mode == 'unit' && basis != 1) ||
          (mode != 'weight' && mode != 'unit')) {
        throw StateError('Invalid weighted sale item snapshot.');
      }
      if (mode == 'weight' &&
          (item['discount_total'] != 0 ||
              item['tax_total'] != 0 ||
              checkedSignedInt64(calculateBasisAmountCents(
                    baseAmountCents: BigInt.from(price),
                    quantity: BigInt.from(quantity),
                    basisQuantity: BigInt.from(500),
                  )) !=
                  total)) {
        throw StateError('Corrupt WEIGHT line total.');
      }
    }
    return {
      'id': _requiredString(item, 'id'),
      'business_id': businessId,
      'branch_id': branchId,
      'sale_id': _requiredString(item, 'sale_id'),
      'product_id': _nullableString(item['product_id']),
      'product_name_snapshot': _nullableString(item['product_name_snapshot']),
      'barcode_snapshot': _nullableString(item['barcode_snapshot']),
      'unit_cost_snapshot': _nullableDouble(item['unit_cost_snapshot']),
      if (exactSale) ...{
        'monetary_contract_version': 'exact_weight_sale_v1',
        'sale_mode_snapshot': mode,
        'price_basis_quantity_snapshot':
            _requiredExactInt(item, 'price_basis_quantity_snapshot'),
        'price_cents_snapshot': _requiredExactInt(item, 'price_cents_snapshot'),
        'line_total_cents': _requiredExactInt(item, 'line_total_cents'),
        'cogs_cents': item['cogs_cents'],
        'cogs_source': 'local_projection_not_authoritative',
      },
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

  Map<String, dynamic> _salePaymentPayload(
    Map<String, dynamic> payment, {
    required bool exactSale,
  }) {
    // Drift's payment.created_at is the durable UTC payment event time. Keep
    // the same value for every retry and never substitute upload time.
    final paidAt = _paymentEventTimeIso(payment['created_at']);
    return {
      'id': _requiredString(payment, 'id'),
      'business_id': _requiredString(payment, 'business_id'),
      'branch_id': _nullableString(payment['branch_id']),
      'sale_id': _requiredString(payment, 'sale_id'),
      'payment_method': _requiredString(payment, 'payment_method'),
      'amount': _double(payment['amount']),
      if (exactSale)
        'amount_cents': _requiredExactInt(
          _metadata(payment['metadata_json']),
          'amount_cents',
        ),
      'currency': _nullableString(payment['currency']) ?? 'COP',
      'status': _nullableString(payment['status']) ?? 'completed',
      'reference': _nullableString(payment['reference']),
      'idempotency_key':
          'sale_payments:${_requiredString(payment, 'id')}:insert',
      'sync_status': 'pending',
      'payment_event_time_contract': 'v1',
      'paid_at': paidAt,
      'metadata': _metadata(payment['metadata_json']),
      'created_at': paidAt,
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

  int _requiredExactInt(Map<String, dynamic> map, String key) {
    final value = map[key];
    if (value is! int) {
      throw StateError('Missing exact $key in weighted sale snapshot.');
    }
    return checkedSignedInt64(BigInt.from(value));
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

  double? _nullableDouble(Object? value) {
    if (value == null) {
      return null;
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

  String _paymentEventTimeIso(Object? value) {
    DateTime? parsed;
    if (value is DateTime) {
      parsed = value;
    } else if (value is int) {
      // Drift stores DateTime columns as Unix seconds. Older rows may use
      // milliseconds; 100 billion separates realistic seconds from millis.
      final milliseconds = value.abs() < 100000000000 ? value * 1000 : value;
      try {
        parsed = DateTime.fromMillisecondsSinceEpoch(
          milliseconds,
          isUtc: true,
        );
      } on ArgumentError {
        throw StateError('Payment event timestamp is invalid.');
      }
    } else if (value is String &&
        RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      parsed = DateTime.tryParse(value);
    }
    if (parsed == null) {
      throw StateError('Payment event timestamp is required.');
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
