import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/application/operational_bootstrap_providers.dart';

class InventoryCostVisibilityKey {
  const InventoryCostVisibilityKey({
    required this.profileId,
    required this.businessId,
    required this.branchId,
  });

  final String profileId;
  final String businessId;
  final String branchId;

  @override
  bool operator ==(Object other) {
    return other is InventoryCostVisibilityKey &&
        other.profileId == profileId &&
        other.businessId == businessId &&
        other.branchId == branchId;
  }

  @override
  int get hashCode => Object.hash(profileId, businessId, branchId);
}

final inventoryCostVisibilityProvider =
    StreamProvider.family<bool, InventoryCostVisibilityKey>((ref, key) {
  return ref
      .watch(authorizedOperationalContextLocalDaoProvider)
      .watchContextRecord(
        profileId: key.profileId,
        businessId: key.businessId,
        branchId: key.branchId,
      )
      .map(
        (context) =>
            context?.isActive == true &&
            context!.effectivePermissions.contains('inventory.view_costs'),
      );
});
