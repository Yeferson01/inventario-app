import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/app_business_selection_provider.dart';
import '../screens/business_context_selection_screen.dart';

class BusinessContextRequiredGate extends ConsumerWidget {
  const BusinessContextRequiredGate({
    required this.profileId,
    required this.child,
    this.loading,
    super.key,
  });

  final String profileId;
  final Widget child;
  final Widget? loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedAsync = ref.watch(
      appSelectedBusinessOptionProvider(profileId),
    );

    return selectedAsync.when(
      data: (selected) {
        if (selected == null) {
          return BusinessContextSelectionScreen(
            profileId: profileId,
            onContextSelected: () {
              ref.invalidate(appSelectedBusinessOptionProvider(profileId));
              ref.invalidate(appAvailableBusinessContextsProvider(profileId));
            },
          );
        }

        return child;
      },
      loading: () {
        return loading ??
            const Scaffold(
              body: Center(
                child: CircularProgressIndicator(),
              ),
            );
      },
      error: (error, _) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error cargando contexto de negocio: $error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}
