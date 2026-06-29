class RemoteProductStockBalance {
  const RemoteProductStockBalance({
    required this.businessId,
    required this.branchId,
    required this.productId,
    required this.quantityOnHand,
    required this.quantityReserved,
    required this.quantityAvailable,
    required this.averageCost,
    required this.lastMovementAt,
    required this.remoteUpdatedAt,
  });

  final String businessId;
  final String branchId;
  final String productId;
  final int quantityOnHand;
  final int quantityReserved;
  final int quantityAvailable;
  final double? averageCost;
  final DateTime? lastMovementAt;
  final DateTime? remoteUpdatedAt;

  String get localId => '$businessId:$branchId:$productId';

  factory RemoteProductStockBalance.fromJson(Map<String, dynamic> json) {
    return RemoteProductStockBalance(
      businessId: _requiredString(json, 'business_id'),
      branchId: _requiredString(json, 'branch_id'),
      productId: _requiredString(json, 'product_id'),
      quantityOnHand: _int(json['quantity_on_hand']),
      quantityReserved: _int(json['quantity_reserved']),
      quantityAvailable: _int(json['quantity_available']),
      averageCost: _double(json['average_cost']),
      lastMovementAt: _date(json['last_movement_at']),
      remoteUpdatedAt: _date(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      'product_id': productId,
      'quantity_on_hand': quantityOnHand,
      'quantity_reserved': quantityReserved,
      'quantity_available': quantityAvailable,
      'average_cost': averageCost,
      'last_movement_at': lastMovementAt?.toIso8601String(),
      'updated_at': remoteUpdatedAt?.toIso8601String(),
    };
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];

    if (value == null || value.toString().trim().isEmpty) {
      throw ArgumentError('Campo requerido ausente: $key');
    }

    return value.toString();
  }

  static int _int(Object? value) {
    if (value == null) {
      return 0;
    }

    if (value is int) {
      return value;
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value.toString()) ?? 0;
  }

  static double? _double(Object? value) {
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

  static DateTime? _date(Object? value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value.toUtc();
    }

    return DateTime.tryParse(value.toString())?.toUtc();
  }
}

class ProductStockBalancePullResult {
  const ProductStockBalancePullResult({
    required this.businessId,
    required this.branchId,
    required this.remoteCount,
    required this.localUpserted,
    required this.pulledAt,
  });

  final String businessId;
  final String branchId;
  final int remoteCount;
  final int localUpserted;
  final DateTime pulledAt;

  Map<String, dynamic> toJson() {
    return {
      'business_id': businessId,
      'branch_id': branchId,
      'remote_count': remoteCount,
      'local_upserted': localUpserted,
      'pulled_at': pulledAt.toIso8601String(),
    };
  }
}
