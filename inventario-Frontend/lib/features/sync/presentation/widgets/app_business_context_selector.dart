import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/app_business_selection_models.dart';
import '../../application/app_business_selection_provider.dart';
import '../../application/local_sync_outbox_providers.dart';

class AppBusinessContextSelector extends ConsumerWidget {
  const AppBusinessContextSelector({
    required this.profileId,
    this.onSelected,
    super.key,
  });

  final String profileId;
  final ValueChanged<AppBusinessSelectionResult>? onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final optionsAsync = ref.watch(
      appAvailableBusinessContextsProvider(profileId),
    );

    final selectedAsync = ref.watch(
      appSelectedBusinessOptionProvider(profileId),
    );

    return optionsAsync.when(
      data: (options) {
        if (options.isEmpty) {
          return const Text('No tienes negocios disponibles.');
        }

        final selected = selectedAsync.when(
          data: (value) => value,
          loading: () => null,
          error: (_, __) => null,
        );

        return DropdownButtonFormField<String>(
          value: _selectedValue(selected, options),
          decoration: const InputDecoration(
            labelText: 'Negocio / Sucursal',
          ),
          items: options.map((option) {
            return DropdownMenuItem<String>(
              value: _optionValue(option),
              child: Text(option.displayName),
            );
          }).toList(),
          onChanged: (value) async {
            if (value == null) {
              return;
            }

            final option = options.firstWhere(
              (item) => _optionValue(item) == value,
            );

            final service = ref.read(appBusinessSelectionServiceProvider);

            final result = await service.selectContext(
              profileId: option.profileId,
              businessId: option.businessId,
              branchId: option.branchId,
            );

            ref.invalidate(appSelectedBusinessOptionProvider(profileId));

            onSelected?.call(result);
          },
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (error, _) => Text(
        'Error cargando negocios: $error',
      ),
    );
  }

  String? _selectedValue(
    AppBusinessSelectionOption? selected,
    List<AppBusinessSelectionOption> options,
  ) {
    if (selected == null) {
      return null;
    }

    final value = _optionValue(selected);

    final exists = options.any((option) => _optionValue(option) == value);

    if (!exists) {
      return null;
    }

    return value;
  }

  String _optionValue(AppBusinessSelectionOption option) {
    return '${option.businessId}:${option.branchId ?? 'main'}:${option.roleId}';
  }
}
