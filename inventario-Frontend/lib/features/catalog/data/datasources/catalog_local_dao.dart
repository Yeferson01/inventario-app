import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/utils/app_uuid.dart';
import '../../../../core/utils/barcode_normalizer.dart';
import '../models/catalog_local_models.dart';

class CatalogLocalDao {
  CatalogLocalDao(this.db);

  final AppDatabase db;

  Future<LocalBarcodeLookupResult> lookupByBarcode({
    required String businessId,
    required String barcode,
  }) async {
    final normalized = BarcodeNormalizer.normalize(barcode);

    if (normalized.isEmpty) {
      return LocalBarcodeLookupResult.none(normalized);
    }

    final businessMatch = await db.customSelect(
      '''
          select
            pb.id as barcode_id,
            pb.scope as barcode_scope,
            pb.business_id as barcode_business_id,
            pb.product_id as barcode_product_id,
            pb.master_product_id as barcode_master_product_id,
            pb.barcode as barcode_value,
            pb.barcode_normalized as barcode_normalized,
            pb.barcode_type as barcode_type,
            pb.is_primary as barcode_is_primary,
            pb.status as barcode_status,
            pb.source as barcode_source,
            pb.confidence_score as barcode_confidence_score,

            p.id as local_product_id,
            p.business_id as local_product_business_id,
            p.barcode as local_product_barcode,
            p.name as local_product_name,
            p.sale_price as local_product_sale_price,
            p.purchase_price as local_product_purchase_price,
            p.stock_quantity as local_product_stock_quantity,
            p.unit as local_product_unit,
            p.status as local_product_status,

            mp.id as master_product_id,
            mp.name as master_product_name,
            mp.product_name as master_product_product_name,
            mp.brand as master_product_brand,
            mp.manufacturer as master_product_manufacturer,
            mp.category_name as master_product_category_name,
            mp.subcategory_name as master_product_subcategory_name,
            mp.package_size as master_product_package_size,
            mp.package_unit as master_product_package_unit,
            mp.unit_type as master_product_unit_type,
            mp.image_thumb_url as master_product_image_thumb_url,
            mp.image_hash as master_product_image_hash,
            mp.confidence_score as master_product_confidence_score
          from local_product_barcodes pb
          left join products p
            on p.id = pb.product_id
          left join local_master_products_catalog mp
            on mp.id = pb.master_product_id
          where pb.scope = 'business'
            and pb.business_id = ?
            and pb.barcode_normalized = ?
            and pb.status = 'active'
            and pb.deleted_at is null
          order by pb.is_primary desc, pb.updated_at desc
          limit 1
          ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(normalized),
      ],
    ).getSingleOrNull();

    if (businessMatch != null) {
      final data = Map<String, dynamic>.from(businessMatch.data);

      return LocalBarcodeLookupResult(
        found: true,
        matchType: 'business',
        suggestedAction: 'use_local_product',
        normalizedBarcode: normalized,
        barcodeRecord: _barcodeRecordFromLookup(data),
        localProduct: _localProductFromLookup(data),
        masterProduct: _masterProductFromLookup(data),
      );
    }

    final globalMatch = await db.customSelect(
      '''
          select
            pb.id as barcode_id,
            pb.scope as barcode_scope,
            pb.business_id as barcode_business_id,
            pb.product_id as barcode_product_id,
            pb.master_product_id as barcode_master_product_id,
            pb.barcode as barcode_value,
            pb.barcode_normalized as barcode_normalized,
            pb.barcode_type as barcode_type,
            pb.is_primary as barcode_is_primary,
            pb.status as barcode_status,
            pb.source as barcode_source,
            pb.confidence_score as barcode_confidence_score,

            mp.id as master_product_id,
            mp.name as master_product_name,
            mp.product_name as master_product_product_name,
            mp.brand as master_product_brand,
            mp.manufacturer as master_product_manufacturer,
            mp.category_name as master_product_category_name,
            mp.subcategory_name as master_product_subcategory_name,
            mp.package_size as master_product_package_size,
            mp.package_unit as master_product_package_unit,
            mp.unit_type as master_product_unit_type,
            mp.image_thumb_url as master_product_image_thumb_url,
            mp.image_hash as master_product_image_hash,
            mp.confidence_score as master_product_confidence_score
          from local_product_barcodes pb
          join local_master_products_catalog mp
            on mp.id = pb.master_product_id
          where pb.scope = 'global'
            and pb.barcode_normalized = ?
            and pb.status = 'active'
            and pb.deleted_at is null
            and mp.deleted_at is null
          order by pb.is_primary desc, pb.updated_at desc
          limit 1
          ''',
      variables: [
        Variable<String>(normalized),
      ],
    ).getSingleOrNull();

    if (globalMatch != null) {
      final data = Map<String, dynamic>.from(globalMatch.data);

      return LocalBarcodeLookupResult(
        found: true,
        matchType: 'global',
        suggestedAction: 'create_local_product_from_master',
        normalizedBarcode: normalized,
        barcodeRecord: _barcodeRecordFromLookup(data),
        masterProduct: _masterProductFromLookup(data),
      );
    }

    return LocalBarcodeLookupResult.none(normalized);
  }

  Future<CatalogDeltaApplyResult> applyCatalogDeltaRecords(
    List<Map<String, dynamic>> records,
  ) async {
    var masterProducts = 0;
    var productBarcodes = 0;
    var ignored = 0;

    await db.transaction(() async {
      for (final record in records) {
        final entityType = _entityType(record);
        final payload = _payload(record);

        if (entityType == 'master_product') {
          await upsertMasterProduct(payload);
          masterProducts++;
        } else if (entityType == 'global_barcode' ||
            entityType == 'business_barcode') {
          await upsertProductBarcode(payload);
          productBarcodes++;
        } else {
          ignored++;
        }
      }
    });

    return CatalogDeltaApplyResult(
      masterProductsUpserted: masterProducts,
      productBarcodesUpserted: productBarcodes,
      ignoredRecords: ignored,
    );
  }

  Future<void> upsertMasterProduct(Map<String, dynamic> payload) async {
    final now = DateTime.now().toUtc();
    final id = _requiredString(payload, 'id');
    final updatedAt = _dateTime(payload['updated_at']) ?? now;

    await _customStatement(
      db,
      '''
      insert into local_master_products_catalog (
        id,
        barcode,
        gtin,
        barcode_normalized,
        name,
        product_name,
        normalized_name,
        brand,
        manufacturer,
        category_name,
        subcategory_name,
        package_size,
        package_unit,
        unit_type,
        has_image,
        image_thumb_url,
        image_hash,
        source,
        verification_status,
        confidence_score,
        catalog_version,
        sync_status,
        version,
        updated_at,
        deleted_at,
        last_synced_at
      )
      values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(id) do update set
        barcode = excluded.barcode,
        gtin = excluded.gtin,
        barcode_normalized = excluded.barcode_normalized,
        name = excluded.name,
        product_name = excluded.product_name,
        normalized_name = excluded.normalized_name,
        brand = excluded.brand,
        manufacturer = excluded.manufacturer,
        category_name = excluded.category_name,
        subcategory_name = excluded.subcategory_name,
        package_size = excluded.package_size,
        package_unit = excluded.package_unit,
        unit_type = excluded.unit_type,
        has_image = excluded.has_image,
        image_thumb_url = excluded.image_thumb_url,
        image_hash = excluded.image_hash,
        source = excluded.source,
        verification_status = excluded.verification_status,
        confidence_score = excluded.confidence_score,
        catalog_version = excluded.catalog_version,
        sync_status = excluded.sync_status,
        version = excluded.version,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at,
        last_synced_at = excluded.last_synced_at
      ''',
      [
        Variable<String>(id),
        Variable<String>(_string(payload['barcode'])),
        Variable<String>(_string(payload['gtin'])),
        Variable<String>(
          _string(payload['barcode_normalized']) ??
              BarcodeNormalizer.normalize(_string(payload['barcode']) ?? ''),
        ),
        Variable<String>(_string(payload['name'])),
        Variable<String>(_string(payload['product_name'] ?? payload['name'])),
        Variable<String>(_string(payload['normalized_name'])),
        Variable<String>(_string(payload['brand'])),
        Variable<String>(_string(payload['manufacturer'])),
        Variable<String>(_string(payload['category_name'])),
        Variable<String>(_string(payload['subcategory_name'])),
        Variable<double>(_double(payload['package_size'])),
        Variable<String>(_string(payload['package_unit'])),
        Variable<String>(_string(payload['unit_type'])),
        Variable<int>(_boolToInt(payload['has_image'])),
        Variable<String>(_string(payload['image_thumb_url'])),
        Variable<String>(_string(payload['image_hash'])),
        Variable<String>(_string(payload['source'])),
        Variable<String>(_string(payload['verification_status'])),
        Variable<double>(_double(payload['confidence_score'])),
        Variable<int>(_int(payload['catalog_version']) ?? 1),
        Variable<String>(_string(payload['sync_status']) ?? 'synced'),
        Variable<int>(_int(payload['version']) ?? 1),
        Variable<DateTime>(updatedAt),
        Variable<DateTime>(_dateTime(payload['deleted_at'])),
        Variable<DateTime>(now),
      ],
    );
  }

  Future<void> upsertProductBarcode(Map<String, dynamic> payload) async {
    final now = DateTime.now().toUtc();
    final id = _requiredString(payload, 'id');
    final rawBarcode = _string(payload['barcode']) ?? '';
    final normalized = _string(payload['barcode_normalized']) ??
        BarcodeNormalizer.normalize(rawBarcode);

    await _customStatement(
      db,
      '''
      insert into local_product_barcodes (
        id,
        scope,
        business_id,
        product_id,
        master_product_id,
        barcode,
        barcode_normalized,
        barcode_type,
        is_primary,
        status,
        source,
        confidence_score,
        sync_status,
        version,
        updated_at,
        deleted_at,
        last_synced_at
      )
      values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(id) do update set
        scope = excluded.scope,
        business_id = excluded.business_id,
        product_id = excluded.product_id,
        master_product_id = excluded.master_product_id,
        barcode = excluded.barcode,
        barcode_normalized = excluded.barcode_normalized,
        barcode_type = excluded.barcode_type,
        is_primary = excluded.is_primary,
        status = excluded.status,
        source = excluded.source,
        confidence_score = excluded.confidence_score,
        sync_status = excluded.sync_status,
        version = excluded.version,
        updated_at = excluded.updated_at,
        deleted_at = excluded.deleted_at,
        last_synced_at = excluded.last_synced_at
      ''',
      [
        Variable<String>(id),
        Variable<String>(_string(payload['scope']) ?? 'global'),
        Variable<String>(_string(payload['business_id'])),
        Variable<String>(_string(payload['product_id'])),
        Variable<String>(_string(payload['master_product_id'])),
        Variable<String>(rawBarcode),
        Variable<String>(normalized),
        Variable<String>(
          _string(payload['barcode_type']) ??
              BarcodeNormalizer.inferBarcodeType(rawBarcode),
        ),
        Variable<int>(_boolToInt(payload['is_primary'])),
        Variable<String>(_string(payload['status']) ?? 'active'),
        Variable<String>(_string(payload['source'])),
        Variable<double>(_double(payload['confidence_score'])),
        Variable<String>(_string(payload['sync_status']) ?? 'synced'),
        Variable<int>(_int(payload['version']) ?? 1),
        Variable<DateTime>(_dateTime(payload['updated_at']) ?? now),
        Variable<DateTime>(_dateTime(payload['deleted_at'])),
        Variable<DateTime>(now),
      ],
    );
  }

  Future<void> saveCatalogSyncSuccess({
    required String businessId,
    required DateTime serverTime,
    required int? catalogVersion,
    Map<String, dynamic>? pageToken,
  }) async {
    final now = DateTime.now().toUtc();

    await _customStatement(
      db,
      '''
      insert into local_catalog_sync_state (
        id,
        business_id,
        last_catalog_pull_at,
        last_server_time,
        last_since_updated_at,
        last_catalog_version,
        last_page_token,
        is_syncing,
        last_error,
        created_at,
        updated_at
      )
      values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(id) do update set
        last_catalog_pull_at = excluded.last_catalog_pull_at,
        last_server_time = excluded.last_server_time,
        last_since_updated_at = excluded.last_since_updated_at,
        last_catalog_version = excluded.last_catalog_version,
        last_page_token = excluded.last_page_token,
        is_syncing = excluded.is_syncing,
        last_error = excluded.last_error,
        updated_at = excluded.updated_at
      ''',
      [
        Variable<String>(businessId),
        Variable<String>(businessId),
        Variable<DateTime>(now),
        Variable<DateTime>(serverTime.toUtc()),
        Variable<DateTime>(serverTime.toUtc()),
        Variable<int>(catalogVersion),
        Variable<String>(pageToken == null ? null : jsonEncode(pageToken)),
        Variable<int>(0),
        const Variable<String>(null),
        Variable<DateTime>(now),
        Variable<DateTime>(now),
      ],
    );
  }

  Future<void> markCatalogSyncStarted(String businessId) async {
    final now = DateTime.now().toUtc();

    await _customStatement(
      db,
      '''
      insert into local_catalog_sync_state (
        id,
        business_id,
        is_syncing,
        created_at,
        updated_at
      )
      values (?, ?, ?, ?, ?)
      on conflict(id) do update set
        is_syncing = excluded.is_syncing,
        updated_at = excluded.updated_at
      ''',
      [
        Variable<String>(businessId),
        Variable<String>(businessId),
        Variable<int>(1),
        Variable<DateTime>(now),
        Variable<DateTime>(now),
      ],
    );
  }

  Future<void> markCatalogSyncFailed({
    required String businessId,
    required Object error,
  }) async {
    final now = DateTime.now().toUtc();

    await _customStatement(
      db,
      '''
      insert into local_catalog_sync_state (
        id,
        business_id,
        is_syncing,
        last_error,
        created_at,
        updated_at
      )
      values (?, ?, ?, ?, ?, ?)
      on conflict(id) do update set
        is_syncing = excluded.is_syncing,
        last_error = excluded.last_error,
        updated_at = excluded.updated_at
      ''',
      [
        Variable<String>(businessId),
        Variable<String>(businessId),
        Variable<int>(0),
        Variable<String>(error.toString()),
        Variable<DateTime>(now),
        Variable<DateTime>(now),
      ],
    );
  }

  Future<Map<String, dynamic>?> getCatalogSyncState(String businessId) async {
    final row = await db.customSelect(
      '''
          select *
          from local_catalog_sync_state
          where business_id = ?
          limit 1
          ''',
      variables: [Variable<String>(businessId)],
    ).getSingleOrNull();

    if (row == null) {
      return null;
    }

    return Map<String, dynamic>.from(row.data);
  }

  Future<String> queueContribution({
    required String businessId,
    required String contributionType,
    String? branchId,
    String? localProductId,
    String? masterProductId,
    String? barcode,
    String? barcodeType,
    String? suggestedName,
    String? suggestedBrand,
    String? suggestedManufacturer,
    String? suggestedCategoryName,
    String? suggestedSubcategoryName,
    double? suggestedPackageSize,
    String? suggestedPackageUnit,
    String? suggestedUnitType,
    String? suggestedImageUrl,
    String? suggestedImageThumbUrl,
    String? suggestedImageHash,
    String source = 'app',
    double? confidenceScore,
    Map<String, dynamic>? metadata,
  }) async {
    final id = AppUuid.v7();
    final now = DateTime.now().toUtc();
    final normalizedBarcode =
        barcode == null ? null : BarcodeNormalizer.normalize(barcode);

    await _customStatement(
      db,
      '''
      insert into local_catalog_contribution_queue (
        id,
        business_id,
        branch_id,
        local_product_id,
        master_product_id,
        contribution_type,
        barcode,
        barcode_normalized,
        barcode_type,
        suggested_name,
        suggested_brand,
        suggested_manufacturer,
        suggested_category_name,
        suggested_subcategory_name,
        suggested_package_size,
        suggested_package_unit,
        suggested_unit_type,
        suggested_image_url,
        suggested_image_thumb_url,
        suggested_image_hash,
        source,
        confidence_score,
        metadata_json,
        local_status,
        retry_count,
        created_at,
        updated_at
      )
      values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''',
      [
        Variable<String>(id),
        Variable<String>(businessId),
        Variable<String>(branchId),
        Variable<String>(localProductId),
        Variable<String>(masterProductId),
        Variable<String>(contributionType),
        Variable<String>(barcode),
        Variable<String>(normalizedBarcode),
        Variable<String>(
          barcodeType ??
              (barcode == null
                  ? null
                  : BarcodeNormalizer.inferBarcodeType(barcode)),
        ),
        Variable<String>(suggestedName),
        Variable<String>(suggestedBrand),
        Variable<String>(suggestedManufacturer),
        Variable<String>(suggestedCategoryName),
        Variable<String>(suggestedSubcategoryName),
        Variable<double>(suggestedPackageSize),
        Variable<String>(suggestedPackageUnit),
        Variable<String>(suggestedUnitType),
        Variable<String>(suggestedImageUrl),
        Variable<String>(suggestedImageThumbUrl),
        Variable<String>(suggestedImageHash),
        Variable<String>(source),
        Variable<double>(confidenceScore),
        Variable<String>(metadata == null ? null : jsonEncode(metadata)),
        Variable<String>('pending'),
        Variable<int>(0),
        Variable<DateTime>(now),
        Variable<DateTime>(now),
      ],
    );

    return id;
  }

  Future<List<Map<String, dynamic>>> getPendingContributions({
    required String businessId,
    int limit = 100,
  }) async {
    final rows = await db.customSelect(
      '''
          select *
          from local_catalog_contribution_queue
          where business_id = ?
            and local_status in ('pending', 'error')
          order by created_at asc
          limit ?
          ''',
      variables: [
        Variable<String>(businessId),
        Variable<int>(limit),
      ],
    ).get();

    return rows.map((row) => Map<String, dynamic>.from(row.data)).toList();
  }

  Future<void> markContributionSynced({
    required String localContributionId,
    required String serverContributionId,
  }) async {
    final now = DateTime.now().toUtc();

    await _customStatement(
      db,
      '''
      update local_catalog_contribution_queue
      set
        local_status = 'synced',
        server_contribution_id = ?,
        synced_at = ?,
        updated_at = ?,
        last_error = null
      where id = ?
      ''',
      [
        Variable<String>(serverContributionId),
        Variable<DateTime>(now),
        Variable<DateTime>(now),
        Variable<String>(localContributionId),
      ],
    );
  }

  Future<void> markContributionError({
    required String localContributionId,
    required Object error,
  }) async {
    final now = DateTime.now().toUtc();

    await _customStatement(
      db,
      '''
      update local_catalog_contribution_queue
      set
        local_status = 'error',
        retry_count = coalesce(retry_count, 0) + 1,
        last_error = ?,
        updated_at = ?
      where id = ?
      ''',
      [
        Variable<String>(error.toString()),
        Variable<DateTime>(now),
        Variable<String>(localContributionId),
      ],
    );
  }

  String _entityType(Map<String, dynamic> record) {
    return _string(
          record['entity_type'] ??
              record['type'] ??
              record['record_type'] ??
              record['kind'],
        ) ??
        '';
  }

  Map<String, dynamic> _payload(Map<String, dynamic> record) {
    final payload = record['payload'] ?? record['data'] ?? record['record'];

    if (payload is Map<String, dynamic>) {
      return payload;
    }

    if (payload is Map) {
      return Map<String, dynamic>.from(payload);
    }

    return record;
  }

  Map<String, dynamic> _barcodeRecordFromLookup(Map<String, dynamic> data) {
    return {
      'id': data['barcode_id'],
      'scope': data['barcode_scope'],
      'business_id': data['barcode_business_id'],
      'product_id': data['barcode_product_id'],
      'master_product_id': data['barcode_master_product_id'],
      'barcode': data['barcode_value'],
      'barcode_normalized': data['barcode_normalized'],
      'barcode_type': data['barcode_type'],
      'is_primary': data['barcode_is_primary'],
      'status': data['barcode_status'],
      'source': data['barcode_source'],
      'confidence_score': data['barcode_confidence_score'],
    };
  }

  Map<String, dynamic>? _localProductFromLookup(Map<String, dynamic> data) {
    if (data['local_product_id'] == null) {
      return null;
    }

    return {
      'id': data['local_product_id'],
      'business_id': data['local_product_business_id'],
      'barcode': data['local_product_barcode'],
      'name': data['local_product_name'],
      'sale_price': data['local_product_sale_price'],
      'purchase_price': data['local_product_purchase_price'],
      'stock_quantity': data['local_product_stock_quantity'],
      'unit': data['local_product_unit'],
      'status': data['local_product_status'],
    };
  }

  Map<String, dynamic>? _masterProductFromLookup(Map<String, dynamic> data) {
    if (data['master_product_id'] == null) {
      return null;
    }

    return {
      'id': data['master_product_id'],
      'name': data['master_product_name'],
      'product_name': data['master_product_product_name'],
      'brand': data['master_product_brand'],
      'manufacturer': data['master_product_manufacturer'],
      'category_name': data['master_product_category_name'],
      'subcategory_name': data['master_product_subcategory_name'],
      'package_size': data['master_product_package_size'],
      'package_unit': data['master_product_package_unit'],
      'unit_type': data['master_product_unit_type'],
      'image_thumb_url': data['master_product_image_thumb_url'],
      'image_hash': data['master_product_image_hash'],
      'confidence_score': data['master_product_confidence_score'],
    };
  }

  String _requiredString(Map<String, dynamic> payload, String key) {
    final value = _string(payload[key]);

    if (value == null || value.trim().isEmpty) {
      throw ArgumentError('Campo requerido ausente para catálogo local: $key');
    }

    return value;
  }

  String? _string(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString();

    if (text.trim().isEmpty) {
      return null;
    }

    return text;
  }

  int? _int(Object? value) {
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

  double? _double(Object? value) {
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

  DateTime? _dateTime(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value.toUtc();
    }

    return DateTime.tryParse(value.toString())?.toUtc();
  }

  int _boolToInt(Object? value) {
    if (value is bool) {
      return value ? 1 : 0;
    }

    if (value is int) {
      return value == 0 ? 0 : 1;
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();

      if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
        return 1;
      }
    }

    return 0;
  }
}

Future<void> _customStatement(
  AppDatabase db,
  String sql, [
  List<Object?> parameters = const [],
]) {
  final rawParameters =
      parameters.map<Object?>(_rawStatementParameter).toList(growable: false);

  return db.customStatement(
    sql,
    rawParameters,
  );
}

Object? _rawStatementParameter(Object? value) {
  if (value is Variable) {
    return _normalizeStatementValue(value.value);
  }

  return _normalizeStatementValue(value);
}

Object? _normalizeStatementValue(Object? value) {
  if (value == null) {
    return null;
  }

  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }

  return value;
}
