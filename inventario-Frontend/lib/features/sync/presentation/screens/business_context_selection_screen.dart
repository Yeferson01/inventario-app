import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/app_business_context_selector.dart';

class BusinessContextSelectionScreen extends ConsumerWidget {
  const BusinessContextSelectionScreen({
    required this.profileId,
    this.title = 'Selecciona tu negocio',
    this.subtitle = 'Elige el negocio y la sucursal con la que vas a trabajar.',
    this.onContextSelected,
    super.key,
  });

  final String profileId;
  final String title;
  final String subtitle;
  final VoidCallback? onContextSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 520,
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      AppBusinessContextSelector(
                        profileId: profileId,
                        onSelected: (_) {
                          onContextSelected?.call();

                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Negocio seleccionado correctamente.',
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Esta selección se usará para permisos, inventario, ventas y sincronización offline.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
