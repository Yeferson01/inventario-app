import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_business_selection_provider.dart';
import 'local_sync_outbox_providers.dart';

class AppBusinessContextActions {
  const AppBusinessContextActions(this._ref);

  final Ref _ref;

  Future<void> clearSelectedBusinessContext({
    required String profileId,
  }) async {
    final service = _ref.read(appBusinessSelectionServiceProvider);

    await service.clearSelectedContext(profileId: profileId);

    _ref.invalidate(appSelectedBusinessOptionProvider(profileId));
    _ref.invalidate(appAvailableBusinessContextsProvider(profileId));
  }
}

final appBusinessContextActionsProvider =
    Provider<AppBusinessContextActions>((ref) {
  return AppBusinessContextActions(ref);
});
