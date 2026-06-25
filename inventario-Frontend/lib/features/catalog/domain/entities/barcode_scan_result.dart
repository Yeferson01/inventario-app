enum BarcodeScanMatchType {
  invalid,
  business,
  global,
  none,
}

extension BarcodeScanMatchTypeCode on BarcodeScanMatchType {
  String get code {
    switch (this) {
      case BarcodeScanMatchType.invalid:
        return 'invalid';
      case BarcodeScanMatchType.business:
        return 'business';
      case BarcodeScanMatchType.global:
        return 'global';
      case BarcodeScanMatchType.none:
        return 'none';
    }
  }
}

enum BarcodeScanSuggestedAction {
  rejectInvalidBarcode,
  useLocalProduct,
  createLocalProductFromMaster,
  createManualProduct,
}

extension BarcodeScanSuggestedActionCode on BarcodeScanSuggestedAction {
  String get code {
    switch (this) {
      case BarcodeScanSuggestedAction.rejectInvalidBarcode:
        return 'reject_invalid_barcode';
      case BarcodeScanSuggestedAction.useLocalProduct:
        return 'use_local_product';
      case BarcodeScanSuggestedAction.createLocalProductFromMaster:
        return 'create_local_product_from_master';
      case BarcodeScanSuggestedAction.createManualProduct:
        return 'create_manual_product';
    }
  }
}

class BarcodeScanResult {
  const BarcodeScanResult({
    required this.rawBarcode,
    required this.normalizedBarcode,
    required this.found,
    required this.matchType,
    required this.suggestedAction,
    required this.message,
    this.barcodeRecord,
    this.localProduct,
    this.masterProduct,
  });

  final String rawBarcode;
  final String normalizedBarcode;
  final bool found;
  final BarcodeScanMatchType matchType;
  final BarcodeScanSuggestedAction suggestedAction;
  final String message;
  final Map<String, dynamic>? barcodeRecord;
  final Map<String, dynamic>? localProduct;
  final Map<String, dynamic>? masterProduct;

  bool get isInvalid => matchType == BarcodeScanMatchType.invalid;

  bool get canUseImmediately {
    return matchType == BarcodeScanMatchType.business && localProduct != null;
  }

  bool get canCreateFromMaster {
    return matchType == BarcodeScanMatchType.global && masterProduct != null;
  }

  bool get requiresManualCreation {
    return matchType == BarcodeScanMatchType.none;
  }

  Map<String, dynamic> toJson() {
    return {
      'raw_barcode': rawBarcode,
      'normalized_barcode': normalizedBarcode,
      'found': found,
      'match_type': matchType.code,
      'suggested_action': suggestedAction.code,
      'message': message,
      'barcode_record': barcodeRecord,
      'local_product': localProduct,
      'master_product': masterProduct,
    };
  }
}
