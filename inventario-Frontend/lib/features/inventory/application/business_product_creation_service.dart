import '../../../core/utils/barcode_normalizer.dart';
import '../../catalog/application/catalog_barcode_lookup_service.dart';
import '../../catalog/domain/entities/barcode_scan_result.dart';
import 'business_product_creation_models.dart';
import 'inventory_product_creation_models.dart';
import 'inventory_product_from_master_sync_service.dart';

class BusinessProductCreationService {
  BusinessProductCreationService({
    required CatalogBarcodeLookupService barcodeLookupService,
    required InventoryProductFromMasterSyncService productSyncService,
  })  : _barcodeLookupService = barcodeLookupService,
        _productSyncService = productSyncService;

  final CatalogBarcodeLookupService _barcodeLookupService;
  final InventoryProductFromMasterSyncService _productSyncService;

  Future<BusinessProductMinimumStockUpdateResult> updateMinimumStock(
    BusinessProductMinimumStockUpdateInput input,
  ) async {
    final contextFailure = _validateContext(input.context);
    if (contextFailure != null || input.productId.trim().isEmpty) {
      return const BusinessProductMinimumStockUpdateResult(
        outcome: BusinessProductMinimumStockUpdateOutcome.validationFailure,
        message: 'El contexto y el producto son requeridos.',
      );
    }
    if (!input.context.hasPermission('products.update')) {
      return const BusinessProductMinimumStockUpdateResult(
        outcome: BusinessProductMinimumStockUpdateOutcome.permissionDenied,
        message: 'Editar el stock mínimo requiere products.update.',
      );
    }
    if (input.minimumStock < 0) {
      return const BusinessProductMinimumStockUpdateResult(
        outcome: BusinessProductMinimumStockUpdateOutcome.validationFailure,
        message: 'El stock mínimo no puede ser negativo.',
      );
    }

    try {
      final result = await _productSyncService.updateMinimumStockAndQueueSync(
        businessId: input.context.businessId,
        branchId: input.context.branchId,
        profileId: input.context.profileId,
        appDeviceId: input.context.appDeviceId,
        deviceInstallationId: input.context.deviceInstallationId,
        productId: input.productId.trim(),
        minimumStock: input.minimumStock,
      );

      if (result == null) {
        return const BusinessProductMinimumStockUpdateResult(
          outcome: BusinessProductMinimumStockUpdateOutcome.notFound,
          message: 'El producto no existe en el negocio seleccionado.',
        );
      }

      return BusinessProductMinimumStockUpdateResult(
        outcome: result.changed
            ? BusinessProductMinimumStockUpdateOutcome.updated
            : BusinessProductMinimumStockUpdateOutcome.unchanged,
        message: result.changed
            ? 'Stock mínimo actualizado localmente.'
            : 'El stock mínimo ya tenía ese valor.',
        minimumStock: result.minimumStock,
        outboxMutationCount: result.outboxResult?.mutationCount ?? 0,
      );
    } catch (error) {
      return BusinessProductMinimumStockUpdateResult(
        outcome:
            BusinessProductMinimumStockUpdateOutcome.localPersistenceFailure,
        message: 'No fue posible actualizar el stock mínimo localmente.',
        cause: error,
      );
    }
  }

  Future<BusinessProductCodeResolution> resolveCode({
    required BusinessProductCreationContext context,
    String? code,
  }) {
    return _resolveCode(context: context, code: code);
  }

  Future<BusinessProductCreationResult> createOrUse({
    required BusinessProductCreationContext context,
    required BusinessProductOwnedFields fields,
    String? code,
    int? clientSequenceStart,
  }) async {
    final contextFailure = _validateContext(context);
    if (contextFailure != null) {
      return contextFailure;
    }

    final resolution = await _resolveCode(context: context, code: code);
    if (resolution.isExisting) {
      return _existingResult(resolution);
    }
    if (resolution.type == BusinessProductCodeResolutionType.invalid) {
      return BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.validationFailure,
        message: resolution.message,
      );
    }
    if (!context.hasPermission('products.create')) {
      return const BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.permissionDenied,
        message: 'Crear productos requiere el permiso products.create.',
      );
    }

    final validationFailure = _validateFields(
      fields,
      requiresManualName: !resolution.hasMasterSuggestion,
    );
    if (validationFailure != null) {
      return validationFailure;
    }

    final sequence = clientSequenceStart ??
        DateTime.now().toUtc().microsecondsSinceEpoch.remainder(2000000000);

    try {
      if (resolution.hasMasterSuggestion) {
        final masterProduct = resolution.masterProduct;
        final barcodeRecord = resolution.barcodeRecord;
        if (masterProduct == null || barcodeRecord == null) {
          return const BusinessProductCreationResult(
            outcome: BusinessProductCreationOutcome.validationFailure,
            message: 'La sugerencia master local está incompleta.',
          );
        }

        final syncResult = await _productSyncService.createProductAndQueueSync(
          CreateProductFromMasterInput(
            businessId: context.businessId,
            branchId: context.branchId,
            profileId: context.profileId,
            appDeviceId: context.appDeviceId,
            deviceInstallationId: context.deviceInstallationId,
            masterProduct: masterProduct,
            barcodeRecord: barcodeRecord,
            purchasePrice: fields.purchasePrice,
            salePrice: fields.salePrice,
            categoryId: fields.categoryId,
            nameOverride: fields.name,
            description: fields.description,
            minimumStock: fields.minimumStock,
            unit: fields.unit,
            clientSequenceStart: sequence,
          ),
        );
        final created = syncResult.createdProduct;
        return BusinessProductCreationResult(
          outcome: BusinessProductCreationOutcome.createdFromMaster,
          message: 'Producto creado localmente desde el catálogo maestro.',
          productId: created.productId,
          product: created.productPayload,
          masterProductId: created.masterProductId,
          barcode: created.barcode,
          outboxMutationCount: syncResult.outboxResult.mutationCount,
        );
      }

      final syncResult =
          await _productSyncService.createManualProductAndQueueSync(
        CreateManualLocalProductInput(
          businessId: context.businessId,
          branchId: context.branchId,
          profileId: context.profileId,
          appDeviceId: context.appDeviceId,
          deviceInstallationId: context.deviceInstallationId,
          name: fields.name!.trim(),
          barcode: resolution.rawCode,
          purchasePrice: fields.purchasePrice,
          salePrice: fields.salePrice,
          categoryId: fields.categoryId,
          description: fields.description,
          minimumStock: fields.minimumStock,
          unit: fields.unit,
          clientSequenceStart: sequence,
        ),
      );
      final created = syncResult.createdProduct;
      return BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.createdManual,
        message: 'Producto manual creado localmente.',
        productId: created.productId,
        product: created.productPayload,
        barcode: created.barcode,
        outboxMutationCount: syncResult.outboxResult.mutationCount,
      );
    } on ArgumentError catch (error) {
      return BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.validationFailure,
        message: error.message?.toString() ??
            'Los datos del producto no son válidos.',
        cause: error,
      );
    } catch (error) {
      if (_isDuplicateBusinessCode(error) &&
          resolution.rawCode?.trim().isNotEmpty == true) {
        final existing = await _resolveCode(
          context: context,
          code: resolution.rawCode,
          businessOnly: true,
        );
        if (existing.isExisting) {
          return _existingResult(existing);
        }
        return BusinessProductCreationResult(
          outcome: BusinessProductCreationOutcome.duplicateCode,
          message: 'El código ya pertenece a otro producto activo del negocio.',
          barcode: resolution.rawCode,
          cause: error,
        );
      }
      return BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.localPersistenceFailure,
        message:
            'No se pudo guardar localmente el producto y su sincronización pendiente.',
        cause: error,
      );
    }
  }

  Future<BusinessProductCreationResult> linkExistingProductToMaster({
    required BusinessProductCreationContext context,
    required String productId,
    required String masterProductId,
    Map<String, dynamic>? barcodeRecord,
    int? clientSequenceStart,
  }) async {
    final contextFailure = _validateContext(context);
    if (contextFailure != null) {
      return contextFailure;
    }
    if (!context.hasPermission('products.update')) {
      return const BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.permissionDenied,
        message: 'Vincular productos requiere el permiso products.update.',
      );
    }

    try {
      final syncResult =
          await _productSyncService.linkProductToMasterAndQueueSync(
        LinkLocalProductToMasterInput(
          businessId: context.businessId,
          branchId: context.branchId,
          profileId: context.profileId,
          appDeviceId: context.appDeviceId,
          deviceInstallationId: context.deviceInstallationId,
          productId: productId,
          masterProductId: masterProductId,
          barcodeRecord: barcodeRecord,
          clientSequenceStart: clientSequenceStart ??
              DateTime.now()
                  .toUtc()
                  .microsecondsSinceEpoch
                  .remainder(2000000000),
        ),
      );
      final linked = syncResult.linkedProduct;
      return BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.linkedExistingProduct,
        message: 'Producto local vinculado al catálogo maestro.',
        productId: linked.productId,
        product: linked.productPayload,
        masterProductId: linked.masterProductId,
        barcode: linked.businessBarcodePayload?['barcode']?.toString(),
        outboxMutationCount: syncResult.outboxResult.mutationCount,
      );
    } on ArgumentError catch (error) {
      return BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.validationFailure,
        message:
            error.message?.toString() ?? 'El vínculo solicitado no es válido.',
        cause: error,
      );
    } on StateError catch (error) {
      return BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.validationFailure,
        message: error.message,
        cause: error,
      );
    } catch (error) {
      return BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.localPersistenceFailure,
        message:
            'No se pudo guardar localmente el vínculo con el catálogo maestro.',
        cause: error,
      );
    }
  }

  Future<BusinessProductCodeResolution> _resolveCode({
    required BusinessProductCreationContext context,
    String? code,
    bool businessOnly = false,
  }) async {
    final rawCode = code?.trim();
    if (rawCode == null || rawCode.isEmpty) {
      return const BusinessProductCodeResolution(
        type: BusinessProductCodeResolutionType.noCode,
        message: 'Crear producto manual sin código.',
      );
    }

    final businessType = BarcodeNormalizer.inferBusinessBarcodeType(rawCode);
    final isInternal = BarcodeNormalizer.isInternalBusinessType(businessType);
    final scan = await _barcodeLookupService.scanBarcode(
      businessId: context.businessId,
      rawBarcode: rawCode,
      allowMasterMatch: !businessOnly && !isInternal,
    );

    return switch (scan.matchType) {
      BarcodeScanMatchType.invalid => BusinessProductCodeResolution(
          type: BusinessProductCodeResolutionType.invalid,
          message: scan.message,
          rawCode: rawCode,
          normalizedCode: scan.normalizedBarcode,
        ),
      BarcodeScanMatchType.business => BusinessProductCodeResolution(
          type: BusinessProductCodeResolutionType.existingBusinessProduct,
          message: scan.message,
          rawCode: rawCode,
          normalizedCode: scan.normalizedBarcode,
          localProduct: scan.localProduct,
          masterProduct: scan.masterProduct,
          barcodeRecord: scan.barcodeRecord,
        ),
      BarcodeScanMatchType.global => BusinessProductCodeResolution(
          type: BusinessProductCodeResolutionType.masterSuggestion,
          message: scan.message,
          rawCode: rawCode,
          normalizedCode: scan.normalizedBarcode,
          masterProduct: scan.masterProduct,
          barcodeRecord: scan.barcodeRecord,
        ),
      BarcodeScanMatchType.none => BusinessProductCodeResolution(
          type: BusinessProductCodeResolutionType.manualSuggestion,
          message: scan.message,
          rawCode: rawCode,
          normalizedCode: scan.normalizedBarcode,
        ),
    };
  }

  BusinessProductCreationResult? _validateContext(
    BusinessProductCreationContext context,
  ) {
    if (context.businessId.trim().isEmpty ||
        context.branchId.trim().isEmpty ||
        context.profileId.trim().isEmpty ||
        context.deviceInstallationId.trim().isEmpty) {
      return const BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.validationFailure,
        message:
            'El contexto operacional para crear el producto está incompleto.',
      );
    }
    return null;
  }

  BusinessProductCreationResult? _validateFields(
    BusinessProductOwnedFields fields, {
    required bool requiresManualName,
  }) {
    if (requiresManualName && (fields.name?.trim().length ?? 0) < 2) {
      return const BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.validationFailure,
        message: 'El nombre del producto es requerido.',
      );
    }
    if (fields.purchasePrice < 0 || fields.salePrice < 0) {
      return const BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.validationFailure,
        message: 'Los precios no pueden ser negativos.',
      );
    }
    if (fields.minimumStock < 0) {
      return const BusinessProductCreationResult(
        outcome: BusinessProductCreationOutcome.validationFailure,
        message: 'El stock mínimo no puede ser negativo.',
      );
    }
    return null;
  }

  BusinessProductCreationResult _existingResult(
    BusinessProductCodeResolution resolution,
  ) {
    final product = resolution.localProduct;
    return BusinessProductCreationResult(
      outcome: BusinessProductCreationOutcome.existing,
      message: 'Se usará el producto existente del negocio.',
      productId: product?['id']?.toString(),
      product: product,
      masterProductId: resolution.masterProduct?['id']?.toString(),
      barcode: resolution.barcodeRecord?['barcode']?.toString(),
    );
  }

  bool _isDuplicateBusinessCode(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('active business product code already exists') ||
        message.contains('ux_product_barcodes_business_code_active') ||
        (message.contains('unique constraint failed') &&
            message.contains('barcode_normalized'));
  }
}
