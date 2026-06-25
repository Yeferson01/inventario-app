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
    if (input.salePrice < 0 || input.purchasePrice < 0) {
      throw ArgumentError('Los precios no pueden ser negativos.');
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
      'minimum_stock': 0,
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

    final mutations = _buildPendingMutations(
      input: input,
      productId: productId,
      businessBarcodeId: businessBarcodeId,
      productPayload: productPayload,
      barcodePayload: barcodePayload,
    );

    return CreatedLocalProductResult(
      productId: productId,
      businessId: input.businessId,
      masterProductId: draft.masterProductId,
      barcode: draft.barcode,
      barcodeNormalized: draft.barcodeNormalized,
      name: productName,
      productPayload: productPayload,
      businessBarcodePayload: barcodePayload,
      pendingMutations: mutations,
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

  Future<void> _insertOrUpdateExistingColumns({
    required String tableName,
    required Map<String, Object?> values,
  }) async {
    final columns = await _getTableColumns(tableName);

    final filtered = <String, Object?>{};
    for (final entry in values.entries) {
      if (columns.contains(entry.key)) {
        filtered[entry.key] = _normalizeSqlValue(entry.value);
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
      columnNames.map((column) => Variable<Object>(filtered[column])).toList(),
    );
  }

  Object? _normalizeSqlValue(Object? value) {
    if (value is DateTime) {
      return value.toUtc().toIso8601String();
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
