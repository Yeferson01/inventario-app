import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../inventory/application/inventory_product_creation_models.dart';
import '../../inventory/application/inventory_product_from_master_sync_service.dart';
import 'app_e2e_local_flow_models.dart';
import 'app_e2e_local_flow_service.dart';
import 'app_e2e_product_from_catalog_flow_models.dart';

class AppE2EProductFromCatalogFlowService {
  AppE2EProductFromCatalogFlowService({
    required AppDatabase db,
    required AppE2ELocalFlowService localFlowService,
    required InventoryProductFromMasterSyncService productFromMasterSyncService,
  })  : _db = db,
        _localFlowService = localFlowService,
        _productFromMasterSyncService = productFromMasterSyncService;

  final AppDatabase _db;
  final AppE2ELocalFlowService _localFlowService;
  final InventoryProductFromMasterSyncService _productFromMasterSyncService;

  Future<AppE2EProductFromCatalogFlowResult> run(
    AppE2EProductFromCatalogFlowInput input,
  ) async {
    var preflight = await _localFlowService.run(
      AppE2ELocalFlowInput(
        profileId: input.profileId,
        preferredBusinessId: input.preferredBusinessId,
        preferredBranchId: input.preferredBranchId,
        isOnline: input.isOnline,
        lastSyncStatus: input.lastSyncStatus,
        // Para crear outbox válido necesitamos runtime/app_device remoto.
        // El sync manual registra el device y resuelve infraestructura ya
        // existente; cualquier setup administrativo faltante es una acción
        // explícita y separada.
        runManualSync: true,
        deviceName: input.deviceName,
        platform: input.platform,
        appVersion: input.appVersion,
        osVersion: input.osVersion,
        metadata: {
          if (input.metadata != null) ...input.metadata!,
          'source': 'app_e2e_product_from_catalog_flow_preflight',
        },
      ),
    );

    if (!preflight.successfulLocalValidation) {
      throw StateError(
        'No se pudo validar contexto local antes de crear producto: '
        '${preflight.reason}',
      );
    }

    final businessId = input.preferredBusinessId ??
        _string(preflight.currentContext?.toJson()['business_id']);

    if (businessId == null) {
      throw StateError('No se pudo resolver business_id para la prueba.');
    }

    final branchId = input.preferredBranchId ??
        _string(preflight.currentContext?.toJson()['branch_id']);

    var candidate = await _findCatalogCandidate(businessId: businessId);

    if (candidate == null && input.isOnline) {
      preflight = await _localFlowService.run(
        AppE2ELocalFlowInput(
          profileId: input.profileId,
          preferredBusinessId: businessId,
          preferredBranchId: branchId,
          isOnline: input.isOnline,
          lastSyncStatus: input.lastSyncStatus,
          runManualSync: true,
          deviceName: input.deviceName,
          platform: input.platform,
          appVersion: input.appVersion,
          osVersion: input.osVersion,
          metadata: {
            if (input.metadata != null) ...input.metadata!,
            'source': 'app_e2e_product_from_catalog_flow_catalog_retry',
          },
        ),
      );

      candidate = await _findCatalogCandidate(businessId: businessId);
    }

    if (candidate == null) {
      final diagnostics = await _catalogDiagnostics(
        businessId: businessId,
      );

      throw StateError(
        'No encontré un barcode de catálogo disponible para crear producto. '
        'Diagnóstico local: $diagnostics',
      );
    }

    final installationId = preflight.installationId;
    final appDeviceId = _extractAppDeviceId(preflight.manualSyncResult);

    if (appDeviceId == null) {
      throw StateError(
        'No se pudo resolver appDeviceId real después del preflight. '
        'Ejecuta primero sync manual controlado y revisa runtime_context.',
      );
    }

    final createResult =
        await _productFromMasterSyncService.createProductAndQueueSync(
      CreateProductFromMasterInput(
        businessId: businessId,
        branchId: branchId,
        profileId: input.profileId,
        appDeviceId: appDeviceId,
        deviceInstallationId: installationId,
        masterProduct: _masterProductFromCandidate(candidate),
        barcodeRecord: _barcodeRecordFromCandidate(candidate),
        salePrice: input.salePrice,
        purchasePrice: input.purchasePrice,
        clientSequenceStart: _safeClientSequenceStart(),
      ),
    );

    Map<String, dynamic>? postCreateSyncResult;
    var didRunManualSyncAfterCreate = false;

    if (input.runManualSyncAfterCreate) {
      final postSync = await _localFlowService.run(
        AppE2ELocalFlowInput(
          profileId: input.profileId,
          preferredBusinessId: businessId,
          preferredBranchId: branchId,
          isOnline: input.isOnline,
          lastSyncStatus: input.lastSyncStatus,
          runManualSync: true,
          deviceName: input.deviceName,
          platform: input.platform,
          appVersion: input.appVersion,
          osVersion: input.osVersion,
          metadata: {
            if (input.metadata != null) ...input.metadata!,
            'source': 'app_e2e_product_from_catalog_flow_post_create_sync',
            'created_product_id': createResult.createdProduct.productId,
            'created_master_product_id':
                createResult.createdProduct.masterProductId,
            'created_barcode_normalized':
                createResult.createdProduct.barcodeNormalized,
            'local_batch_id': createResult.outboxResult.localBatchId,
          },
        ),
      );

      didRunManualSyncAfterCreate = postSync.didRunManualSync;
      postCreateSyncResult = postSync.toJson();
    }

    return AppE2EProductFromCatalogFlowResult(
      installationId: installationId,
      businessId: businessId,
      branchId: branchId,
      profileId: input.profileId,
      appDeviceId: appDeviceId,
      catalogCandidate: candidate,
      creationResult: createResult.toJson(),
      didRunManualSyncAfterCreate: didRunManualSyncAfterCreate,
      postCreateSyncResult: postCreateSyncResult,
    );
  }

  Future<Map<String, dynamic>> _catalogDiagnostics({
    required String businessId,
  }) async {
    final masterColumns = await _tableColumns('local_master_products_catalog');
    final barcodeColumns = await _tableColumns('local_product_barcodes');
    final productColumns = await _tableColumns('products');

    return {
      'business_id': businessId,
      'local_master_products_catalog': {
        'columns': masterColumns.toList()..sort(),
        'total_rows': await _safeCount('local_master_products_catalog'),
        'rows_with_barcode': masterColumns.contains('barcode')
            ? await _safeCount(
                'local_master_products_catalog',
                where: "where barcode is not null and trim(barcode) <> ''",
              )
            : 'column_missing',
        'rows_with_barcode_normalized':
            masterColumns.contains('barcode_normalized')
                ? await _safeCount(
                    'local_master_products_catalog',
                    where:
                        "where barcode_normalized is not null and trim(barcode_normalized) <> ''",
                  )
                : 'column_missing',
        'sample': await _safeSample(
          tableName: 'local_master_products_catalog',
          preferredColumns: [
            'id',
            'name',
            'product_name',
            'barcode',
            'barcode_normalized',
            'brand',
            'status',
            'created_at',
            'updated_at',
          ],
        ),
      },
      'local_product_barcodes': {
        'columns': barcodeColumns.toList()..sort(),
        'total_rows': await _safeCount('local_product_barcodes'),
        'rows_with_master_product_id':
            barcodeColumns.contains('master_product_id')
                ? await _safeCount(
                    'local_product_barcodes',
                    where:
                        "where master_product_id is not null and trim(master_product_id) <> ''",
                  )
                : 'column_missing',
        'rows_with_barcode_normalized':
            barcodeColumns.contains('barcode_normalized')
                ? await _safeCount(
                    'local_product_barcodes',
                    where:
                        "where barcode_normalized is not null and trim(barcode_normalized) <> ''",
                  )
                : 'column_missing',
        'business_rows_for_current_business':
            barcodeColumns.contains('business_id')
                ? await _safeCount(
                    'local_product_barcodes',
                    where: 'where business_id = ?',
                    variables: [Variable<String>(businessId)],
                  )
                : 'column_missing',
        'sample': await _safeSample(
          tableName: 'local_product_barcodes',
          preferredColumns: [
            'id',
            'scope',
            'business_id',
            'product_id',
            'master_product_id',
            'barcode',
            'barcode_normalized',
            'barcode_type',
            'status',
            'source',
            'created_at',
            'updated_at',
          ],
        ),
      },
      'products': {
        'columns': productColumns.toList()..sort(),
        'rows_for_current_business': productColumns.contains('business_id')
            ? await _safeCount(
                'products',
                where: 'where business_id = ?',
                variables: [Variable<String>(businessId)],
              )
            : 'column_missing',
        'sample_for_current_business': productColumns.contains('business_id')
            ? await _safeSample(
                tableName: 'products',
                preferredColumns: [
                  'id',
                  'business_id',
                  'name',
                  'barcode',
                  'master_product_id',
                  'sync_status',
                  'local_status',
                  'created_at',
                  'updated_at',
                ],
                where: 'where business_id = ?',
                variables: [Variable<String>(businessId)],
              )
            : 'column_missing',
      },
    };
  }

  Future<Set<String>> _tableColumns(String tableName) async {
    try {
      final rows = await _db
          .customSelect(
            'pragma table_info($tableName)',
          )
          .get();

      return rows
          .map((row) => row.data['name']?.toString())
          .whereType<String>()
          .toSet();
    } catch (error) {
      return <String>{'__error__: $error'};
    }
  }

  Future<Object> _safeCount(
    String tableName, {
    String? where,
    List<Variable> variables = const [],
  }) async {
    try {
      final rows = await _db
          .customSelect(
            'select count(*) as total from $tableName ${where ?? ''}',
            variables: variables,
          )
          .get();

      if (rows.isEmpty) {
        return 0;
      }

      return rows.first.data['total'] ?? 0;
    } catch (error) {
      return 'error: $error';
    }
  }

  Future<Object> _safeSample({
    required String tableName,
    required List<String> preferredColumns,
    String? where,
    List<Variable> variables = const [],
  }) async {
    try {
      final columns = await _tableColumns(tableName);
      final selectedColumns =
          preferredColumns.where((column) => columns.contains(column)).toList();

      final projection = selectedColumns.isEmpty
          ? '*'
          : selectedColumns.map((column) => '$column as $column').join(', ');

      final rows = await _db
          .customSelect(
            'select $projection from $tableName ${where ?? ''} limit 5',
            variables: variables,
          )
          .get();

      return rows.map((row) => row.data).toList();
    } catch (error) {
      return 'error: $error';
    }
  }

  Future<Map<String, dynamic>?> _findCatalogCandidate({
    required String businessId,
  }) async {
    final result = await _queryCandidate(
      businessId: businessId,
      preferGlobalOnly: true,
    );

    if (result != null) {
      return result;
    }

    return _queryCandidate(
      businessId: businessId,
      preferGlobalOnly: false,
    );
  }

  Future<Map<String, dynamic>?> _queryCandidate({
    required String businessId,
    required bool preferGlobalOnly,
  }) async {
    final scopeFilter = preferGlobalOnly
        ? '''
          and (
            pb.business_id is null
            or trim(pb.business_id) = ''
          )
        '''
        : '';

    final rows = await _db.customSelect(
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
        where pb.master_product_id is not null
          and trim(pb.master_product_id) <> ''
          and pb.barcode_normalized is not null
          and trim(pb.barcode_normalized) <> ''
          $scopeFilter
          and not exists (
            select 1
            from local_product_barcodes existing
            where existing.business_id = ?
              and existing.barcode_normalized = pb.barcode_normalized
              and lower(coalesce(existing.scope, '')) = 'business'
              and coalesce(existing.deleted_at, '') = ''
          )
        order by
          case
            when pb.business_id is null or trim(pb.business_id) = '' then 0
            else 1
          end,
          coalesce(pb.updated_at, pb.created_at) desc
        limit 1
      ''',
      variables: [
        Variable<String>(businessId),
      ],
    ).get();

    if (rows.isEmpty) {
      return null;
    }

    return rows.first.data;
  }

  Map<String, dynamic> _masterProductFromCandidate(
    Map<String, dynamic> candidate,
  ) {
    return {
      'id': candidate['master_product_id'],
      'name': candidate['master_product_name'],
      'product_name': candidate['master_product_product_name'],
      'brand': candidate['master_product_brand'],
      'manufacturer': candidate['master_product_manufacturer'],
      'category_name': candidate['master_product_category_name'],
      'subcategory_name': candidate['master_product_subcategory_name'],
      'package_size': candidate['master_product_package_size'],
      'package_unit': candidate['master_product_package_unit'],
      'unit_type': candidate['master_product_unit_type'],
      'image_thumb_url': candidate['master_product_image_thumb_url'],
      'image_hash': candidate['master_product_image_hash'],
      'confidence_score': candidate['master_product_confidence_score'],
      'barcode': candidate['barcode_value'],
      'barcode_normalized': candidate['barcode_normalized'],
    };
  }

  Map<String, dynamic> _barcodeRecordFromCandidate(
    Map<String, dynamic> candidate,
  ) {
    return {
      'id': candidate['barcode_id'],
      'scope': candidate['barcode_scope'],
      'business_id': candidate['barcode_business_id'],
      'product_id': candidate['barcode_product_id'],
      'master_product_id': candidate['barcode_master_product_id'],
      'barcode': candidate['barcode_value'],
      'barcode_normalized': candidate['barcode_normalized'],
      'barcode_type': candidate['barcode_type'],
      'is_primary': candidate['barcode_is_primary'],
      'status': candidate['barcode_status'],
      'source': candidate['barcode_source'],
      'confidence_score': candidate['barcode_confidence_score'],
    };
  }

  int _safeClientSequenceStart() {
    final value = DateTime.now().microsecondsSinceEpoch.remainder(2000000000);

    if (value < 1) {
      return 1;
    }

    return value;
  }

  String? _extractAppDeviceId(Map<String, dynamic>? manualSyncResult) {
    final runtimeContext = manualSyncResult?['manual_sync_result']
        ?['runtime_context'] as Map<String, dynamic>?;

    return _string(runtimeContext?['app_device_id']) ??
        _string(runtimeContext?['id']);
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
}
