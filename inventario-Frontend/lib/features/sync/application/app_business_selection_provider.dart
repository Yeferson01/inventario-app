import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_business_selection_models.dart';
import 'local_sync_outbox_providers.dart';

final appAvailableBusinessContextsProvider =
    FutureProvider.family<List<AppBusinessSelectionOption>, String>(
  (ref, profileId) async {
    final service = ref.watch(appBusinessSelectionServiceProvider);

    return service.getAvailableContexts(profileId: profileId);
  },
);

final appSelectedBusinessOptionProvider =
    FutureProvider.family<AppBusinessSelectionOption?, String>(
  (ref, profileId) async {
    final service = ref.watch(appBusinessSelectionServiceProvider);

    return service.getSelectedOption(profileId: profileId);
  },
);
