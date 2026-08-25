import '../../../core/utils/barcode_normalizer.dart';
import '../data/models/catalog_local_models.dart';
import '../domain/entities/barcode_scan_result.dart';

typedef CatalogLocalLookupFn = Future<LocalBarcodeLookupResult> Function({
  required String businessId,
  required String barcode,
  required bool allowMasterMatch,
});

class CatalogBarcodeLookupService {
  CatalogBarcodeLookupService({
    required CatalogLocalLookupFn lookupByBarcode,
  }) : _lookupByBarcode = lookupByBarcode;

  final CatalogLocalLookupFn _lookupByBarcode;

  Future<BarcodeScanResult> scanBarcode({
    required String businessId,
    required String rawBarcode,
    bool allowMasterMatch = true,
  }) async {
    final normalizedBarcode = BarcodeNormalizer.normalize(rawBarcode);

    if (normalizedBarcode.isEmpty) {
      return BarcodeScanResult(
        rawBarcode: rawBarcode,
        normalizedBarcode: normalizedBarcode,
        found: false,
        matchType: BarcodeScanMatchType.invalid,
        suggestedAction: BarcodeScanSuggestedAction.rejectInvalidBarcode,
        message:
            'El código escaneado está vacío o no contiene caracteres válidos.',
      );
    }

    final localLookup = await _lookupByBarcode(
      businessId: businessId,
      barcode: normalizedBarcode,
      allowMasterMatch: allowMasterMatch,
    );

    if (!localLookup.found) {
      return BarcodeScanResult(
        rawBarcode: rawBarcode,
        normalizedBarcode: normalizedBarcode,
        found: false,
        matchType: BarcodeScanMatchType.none,
        suggestedAction: BarcodeScanSuggestedAction.createManualProduct,
        message:
            'No se encontró el código en el catálogo local. Crear producto manualmente.',
      );
    }

    if (localLookup.matchType == 'business') {
      return BarcodeScanResult(
        rawBarcode: rawBarcode,
        normalizedBarcode: normalizedBarcode,
        found: true,
        matchType: BarcodeScanMatchType.business,
        suggestedAction: BarcodeScanSuggestedAction.useLocalProduct,
        message: 'Producto encontrado en el catálogo local del negocio.',
        barcodeRecord: localLookup.barcodeRecord,
        localProduct: localLookup.localProduct,
        masterProduct: localLookup.masterProduct,
      );
    }

    if (localLookup.matchType == 'global') {
      return BarcodeScanResult(
        rawBarcode: rawBarcode,
        normalizedBarcode: normalizedBarcode,
        found: true,
        matchType: BarcodeScanMatchType.global,
        suggestedAction:
            BarcodeScanSuggestedAction.createLocalProductFromMaster,
        message:
            'Producto encontrado en el catálogo maestro local. Crear producto local desde master.',
        barcodeRecord: localLookup.barcodeRecord,
        masterProduct: localLookup.masterProduct,
      );
    }

    return BarcodeScanResult(
      rawBarcode: rawBarcode,
      normalizedBarcode: normalizedBarcode,
      found: false,
      matchType: BarcodeScanMatchType.none,
      suggestedAction: BarcodeScanSuggestedAction.createManualProduct,
      message: 'Resultado local no reconocido. Crear producto manualmente.',
      barcodeRecord: localLookup.barcodeRecord,
      localProduct: localLookup.localProduct,
      masterProduct: localLookup.masterProduct,
    );
  }
}
