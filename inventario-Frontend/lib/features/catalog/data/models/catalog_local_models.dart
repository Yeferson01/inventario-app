class LocalBarcodeLookupResult {
  const LocalBarcodeLookupResult({
    required this.found,
    required this.matchType,
    required this.suggestedAction,
    required this.normalizedBarcode,
    this.barcodeRecord,
    this.localProduct,
    this.masterProduct,
  });

  final bool found;
  final String matchType;
  final String suggestedAction;
  final String normalizedBarcode;
  final Map<String, dynamic>? barcodeRecord;
  final Map<String, dynamic>? localProduct;
  final Map<String, dynamic>? masterProduct;

  factory LocalBarcodeLookupResult.none(String normalizedBarcode) {
    return LocalBarcodeLookupResult(
      found: false,
      matchType: 'none',
      suggestedAction: 'create_manual_product',
      normalizedBarcode: normalizedBarcode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'found': found,
      'match_type': matchType,
      'suggested_action': suggestedAction,
      'normalized_barcode': normalizedBarcode,
      'barcode_record': barcodeRecord,
      'local_product': localProduct,
      'master_product': masterProduct,
    };
  }
}

class CatalogDeltaApplyResult {
  const CatalogDeltaApplyResult({
    required this.masterProductsUpserted,
    required this.productBarcodesUpserted,
    required this.ignoredRecords,
    this.tombstonesApplied = 0,
    this.staleRecordsIgnored = 0,
    this.dirtyRecordsSkipped = 0,
  });

  final int masterProductsUpserted;
  final int productBarcodesUpserted;
  final int ignoredRecords;
  final int tombstonesApplied;
  final int staleRecordsIgnored;
  final int dirtyRecordsSkipped;

  int get totalApplied => masterProductsUpserted + productBarcodesUpserted;

  Map<String, dynamic> toJson() {
    return {
      'master_products_upserted': masterProductsUpserted,
      'product_barcodes_upserted': productBarcodesUpserted,
      'ignored_records': ignoredRecords,
      'tombstones_applied': tombstonesApplied,
      'stale_records_ignored': staleRecordsIgnored,
      'dirty_records_skipped': dirtyRecordsSkipped,
      'total_applied': totalApplied,
    };
  }
}
