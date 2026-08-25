import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/database/utils/sqlite_parameter_utils.dart';
import '../../../../core/utils/app_uuid.dart';
import '../../../../core/utils/barcode_normalizer.dart';
import '../models/catalog_local_models.dart';

class CatalogLocalDao {
  CatalogLocalDao(this.db);

  final AppDatabase db;

  Future<LocalBarcodeLookupResult> lookupByBarcode({
    required String businessId,
    required String barcode,
    bool allowMasterMatch = true,
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
          join products p
            on p.id = pb.product_id
          left join local_master_products_catalog mp
            on mp.id = pb.master_product_id
          where pb.scope = 'business'
            and pb.business_id = ?
            and pb.barcode_normalized = ?
            and pb.status = 'active'
            and pb.deleted_at is null
            and p.deleted_at is null
            and p.status = 'active'
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

    if (!allowMasterMatch) {
      return LocalBarcodeLookupResult.none(normalized);
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
    return db.transaction(() => _applyCatalogDeltaRecords(records));
  }

  Future<CatalogDeltaApplyResult> applyCatalogDeltaPage({
    required String businessId,
    required List<Map<String, dynamic>> records,
    required DateTime? committedSince,
    required DateTime windowUpperBound,
    required int? catalogVersion,
    required Map<String, dynamic>? pageToken,
    required bool completed,
    required bool isSyncing,
  }) {
    return db.transaction(() async {
      final result = await _applyCatalogDeltaRecords(records);
      await _saveCatalogSyncProgress(
        businessId: businessId,
        committedSince: committedSince,
        windowUpperBound: windowUpperBound,
        catalogVersion: catalogVersion,
        pageToken: pageToken,
        completed: completed,
        isSyncing: isSyncing,
      );
      return result;
    });
  }

  Future<CatalogDeltaApplyResult> _applyCatalogDeltaRecords(
    List<Map<String, dynamic>> records,
  ) async {
    var masterProducts = 0;
    var productBarcodes = 0;
    var ignored = 0;
    var tombstones = 0;
    var stale = 0;
    var dirty = 0;

    for (final record in records) {
      final entityType = _entityType(record);
      final payload = _payload(record);
      _CatalogRecordApplyOutcome? outcome;

      if (entityType == 'master_product') {
        outcome = await _applyMasterProduct(payload);
        if (outcome.isApplied) {
          masterProducts++;
        }
      } else if (entityType == 'global_barcode' ||
          entityType == 'business_barcode') {
        outcome = await _applyProductBarcode(payload);
        if (outcome.isApplied) {
          productBarcodes++;
        }
      } else {
        ignored++;
      }

      switch (outcome) {
        case _CatalogRecordApplyOutcome.tombstoneApplied:
          tombstones++;
        case _CatalogRecordApplyOutcome.staleIgnored:
          stale++;
          ignored++;
        case _CatalogRecordApplyOutcome.dirtySkipped:
          dirty++;
          ignored++;
        case _CatalogRecordApplyOutcome.applied:
        case null:
          break;
      }
    }

    return CatalogDeltaApplyResult(
      masterProductsUpserted: masterProducts,
      productBarcodesUpserted: productBarcodes,
      ignoredRecords: ignored,
      tombstonesApplied: tombstones,
      staleRecordsIgnored: stale,
      dirtyRecordsSkipped: dirty,
    );
  }

  Future<void> upsertMasterProduct(Map<String, dynamic> payload) async {
    await _applyMasterProduct(payload);
  }

  Future<_CatalogRecordApplyOutcome> _applyMasterProduct(
    Map<String, dynamic> payload,
  ) async {
    final now = DateTime.now().toUtc();
    final id = _requiredString(payload, 'id');
    final incomingVersion = _int(payload['version']) ?? 1;
    final updatedAt = _dateTime(payload['updated_at']) ?? now;
    final decision = await _decideIncomingVersion(
      table: 'local_master_products_catalog',
      id: id,
      incomingVersion: incomingVersion,
    );

    if (decision != null) {
      return decision;
    }

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
      normalizeSqliteParameters([
        id,
        _string(payload['barcode']),
        _string(payload['gtin']),
        _string(payload['barcode_normalized']) ??
            BarcodeNormalizer.normalize(_string(payload['barcode']) ?? ''),
        _string(payload['name']),
        _string(payload['product_name'] ?? payload['name']),
        _string(payload['normalized_name']),
        _string(payload['brand']),
        _string(payload['manufacturer']),
        _string(payload['category_name']),
        _string(payload['subcategory_name']),
        _double(payload['package_size']),
        _string(payload['package_unit']),
        _string(payload['unit_type']),
        _boolToInt(payload['has_image']),
        _string(payload['image_thumb_url']),
        _string(payload['image_hash']),
        _string(payload['source']),
        _string(payload['verification_status']),
        _double(payload['confidence_score']),
        _int(payload['catalog_version']) ?? 1,
        _string(payload['sync_status']) ?? 'synced',
        incomingVersion,
        updatedAt,
        _dateTime(payload['deleted_at']),
        now,
      ]),
    );

    return payload['deleted_at'] == null
        ? _CatalogRecordApplyOutcome.applied
        : _CatalogRecordApplyOutcome.tombstoneApplied;
  }

  Future<void> upsertProductBarcode(Map<String, dynamic> payload) async {
    await _applyProductBarcode(payload);
  }

  Future<_CatalogRecordApplyOutcome> _applyProductBarcode(
    Map<String, dynamic> payload,
  ) async {
    final now = DateTime.now().toUtc();
    final id = _requiredString(payload, 'id');
    final incomingVersion = _int(payload['version']) ?? 1;
    final rawBarcode = _string(payload['barcode']) ?? '';
    final normalized = _string(payload['barcode_normalized']) ??
        BarcodeNormalizer.normalize(rawBarcode);
    final decision = await _decideIncomingVersion(
      table: 'local_product_barcodes',
      id: id,
      incomingVersion: incomingVersion,
    );

    if (decision != null) {
      return decision;
    }

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
      normalizeSqliteParameters([
        id,
        _string(payload['scope']) ?? 'global',
        _string(payload['business_id']),
        _string(payload['product_id']),
        _string(payload['master_product_id']),
        rawBarcode,
        normalized,
        _string(payload['barcode_type']) ??
            BarcodeNormalizer.inferBarcodeType(rawBarcode),
        _boolToInt(payload['is_primary']),
        _string(payload['status']) ?? 'active',
        _string(payload['source']),
        _double(payload['confidence_score']),
        _string(payload['sync_status']) ?? 'synced',
        incomingVersion,
        _dateTime(payload['updated_at']) ?? now,
        _dateTime(payload['deleted_at']),
        now,
      ]),
    );

    return payload['deleted_at'] == null
        ? _CatalogRecordApplyOutcome.applied
        : _CatalogRecordApplyOutcome.tombstoneApplied;
  }

  Future<_CatalogRecordApplyOutcome?> _decideIncomingVersion({
    required String table,
    required String id,
    required int incomingVersion,
  }) async {
    final row = await db.customSelect(
      'select version, local_status from $table where id = ? limit 1',
      variables: [Variable<String>(id)],
    ).getSingleOrNull();

    if (row == null) {
      return null;
    }

    final localStatus = _string(row.data['local_status']) ?? 'clean';
    if (localStatus != 'clean') {
      return _CatalogRecordApplyOutcome.dirtySkipped;
    }

    final localVersion = _int(row.data['version']) ?? 1;
    if (incomingVersion <= localVersion) {
      return _CatalogRecordApplyOutcome.staleIgnored;
    }

    return null;
  }

  Future<void> _saveCatalogSyncProgress({
    required String businessId,
    required DateTime? committedSince,
    required DateTime windowUpperBound,
    required int? catalogVersion,
    required Map<String, dynamic>? pageToken,
    required bool completed,
    required bool isSyncing,
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
        last_catalog_pull_at = coalesce(
          excluded.last_catalog_pull_at,
          local_catalog_sync_state.last_catalog_pull_at
        ),
        last_server_time = excluded.last_server_time,
        last_since_updated_at = excluded.last_since_updated_at,
        last_catalog_version = coalesce(
          excluded.last_catalog_version,
          local_catalog_sync_state.last_catalog_version
        ),
        last_page_token = excluded.last_page_token,
        is_syncing = excluded.is_syncing,
        last_error = excluded.last_error,
        updated_at = excluded.updated_at
      ''',
      normalizeSqliteParameters([
        businessId,
        businessId,
        completed ? now : null,
        windowUpperBound.toUtc(),
        completed ? windowUpperBound.toUtc() : committedSince?.toUtc(),
        completed ? catalogVersion : null,
        pageToken == null ? null : jsonEncode(pageToken),
        isSyncing ? 1 : 0,
        null,
        now,
        now,
      ]),
    );
  }

  Future<void> resetCatalogSyncResume({
    required String businessId,
    required bool clearCommittedCursor,
  }) async {
    final now = DateTime.now().toUtc();

    await _customStatement(
      db,
      '''
      insert into local_catalog_sync_state (
        id,
        business_id,
        last_since_updated_at,
        last_server_time,
        last_page_token,
        is_syncing,
        last_error,
        created_at,
        updated_at
      )
      values (?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(id) do update set
        last_since_updated_at = case
          when ? = 1 then null
          else local_catalog_sync_state.last_since_updated_at
        end,
        last_server_time = null,
        last_page_token = null,
        is_syncing = excluded.is_syncing,
        last_error = null,
        updated_at = excluded.updated_at
      ''',
      normalizeSqliteParameters([
        businessId,
        businessId,
        null,
        null,
        null,
        1,
        null,
        now,
        now,
        clearCommittedCursor ? 1 : 0,
      ]),
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
      normalizeSqliteParameters([
        businessId,
        businessId,
        1,
        now,
        now,
      ]),
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
      normalizeSqliteParameters([
        businessId,
        businessId,
        0,
        error.toString(),
        now,
        now,
      ]),
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
      normalizeSqliteParameters([
        id,
        businessId,
        branchId,
        localProductId,
        masterProductId,
        contributionType,
        barcode,
        normalizedBarcode,
        barcodeType ??
            (barcode == null
                ? null
                : BarcodeNormalizer.inferBarcodeType(barcode)),
        suggestedName,
        suggestedBrand,
        suggestedManufacturer,
        suggestedCategoryName,
        suggestedSubcategoryName,
        suggestedPackageSize,
        suggestedPackageUnit,
        suggestedUnitType,
        suggestedImageUrl,
        suggestedImageThumbUrl,
        suggestedImageHash,
        source,
        confidenceScore,
        metadata == null ? null : jsonEncode(metadata),
        'pending',
        0,
        now,
        now,
      ]),
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
      normalizeSqliteParameters([
        serverContributionId,
        now,
        now,
        localContributionId,
      ]),
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
      normalizeSqliteParameters([
        error.toString(),
        now,
        localContributionId,
      ]),
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

enum _CatalogRecordApplyOutcome {
  applied,
  tombstoneApplied,
  staleIgnored,
  dirtySkipped;

  bool get isApplied => this == applied || this == tombstoneApplied;
}

Future<void> _customStatement(
  AppDatabase db,
  String sql, [
  List<Object?> parameters = const [],
]) {
  return db.customStatement(
    sql,
    normalizeSqliteParameters(parameters),
  );
}
