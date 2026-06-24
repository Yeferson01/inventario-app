class BarcodeNormalizer {
  BarcodeNormalizer._();

  static String normalize(String input) {
    return input.trim().toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  }

  static bool isEmptyAfterNormalize(String input) {
    return normalize(input).isEmpty;
  }

  static bool looksLikeGtin(String input) {
    final normalized = normalize(input);

    return RegExp(r'^\d{8}$').hasMatch(normalized) ||
        RegExp(r'^\d{12}$').hasMatch(normalized) ||
        RegExp(r'^\d{13}$').hasMatch(normalized) ||
        RegExp(r'^\d{14}$').hasMatch(normalized);
  }

  static String inferBarcodeType(String input) {
    final normalized = normalize(input);

    if (RegExp(r'^\d{13}$').hasMatch(normalized)) {
      return 'ean13';
    }

    if (RegExp(r'^\d{8}$').hasMatch(normalized)) {
      return 'ean8';
    }

    if (RegExp(r'^\d{12}$').hasMatch(normalized)) {
      return 'upc';
    }

    if (RegExp(r'^\d{14}$').hasMatch(normalized)) {
      return 'gtin';
    }

    if (normalized.startsWith('LOCAL') || normalized.startsWith('SKU')) {
      return 'local_sku';
    }

    return 'unknown';
  }
}
