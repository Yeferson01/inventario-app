enum BusinessProductCodeResolutionType {
  noCode,
  invalid,
  existingBusinessProduct,
  masterSuggestion,
  manualSuggestion,
}

class BusinessProductCreationContext {
  const BusinessProductCreationContext({
    required this.businessId,
    required this.branchId,
    required this.profileId,
    required this.deviceInstallationId,
    required this.effectivePermissions,
    this.appDeviceId,
  });

  final String businessId;
  final String branchId;
  final String profileId;
  final String? appDeviceId;
  final String deviceInstallationId;
  final Set<String> effectivePermissions;

  bool hasPermission(String permission) {
    return effectivePermissions.contains(permission);
  }
}

class BusinessProductCodeResolution {
  const BusinessProductCodeResolution({
    required this.type,
    required this.message,
    this.rawCode,
    this.normalizedCode,
    this.localProduct,
    this.masterProduct,
    this.barcodeRecord,
  });

  final BusinessProductCodeResolutionType type;
  final String message;
  final String? rawCode;
  final String? normalizedCode;
  final Map<String, dynamic>? localProduct;
  final Map<String, dynamic>? masterProduct;
  final Map<String, dynamic>? barcodeRecord;

  bool get isExisting =>
      type == BusinessProductCodeResolutionType.existingBusinessProduct;

  bool get hasMasterSuggestion =>
      type == BusinessProductCodeResolutionType.masterSuggestion;
}

class BusinessProductOwnedFields {
  const BusinessProductOwnedFields({
    required this.purchasePrice,
    required this.salePrice,
    this.name,
    this.categoryId,
    this.description,
    this.minimumStock = 0,
    this.unit,
  });

  final String? name;
  final double purchasePrice;
  final double salePrice;
  final String? categoryId;
  final String? description;
  final int minimumStock;
  final String? unit;
}

enum BusinessProductCreationOutcome {
  existing,
  createdFromMaster,
  createdManual,
  linkedExistingProduct,
  validationFailure,
  duplicateCode,
  permissionDenied,
  localPersistenceFailure,
}

class BusinessProductCreationResult {
  const BusinessProductCreationResult({
    required this.outcome,
    required this.message,
    this.productId,
    this.product,
    this.masterProductId,
    this.barcode,
    this.outboxMutationCount = 0,
    this.cause,
  });

  final BusinessProductCreationOutcome outcome;
  final String message;
  final String? productId;
  final Map<String, dynamic>? product;
  final String? masterProductId;
  final String? barcode;
  final int outboxMutationCount;

  /// Kept for diagnostics/tests. Presentation must use [message], not this raw
  /// persistence error.
  final Object? cause;

  bool get succeeded {
    return outcome == BusinessProductCreationOutcome.existing ||
        outcome == BusinessProductCreationOutcome.createdFromMaster ||
        outcome == BusinessProductCreationOutcome.createdManual ||
        outcome == BusinessProductCreationOutcome.linkedExistingProduct;
  }

  bool get created {
    return outcome == BusinessProductCreationOutcome.createdFromMaster ||
        outcome == BusinessProductCreationOutcome.createdManual;
  }
}
