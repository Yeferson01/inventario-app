import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/app_uuid.dart';
import '../../../core/utils/barcode_normalizer.dart';
import 'inventory_product_creation_models.dart';

class InventoryProductCreationService {
  InventoryProductCreationService(this._db);

  final AppDatabase _db;

  ProductFromMasterDraft buildDraftFromMaster({
    required String businessId,
    required Map<String, dynamic> masterProduct,
    required Map<String, dynamic> barcodeRecord,
  }) {
    final masterProductId = _requiredString(masterProduct, 'id');

    final rawBarcode = _string(barcodeRecord['barcode']) ??
        _string(masterProduct['barcode']) ??
        '';

    final barcodeNormalized = _string(barcodeRecord['barcode_normalized']) ??
        _string(masterProduct['barcode_normalized']) ??
        BarcodeNormalizer.normalize(rawBarcode);

    final name = _string(masterProduct['product_name']) ??
        _string(masterProduct['name']) ??
        'Producto sin nombre';

    return ProductFromMasterDraft(
      businessId: businessId,
      masterProductId: masterProductId,
      barcode: rawBarcode,
      barcodeNormalized: barcodeNormalized,
      barcodeType: _string(barcodeRecord['barcode_type']) ??
          BarcodeNormalizer.inferBarcodeType(rawBarcode),
      name: name,
      brand: _string(masterProduct['brand']),
      manufacturer: _string(masterProduct['manufacturer']),
      categoryName: _string(masterProduct['category_name']),
      subcategoryName: _string(masterProduct['subcategory_name']),
      packageSize: _double(masterProduct['package_size']),
      packageUnit: _string(masterProduct['package_unit']),
      unitType: _string(masterProduct['unit_type']),
      imageThumbUrl: _string(masterProduct['image_thumb_url']),
      imageHash: _string(masterProduct['image_hash']),
      confidenceScore: _double(
        masterProduct['confidence_score'] ?? barcodeRecord['confidence_score'],
      ),
    );
  }

  Future<CreatedLocalProductResult> createLocalProductFromMaster(
    CreateProductFromMasterInput input,
  ) async {
    if (input.salePrice < 0 ||
        input.purchasePrice < 0 ||
        input.minimumStock < 0) {
      throw ArgumentError(
          'Los precios y el stock mínimo no pueden ser negativos.');
    }

    final draft = buildDraftFromMaster(
      businessId: input.businessId,
      masterProduct: input.masterProduct,
      barcodeRecord: input.barcodeRecord,
    );

    final now = DateTime.now().toUtc();
    final productId = AppUuid.v7();
    final businessBarcodeId = AppUuid.v7();

    final productName = input.nameOverride?.trim().isNotEmpty == true
        ? input.nameOverride!.trim()
        : draft.name;

    final productSyncStatus = await _pendingSyncValueForColumn(
      tableName: 'products',
      columnName: 'sync_status',
      textValue: 'pending_upload',
      intValue: 1,
    );

    final productLocalStatus = await _pendingSyncValueForColumn(
      tableName: 'products',
      columnName: 'local_status',
      textValue: 'dirty',
      intValue: 1,
    );

    final productPayload = <String, dynamic>{
      'id': productId,
      'business_id': input.businessId,
      'branch_id': input.branchId,
      'category_id': input.categoryId,
      'barcode': draft.barcode,
      'barcode_normalized': draft.barcodeNormalized,
      'name': productName,
      'description': input.description,
      'purchase_price': input.purchasePrice,
      'sale_price': input.salePrice,
      'stock_quantity': 0,
      'minimum_stock': input.minimumStock,
      'unit': input.unit ?? draft.packageUnit ?? draft.unitType ?? 'unidad',
      'status': 'active',
      'simple_category': draft.categoryName,
      'master_product_id': draft.masterProductId,
      'catalog_match_confidence': draft.confidenceScore,
      'catalog_linked_at': now.toIso8601String(),
      'sync_status': productSyncStatus,
      'local_status': productLocalStatus,
      'version': 1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'deleted_at': null,
      'last_synced_at': null,
      'metadata_json': {
        'created_from': 'master_catalog',
        'brand': draft.brand,
        'manufacturer': draft.manufacturer,
        'category_name': draft.categoryName,
        'subcategory_name': draft.subcategoryName,
        'package_size': draft.packageSize,
        'package_unit': draft.packageUnit,
        'unit_type': draft.unitType,
        'image_thumb_url': draft.imageThumbUrl,
        'image_hash': draft.imageHash,
      },
    };

    final barcodePayload = <String, dynamic>{
      'id': businessBarcodeId,
      'scope': 'business',
      'business_id': input.businessId,
      'product_id': productId,
      'master_product_id': draft.masterProductId,
      'barcode': draft.barcode,
      'barcode_normalized': draft.barcodeNormalized,
      'barcode_type': draft.barcodeType,
      'is_primary': 1,
      'status': 'active',
      'source': 'inventory_from_master',
      'confidence_score': draft.confidenceScore,
      'sync_status': 'pending_upload',
      'local_status': 'dirty',
      'version': 1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'deleted_at': null,
      'last_synced_at': null,
    };

    await _db.transaction(() async {
      await _insertOrUpdateExistingColumns(
        tableName: 'products',
        values: productPayload,
      );

      await _insertOrUpdateExistingColumns(
        tableName: 'local_product_barcodes',
        values: barcodePayload,
      );
    });

    final persistedProductPayload = await _readPersistedProductSyncPayload(
      businessId: input.businessId,
      productId: productId,
      branchId: input.branchId,
    );

    final mutations = _buildPendingMutations(
      input: input,
      productId: productId,
      businessBarcodeId: businessBarcodeId,
      productPayload: persistedProductPayload,
      barcodePayload: barcodePayload,
    );

    return CreatedLocalProductResult(
      productId: productId,
      businessId: input.businessId,
      masterProductId: draft.masterProductId,
      barcode: draft.barcode,
      barcodeNormalized: draft.barcodeNormalized,
      name: productName,
      productPayload: persistedProductPayload,
      businessBarcodePayload: barcodePayload,
      pendingMutations: mutations,
    );
  }

  Future<CreatedManualLocalProductResult> createManualLocalProduct(
    CreateManualLocalProductInput input,
  ) async {
    final productName = input.name.trim();

    if (productName.length < 2) {
      throw ArgumentError('El nombre del producto es requerido.');
    }

    if (input.purchasePrice < 0 ||
        input.salePrice < 0 ||
        input.minimumStock < 0) {
      throw ArgumentError(
          'Los precios y el stock mínimo no pueden ser negativos.');
    }

    final now = DateTime.now().toUtc();
    final productId = AppUuid.v7();

    final rawBarcode = input.barcode?.trim();
    final hasBarcode = rawBarcode != null && rawBarcode.isNotEmpty;
    final barcodeNormalized =
        hasBarcode ? BarcodeNormalizer.normalize(rawBarcode) : null;
    final barcodeType = hasBarcode
        ? BarcodeNormalizer.inferBusinessBarcodeType(rawBarcode)
        : null;

    final productSyncStatus = await _pendingSyncValueForColumn(
      tableName: 'products',
      columnName: 'sync_status',
      textValue: 'pending_upload',
      intValue: 1,
    );

    final productLocalStatus = await _pendingSyncValueForColumn(
      tableName: 'products',
      columnName: 'local_status',
      textValue: 'dirty',
      intValue: 1,
    );

    final productPayload = <String, dynamic>{
      'id': productId,
      'business_id': input.businessId,
      'branch_id': input.branchId,
      'category_id': input.categoryId,
      'barcode': hasBarcode ? rawBarcode : null,
      'barcode_normalized': barcodeNormalized,
      'name': productName,
      'description': input.description,
      'purchase_price': input.purchasePrice,
      'sale_price': input.salePrice,
      'stock_quantity': 0,
      'minimum_stock': input.minimumStock,
      'unit': input.unit ?? 'unidad',
      'status': 'active',
      'simple_category': null,
      'master_product_id': null,
      'catalog_match_confidence': null,
      'catalog_linked_at': null,
      'sync_status': productSyncStatus,
      'local_status': productLocalStatus,
      'version': 1,
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
      'deleted_at': null,
      'last_synced_at': null,
      'metadata_json': {
        'created_from': 'quick_purchase_manual_product',
        'catalog_status': 'manual_unmatched',
        'source': 'purchase_entry_screen',
        'app_device_id': input.appDeviceId,
        'device_installation_id': input.deviceInstallationId,
      },
    };

    Map<String, dynamic>? barcodePayload;
    String? businessBarcodeId;

    if (hasBarcode) {
      businessBarcodeId = AppUuid.v7();

      barcodePayload = <String, dynamic>{
        'id': businessBarcodeId,
        'scope': 'business',
        'business_id': input.businessId,
        'product_id': productId,
        'master_product_id': null,
        'barcode': rawBarcode,
        'barcode_normalized': barcodeNormalized,
        'barcode_type': barcodeType,
        'is_primary': 1,
        'status': 'active',
        'source': 'quick_purchase_manual_product',
        'confidence_score': null,
        'sync_status': 'pending_upload',
        'local_status': 'dirty',
        'version': 1,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
        'deleted_at': null,
        'last_synced_at': null,
      };
    }

    await _db.transaction(() async {
      await _insertOrUpdateExistingColumns(
        tableName: 'products',
        values: productPayload,
      );

      if (barcodePayload != null) {
        await _insertOrUpdateExistingColumns(
          tableName: 'local_product_barcodes',
          values: barcodePayload,
        );
      }
    });

    final persistedProductPayload = await _readPersistedProductSyncPayload(
      businessId: input.businessId,
      productId: productId,
      branchId: input.branchId,
    );

    final pendingMutations = _buildManualPendingMutations(
      input: input,
      productId: productId,
      businessBarcodeId: businessBarcodeId,
      productPayload: persistedProductPayload,
      barcodePayload: barcodePayload,
    );

    return CreatedManualLocalProductResult(
      productId: productId,
      businessId: input.businessId,
      name: productName,
      barcode: hasBarcode ? rawBarcode : null,
      barcodeNormalized: barcodeNormalized,
      productPayload: persistedProductPayload,
      businessBarcodePayload: barcodePayload,
      pendingMutations: pendingMutations,
    );
  }

  Future<LinkedLocalProductToMasterResult> linkLocalProductToMaster(
    LinkLocalProductToMasterInput input,
  ) async {
    final businessId = input.businessId.trim();
    final productId = input.productId.trim();
    final masterProductId = input.masterProductId.trim();
    if (businessId.isEmpty || productId.isEmpty || masterProductId.isEmpty) {
      throw ArgumentError(
        'businessId, productId y masterProductId son requeridos.',
      );
    }

    final product = await _getActiveBusinessProduct(
      businessId: businessId,
      productId: productId,
    );
    if (product == null) {
      throw StateError('El Product empresarial no existe o no está activo.');
    }

    final currentMasterProductId = _string(product['master_product_id']);
    if (currentMasterProductId != null &&
        currentMasterProductId != masterProductId) {
      throw StateError(
        'El Product ya está vinculado a otro MasterProduct.',
      );
    }

    final master = await _db.customSelect(
      '''
      select id
      from local_master_products_catalog
      where id = ? and deleted_at is null
      limit 1
      ''',
      variables: [Variable<String>(masterProductId)],
      readsFrom: {_db.localMasterProductsCatalog},
    ).getSingleOrNull();
    if (master == null) {
      throw StateError('El MasterProduct no existe en el catálogo local.');
    }

    final now = DateTime.now().toUtc();
    final productSyncStatus = await _pendingSyncValueForColumn(
      tableName: 'products',
      columnName: 'sync_status',
      textValue: 'pending_upload',
      intValue: 1,
    );

    Map<String, dynamic>? barcodePayload;
    String? businessBarcodeId;
    final barcodeRecord = input.barcodeRecord;
    final rawBarcode = _string(barcodeRecord?['barcode']);
    if (rawBarcode != null) {
      final recordMasterId = _string(barcodeRecord?['master_product_id']);
      if (recordMasterId != null && recordMasterId != masterProductId) {
        throw StateError(
          'El código seleccionado pertenece a otro MasterProduct.',
        );
      }

      final barcodeType = _string(barcodeRecord?['barcode_type']) ??
          BarcodeNormalizer.inferBarcodeType(rawBarcode);
      if (BarcodeNormalizer.isInternalBusinessType(barcodeType)) {
        throw StateError(
          'Un código interno no puede materializar una identidad master.',
        );
      }

      final barcodeNormalized = _string(barcodeRecord?['barcode_normalized']) ??
          BarcodeNormalizer.normalize(rawBarcode);
      if (barcodeNormalized.isEmpty) {
        throw StateError('El código master no puede normalizarse vacío.');
      }

      final existingBarcode = await _getActiveBusinessBarcode(
        businessId: businessId,
        barcodeNormalized: barcodeNormalized,
      );
      final existingProductId = _string(existingBarcode?['product_id']);
      if (existingProductId != null && existingProductId != productId) {
        throw StateError(
          'El código ya pertenece a otro Product activo del negocio.',
        );
      }

      businessBarcodeId = _string(existingBarcode?['id']) ?? AppUuid.v7();
      final alreadyHasPrimary = await _hasActivePrimaryBusinessCode(
        businessId: businessId,
        productId: productId,
        excludingBarcodeId: businessBarcodeId,
      );
      final isPrimary = existingBarcode == null
          ? !alreadyHasPrimary
          : _intOrDefault(existingBarcode['is_primary'], 0) == 1;

      barcodePayload = <String, dynamic>{
        'id': businessBarcodeId,
        'scope': 'business',
        'business_id': businessId,
        'product_id': productId,
        'master_product_id': masterProductId,
        'barcode': rawBarcode,
        'barcode_normalized': barcodeNormalized,
        'barcode_type': barcodeType,
        'is_primary': isPrimary ? 1 : 0,
        'status': 'active',
        'source': _string(existingBarcode?['source']) ?? 'master_link',
        'confidence_score': _double(
          barcodeRecord?['confidence_score'] ??
              existingBarcode?['confidence_score'],
        ),
        'sync_status': 'pending_upload',
        'local_status': 'dirty',
        'version': _intOrDefault(existingBarcode?['version'], 1),
        'created_at': _isoStringOrFallback(
          existingBarcode?['created_at'],
          now,
        ),
        'updated_at': now.toIso8601String(),
        'deleted_at': null,
        'last_synced_at': null,
      };
    }

    await _db.transaction(() async {
      await _db.customStatement(
        '''
        update products
        set master_product_id = ?, sync_status = ?, updated_at = ?
        where id = ? and business_id = ? and deleted_at is null
        ''',
        [
          masterProductId,
          productSyncStatus,
          now.millisecondsSinceEpoch ~/ 1000,
          productId,
          businessId,
        ],
      );

      if (barcodePayload != null) {
        await _insertOrUpdateExistingColumns(
          tableName: 'local_product_barcodes',
          values: barcodePayload,
        );
      }
    });

    final persistedProductPayload = await _readPersistedProductSyncPayload(
      businessId: businessId,
      productId: productId,
      branchId: input.branchId,
    );
    final persistedBarcodePayload = businessBarcodeId == null
        ? null
        : await _readPersistedBusinessBarcodePayload(
            businessId: businessId,
            barcodeId: businessBarcodeId,
          );
    final pendingMutations = _buildMasterLinkPendingMutations(
      input: input,
      productPayload: persistedProductPayload,
      barcodeId: businessBarcodeId,
      barcodePayload: persistedBarcodePayload,
    );

    return LinkedLocalProductToMasterResult(
      productId: productId,
      businessId: businessId,
      masterProductId: masterProductId,
      businessBarcodeId: businessBarcodeId,
      productPayload: persistedProductPayload,
      businessBarcodePayload: persistedBarcodePayload,
      pendingMutations: pendingMutations,
    );
  }

  List<PendingCatalogSyncMutationDraft> _buildManualPendingMutations({
    required CreateManualLocalProductInput input,
    required String productId,
    required String? businessBarcodeId,
    required Map<String, dynamic> productPayload,
    required Map<String, dynamic>? barcodePayload,
  }) {
    final installationId = input.deviceInstallationId?.trim().isNotEmpty == true
        ? input.deviceInstallationId!.trim()
        : 'local-device';

    final productSequence = input.clientSequenceStart;
    final mutations = <PendingCatalogSyncMutationDraft>[
      PendingCatalogSyncMutationDraft(
        clientMutationId: '$installationId:mutation:$productSequence',
        clientSequence: productSequence,
        entityTable: 'products',
        entityId: productId,
        operation: 'insert',
        payload: productPayload,
        changedFields: productPayload.keys.toList(),
        idempotencyKey:
            '$installationId:products:$productId:insert:$productSequence',
        businessId: input.businessId,
        branchId: input.branchId,
        profileId: input.profileId,
        appDeviceId: input.appDeviceId,
      ),
    ];

    if (businessBarcodeId != null && barcodePayload != null) {
      final barcodeSequence = input.clientSequenceStart + 1;

      mutations.add(
        PendingCatalogSyncMutationDraft(
          clientMutationId: '$installationId:mutation:$barcodeSequence',
          clientSequence: barcodeSequence,
          entityTable: 'product_barcodes',
          entityId: businessBarcodeId,
          operation: 'insert',
          payload: barcodePayload,
          changedFields: barcodePayload.keys.toList(),
          idempotencyKey:
              '$installationId:product_barcodes:$businessBarcodeId:insert:$barcodeSequence',
          businessId: input.businessId,
          branchId: input.branchId,
          profileId: input.profileId,
          appDeviceId: input.appDeviceId,
        ),
      );
    }

    return mutations;
  }

  List<PendingCatalogSyncMutationDraft> _buildMasterLinkPendingMutations({
    required LinkLocalProductToMasterInput input,
    required Map<String, dynamic> productPayload,
    required String? barcodeId,
    required Map<String, dynamic>? barcodePayload,
  }) {
    final installationId = input.deviceInstallationId?.trim().isNotEmpty == true
        ? input.deviceInstallationId!.trim()
        : 'local-device';
    final productSequence = input.clientSequenceStart;
    final mutations = <PendingCatalogSyncMutationDraft>[
      PendingCatalogSyncMutationDraft(
        clientMutationId:
            '$installationId:master-link:products:${input.productId}:${input.masterProductId}',
        clientSequence: productSequence,
        entityTable: 'products',
        entityId: input.productId,
        operation: 'upsert',
        payload: productPayload,
        changedFields: const ['master_product_id', 'updated_at'],
        idempotencyKey:
            '$installationId:master-link:products:${input.productId}:${input.masterProductId}',
        businessId: input.businessId,
        branchId: input.branchId,
        profileId: input.profileId,
        appDeviceId: input.appDeviceId,
      ),
    ];

    if (barcodeId != null && barcodePayload != null) {
      mutations.add(
        PendingCatalogSyncMutationDraft(
          clientMutationId:
              '$installationId:master-link:product-barcodes:$barcodeId',
          clientSequence: productSequence + 1,
          entityTable: 'product_barcodes',
          entityId: barcodeId,
          operation: 'upsert',
          payload: barcodePayload,
          changedFields: const [
            'master_product_id',
            'barcode',
            'barcode_normalized',
            'barcode_type',
            'is_primary',
            'status',
            'updated_at',
          ],
          idempotencyKey:
              '$installationId:master-link:product-barcodes:$barcodeId',
          businessId: input.businessId,
          branchId: input.branchId,
          profileId: input.profileId,
          appDeviceId: input.appDeviceId,
        ),
      );
    }

    return mutations;
  }

  Future<Set<String>> _inventoryLocalTableColumnNames(
    String tableName,
  ) async {
    const allowedTables = {
      'products',
      'purchases',
      'purchase_items',
      'local_product_barcodes',
    };

    if (!allowedTables.contains(tableName)) {
      throw ArgumentError.value(tableName, 'tableName', 'Tabla no permitida');
    }

    final rows = await _db
        .customSelect(
          'pragma table_info($tableName)',
        )
        .get();

    return rows
        .map((row) => row.data['name']?.toString())
        .whereType<String>()
        .where((name) => name.trim().isNotEmpty)
        .toSet();
  }

  Future<List<String>> getManualProductIdsUsedByUnsyncedPurchases({
    required String businessId,
    required String branchId,
    int limit = 100,
  }) async {
    final productColumns = await _inventoryLocalTableColumnNames('products');
    final purchaseColumns = await _inventoryLocalTableColumnNames('purchases');
    final itemColumns = await _inventoryLocalTableColumnNames('purchase_items');

    final whereParts = <String>[];
    final variables = <Variable>[];

    whereParts.add('pi.business_id = ?');
    variables.add(Variable<String>(businessId));

    if (itemColumns.contains('branch_id')) {
      whereParts.add('pi.branch_id = ?');
      variables.add(Variable<String>(branchId));
    }

    if (itemColumns.contains('deleted_at')) {
      whereParts.add('pi.deleted_at is null');
    }

    if (purchaseColumns.contains('deleted_at')) {
      whereParts.add('p.deleted_at is null');
    }

    if (productColumns.contains('deleted_at')) {
      whereParts.add('pr.deleted_at is null');
    }

    // El repair de compras solo crea drafts para Products todavía manuales.
    // La guarda mantiene compatibilidad con bases anteriores a schema 10.
    if (productColumns.contains('master_product_id')) {
      whereParts.add(
        "trim(coalesce(cast(pr.master_product_id as text), '')) = ''",
      );
    }

    final pendingParts = <String>[];

    void addPendingStatusCondition(
      Set<String> columns,
      String alias,
      String columnName,
    ) {
      if (columns.contains(columnName)) {
        pendingParts.add(
          "coalesce(cast($alias.$columnName as text), '0') "
          "not in ('0', 'synced')",
        );
      }
    }

    void addDirtyLocalStatusCondition(
      Set<String> columns,
      String alias,
      String columnName,
    ) {
      if (columns.contains(columnName)) {
        pendingParts.add(
          "coalesce(cast($alias.$columnName as text), '') != 'synced'",
        );
      }
    }

    addPendingStatusCondition(productColumns, 'pr', 'sync_status');
    addDirtyLocalStatusCondition(productColumns, 'pr', 'local_status');

    if (productColumns.contains('last_synced_at')) {
      pendingParts.add(
        "coalesce(cast(pr.last_synced_at as text), '') = ''",
      );
    }

    addPendingStatusCondition(purchaseColumns, 'p', 'sync_status');
    addPendingStatusCondition(itemColumns, 'pi', 'sync_status');

    addDirtyLocalStatusCondition(purchaseColumns, 'p', 'local_status');
    addDirtyLocalStatusCondition(itemColumns, 'pi', 'local_status');

    if (pendingParts.isEmpty) {
      return const <String>[];
    }

    whereParts.add('(${pendingParts.join(' or ')})');

    final orderBy = itemColumns.contains('created_at')
        ? 'pi.created_at asc'
        : 'pi.product_id asc';

    variables.add(Variable<int>(limit));

    final rows = await _db.customSelect(
      '''
      select distinct pi.product_id as product_id
      from purchase_items pi
      join purchases p
        on p.id = pi.purchase_id
      join products pr
        on pr.id = pi.product_id
       and pr.business_id = pi.business_id
      where ${whereParts.join('\n        and ')}
      order by $orderBy
      limit ?
      ''',
      variables: variables,
    ).get();

    return rows
        .map((row) => row.data['product_id']?.toString())
        .whereType<String>()
        .where((value) => value.trim().isNotEmpty)
        .toList();
  }

  Future<CreatedManualLocalProductResult?>
      buildExistingManualProductCatalogSyncDraft({
    required String businessId,
    required String productId,
    String? branchId,
    String? profileId,
    String? appDeviceId,
    String? deviceInstallationId,
    int clientSequenceStart = 1,
  }) async {
    final productRows = await _db.customSelect(
      '''
      select *
      from products
      where id = ?
        and business_id = ?
        and deleted_at is null
      limit 1
      ''',
      variables: [
        Variable<String>(productId),
        Variable<String>(businessId),
      ],
    ).get();

    if (productRows.isEmpty) {
      return null;
    }

    final product = Map<String, dynamic>.from(productRows.first.data);
    final now = DateTime.now().toUtc();

    final name = _string(product['name'])?.trim();
    if (name == null || name.length < 2) {
      return null;
    }

    final barcodeRows = await _db.customSelect(
      '''
      select *
      from local_product_barcodes
      where business_id = ?
        and product_id = ?
        and deleted_at is null
      order by is_primary desc, created_at asc
      limit 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(productId),
      ],
    ).get();

    final barcodeRow = barcodeRows.isEmpty
        ? null
        : Map<String, dynamic>.from(barcodeRows.first.data);

    final rawBarcode =
        _string(barcodeRow?['barcode']) ?? _string(product['barcode']);
    final hasBarcode = rawBarcode != null && rawBarcode.trim().isNotEmpty;

    final barcodeNormalized = hasBarcode
        ? (_string(barcodeRow?['barcode_normalized']) ??
            _string(product['barcode_normalized']) ??
            BarcodeNormalizer.normalize(rawBarcode))
        : null;

    final productSyncStatus = await _pendingSyncValueForColumn(
      tableName: 'products',
      columnName: 'sync_status',
      textValue: 'pending_upload',
      intValue: 1,
    );

    final productLocalStatus = await _pendingSyncValueForColumn(
      tableName: 'products',
      columnName: 'local_status',
      textValue: 'dirty',
      intValue: 1,
    );

    final productPayload = <String, dynamic>{
      'id': productId,
      'business_id': businessId,
      'branch_id': branchId ?? _string(product['branch_id']),
      'category_id': _string(product['category_id']),
      'barcode': hasBarcode ? rawBarcode : null,
      'barcode_normalized': barcodeNormalized,
      'name': name,
      'description': _string(product['description']),
      'purchase_price': _double(product['purchase_price']) ?? 0,
      'sale_price': _double(product['sale_price']) ?? 0,
      'stock_quantity': _intOrDefault(product['stock_quantity'], 0),
      'minimum_stock': _intOrDefault(product['minimum_stock'], 0),
      'unit': _string(product['unit']) ?? 'unidad',
      'status': _string(product['status']) ?? 'active',
      'simple_category': _string(product['simple_category']),
      'master_product_id': _string(product['master_product_id']),
      'catalog_match_confidence': null,
      'catalog_linked_at': null,
      'sync_status': productSyncStatus,
      'local_status': productLocalStatus,
      'version': _intOrDefault(product['version'], 1),
      'created_at': _isoStringOrFallback(product['created_at'], now),
      'updated_at': now.toIso8601String(),
      'deleted_at': null,
      'last_synced_at': null,
      'metadata_json': {
        'created_from': 'quick_purchase_manual_product',
        'catalog_status': 'manual_unmatched',
        'source': 'purchase_catalog_backfill',
        'app_device_id': appDeviceId,
        'device_installation_id': deviceInstallationId,
      },
    };

    Map<String, dynamic>? barcodePayload;
    String? businessBarcodeId;

    if (barcodeRow != null && hasBarcode) {
      businessBarcodeId = _requiredString(barcodeRow, 'id');

      barcodePayload = <String, dynamic>{
        'id': businessBarcodeId,
        'scope': _string(barcodeRow['scope']) ?? 'business',
        'business_id': businessId,
        'product_id': productId,
        'master_product_id': _string(product['master_product_id']),
        'barcode': rawBarcode,
        'barcode_normalized': barcodeNormalized,
        'barcode_type': _string(barcodeRow['barcode_type']) ??
            BarcodeNormalizer.inferBusinessBarcodeType(rawBarcode),
        'is_primary': _intOrDefault(barcodeRow['is_primary'], 1),
        'status': _string(barcodeRow['status']) ?? 'active',
        'source':
            _string(barcodeRow['source']) ?? 'quick_purchase_manual_product',
        'confidence_score': _double(barcodeRow['confidence_score']),
        'sync_status': 'pending_upload',
        'local_status': 'dirty',
        'version': _intOrDefault(barcodeRow['version'], 1),
        'created_at': _isoStringOrFallback(barcodeRow['created_at'], now),
        'updated_at': now.toIso8601String(),
        'deleted_at': null,
        'last_synced_at': null,
      };
    }

    final installationId = deviceInstallationId?.trim().isNotEmpty == true
        ? deviceInstallationId!.trim()
        : 'local-device';

    final pendingMutations = <PendingCatalogSyncMutationDraft>[
      PendingCatalogSyncMutationDraft(
        clientMutationId:
            '$installationId:catalog-backfill:products:$productId',
        clientSequence: clientSequenceStart,
        entityTable: 'products',
        entityId: productId,
        operation: 'insert',
        payload: productPayload,
        changedFields: productPayload.keys.toList(),
        idempotencyKey:
            '$installationId:catalog-backfill:products:$productId:insert',
        businessId: businessId,
        branchId: branchId,
        profileId: profileId,
        appDeviceId: appDeviceId,
      ),
    ];

    if (businessBarcodeId != null && barcodePayload != null) {
      pendingMutations.add(
        PendingCatalogSyncMutationDraft(
          clientMutationId:
              '$installationId:catalog-backfill:product-barcodes:$businessBarcodeId',
          clientSequence: clientSequenceStart + 1,
          entityTable: 'product_barcodes',
          entityId: businessBarcodeId,
          operation: 'insert',
          payload: barcodePayload,
          changedFields: barcodePayload.keys.toList(),
          idempotencyKey:
              '$installationId:catalog-backfill:product-barcodes:$businessBarcodeId:insert',
          businessId: businessId,
          branchId: branchId,
          profileId: profileId,
          appDeviceId: appDeviceId,
        ),
      );
    }

    return CreatedManualLocalProductResult(
      productId: productId,
      businessId: businessId,
      name: name,
      barcode: hasBarcode ? rawBarcode : null,
      barcodeNormalized: barcodeNormalized,
      productPayload: productPayload,
      businessBarcodePayload: barcodePayload,
      pendingMutations: pendingMutations,
    );
  }

  List<PendingCatalogSyncMutationDraft> _buildPendingMutations({
    required CreateProductFromMasterInput input,
    required String productId,
    required String businessBarcodeId,
    required Map<String, dynamic> productPayload,
    required Map<String, dynamic> barcodePayload,
  }) {
    final installationId = input.deviceInstallationId?.trim().isNotEmpty == true
        ? input.deviceInstallationId!.trim()
        : 'local-device';

    final productSequence = input.clientSequenceStart;
    final barcodeSequence = input.clientSequenceStart + 1;

    return [
      PendingCatalogSyncMutationDraft(
        clientMutationId: '$installationId:mutation:$productSequence',
        clientSequence: productSequence,
        entityTable: 'products',
        entityId: productId,
        operation: 'insert',
        payload: productPayload,
        changedFields: productPayload.keys.toList(),
        idempotencyKey:
            '$installationId:products:$productId:insert:$productSequence',
        businessId: input.businessId,
        branchId: input.branchId,
        profileId: input.profileId,
        appDeviceId: input.appDeviceId,
      ),
      PendingCatalogSyncMutationDraft(
        clientMutationId: '$installationId:mutation:$barcodeSequence',
        clientSequence: barcodeSequence,
        entityTable: 'product_barcodes',
        entityId: businessBarcodeId,
        operation: 'insert',
        payload: barcodePayload,
        changedFields: barcodePayload.keys.toList(),
        idempotencyKey:
            '$installationId:product_barcodes:$businessBarcodeId:insert:$barcodeSequence',
        businessId: input.businessId,
        branchId: input.branchId,
        profileId: input.profileId,
        appDeviceId: input.appDeviceId,
      ),
    ];
  }

  Future<Map<String, dynamic>?> _getActiveBusinessProduct({
    required String businessId,
    required String productId,
  }) async {
    final row = await _db.customSelect(
      '''
      select *
      from products
      where id = ?
        and business_id = ?
        and deleted_at is null
        and status = 'active'
      limit 1
      ''',
      variables: [
        Variable<String>(productId),
        Variable<String>(businessId),
      ],
      readsFrom: {_db.products},
    ).getSingleOrNull();
    return row == null ? null : Map<String, dynamic>.from(row.data);
  }

  Future<Map<String, dynamic>?> _getActiveBusinessBarcode({
    required String businessId,
    required String barcodeNormalized,
  }) async {
    final row = await _db.customSelect(
      '''
      select *
      from local_product_barcodes
      where scope = 'business'
        and business_id = ?
        and barcode_normalized = ?
        and status = 'active'
        and deleted_at is null
      order by updated_at desc, id
      limit 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(barcodeNormalized),
      ],
      readsFrom: {_db.localProductBarcodes},
    ).getSingleOrNull();
    return row == null ? null : Map<String, dynamic>.from(row.data);
  }

  Future<bool> _hasActivePrimaryBusinessCode({
    required String businessId,
    required String productId,
    required String excludingBarcodeId,
  }) async {
    final row = await _db.customSelect(
      '''
      select 1
      from local_product_barcodes
      where scope = 'business'
        and business_id = ?
        and product_id = ?
        and id <> ?
        and is_primary = 1
        and status = 'active'
        and deleted_at is null
      limit 1
      ''',
      variables: [
        Variable<String>(businessId),
        Variable<String>(productId),
        Variable<String>(excludingBarcodeId),
      ],
      readsFrom: {_db.localProductBarcodes},
    ).getSingleOrNull();
    return row != null;
  }

  Future<Map<String, dynamic>> _readPersistedProductSyncPayload({
    required String businessId,
    required String productId,
    String? branchId,
  }) async {
    final product = await _getActiveBusinessProduct(
      businessId: businessId,
      productId: productId,
    );
    if (product == null) {
      throw StateError('No se pudo releer el Product persistido.');
    }

    final now = DateTime.now().toUtc();
    return <String, dynamic>{
      'id': productId,
      'business_id': businessId,
      'branch_id': branchId,
      'category_id': _string(product['category_id']),
      'barcode': _string(product['barcode']),
      'name': _requiredString(product, 'name'),
      'description': _string(product['description']),
      'purchase_price': _double(product['purchase_price']) ?? 0,
      'sale_price': _double(product['sale_price']) ?? 0,
      'stock_quantity': _intOrDefault(product['stock_quantity'], 0),
      'minimum_stock': _intOrDefault(product['minimum_stock'], 0),
      'unit': _string(product['unit']) ?? 'unidad',
      'status': _string(product['status']) ?? 'active',
      'simple_category': _string(product['simple_category']),
      'master_product_id': _string(product['master_product_id']),
      'created_at': _isoStringOrFallback(product['created_at'], now),
      'updated_at': _isoStringOrFallback(product['updated_at'], now),
      'deleted_at': null,
    };
  }

  Future<Map<String, dynamic>> _readPersistedBusinessBarcodePayload({
    required String businessId,
    required String barcodeId,
  }) async {
    final row = await _db.customSelect(
      '''
      select *
      from local_product_barcodes
      where id = ?
        and scope = 'business'
        and business_id = ?
        and status = 'active'
        and deleted_at is null
      limit 1
      ''',
      variables: [
        Variable<String>(barcodeId),
        Variable<String>(businessId),
      ],
      readsFrom: {_db.localProductBarcodes},
    ).getSingleOrNull();
    if (row == null) {
      throw StateError('No se pudo releer el código empresarial persistido.');
    }
    final barcode = Map<String, dynamic>.from(row.data);
    final now = DateTime.now().toUtc();
    return <String, dynamic>{
      'id': barcodeId,
      'scope': 'business',
      'business_id': businessId,
      'product_id': _requiredString(barcode, 'product_id'),
      'master_product_id': _string(barcode['master_product_id']),
      'barcode': _requiredString(barcode, 'barcode'),
      'barcode_normalized': _requiredString(barcode, 'barcode_normalized'),
      'barcode_type': _string(barcode['barcode_type']) ?? 'unknown',
      'is_primary': _intOrDefault(barcode['is_primary'], 0),
      'status': _string(barcode['status']) ?? 'active',
      'source': _string(barcode['source']),
      'confidence_score': _double(barcode['confidence_score']),
      'version': _intOrDefault(barcode['version'], 1),
      'created_at': _isoStringOrFallback(barcode['created_at'], now),
      'updated_at': _isoStringOrFallback(barcode['updated_at'], now),
      'deleted_at': null,
    };
  }

  Future<void> _insertOrUpdateExistingColumns({
    required String tableName,
    required Map<String, Object?> values,
  }) async {
    final columns = await _getTableColumns(tableName);

    final filtered = <String, Object?>{};
    for (final entry in values.entries) {
      if (columns.contains(entry.key)) {
        filtered[entry.key] = _normalizeSqlValue(
          entry.value,
          columnName: entry.key,
        );
      }
    }

    if (!filtered.containsKey('id')) {
      throw StateError(
          'La tabla $tableName no tiene columna id o no se envió id.');
    }

    final columnNames = filtered.keys.toList();
    final placeholders = List.filled(columnNames.length, '?').join(', ');
    final updateColumns =
        columnNames.where((column) => column != 'id').toList();

    final updateSet = updateColumns.map((column) {
      return '$column = excluded.$column';
    }).join(', ');

    if (updateSet.isEmpty) {
      throw StateError('No hay columnas actualizables para $tableName.');
    }

    final sql = '''
      insert into $tableName (${columnNames.join(', ')})
      values ($placeholders)
      on conflict(id) do update set
        $updateSet
    ''';

    await _db.customStatement(
      sql,
      columnNames.map((column) => filtered[column]).toList(),
    );
  }

  int _intOrDefault(Object? value, int fallback) {
    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  String _isoStringOrFallback(Object? value, DateTime fallback) {
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
    }

    final parsed = DateTime.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      return parsed.toUtc().toIso8601String();
    }

    return fallback.toIso8601String();
  }

  Object? _normalizeSqlValue(
    Object? value, {
    required String columnName,
  }) {
    if (value is DateTime) {
      return value.toUtc().millisecondsSinceEpoch ~/ 1000;
    }

    if (value is String && columnName.endsWith('_at')) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) {
        return parsed.toUtc().millisecondsSinceEpoch ~/ 1000;
      }
    }

    if (value is Map || value is List) {
      return value.toString();
    }

    return value;
  }

  Future<Object?> _pendingSyncValueForColumn({
    required String tableName,
    required String columnName,
    required String textValue,
    required int intValue,
  }) async {
    final columnTypes = await _getTableColumnTypes(tableName);
    final type = columnTypes[columnName]?.toUpperCase();

    if (type == null) {
      return textValue;
    }

    if (type.contains('INT')) {
      return intValue;
    }

    return textValue;
  }

  Future<Set<String>> _getTableColumns(String tableName) async {
    final rows = await _db.customSelect('pragma table_info($tableName)').get();

    return rows.map((row) => row.data['name']).whereType<String>().toSet();
  }

  Future<Map<String, String>> _getTableColumnTypes(String tableName) async {
    final rows = await _db.customSelect('pragma table_info($tableName)').get();

    return {
      for (final row in rows)
        if (row.data['name'] is String)
          row.data['name'] as String: row.data['type']?.toString() ?? '',
    };
  }

  String _requiredString(Map<String, dynamic> source, String key) {
    final value = _string(source[key]);

    if (value == null) {
      throw ArgumentError('Campo requerido ausente: $key');
    }

    return value;
  }

  String? _string(Object? value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
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
}
