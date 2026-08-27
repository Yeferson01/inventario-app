import 'package:flutter/material.dart';

import '../../data/models/authorized_operational_context_models.dart';
import '../widgets/app_business_context_selector.dart';

class BusinessContextSelectionScreen extends StatelessWidget {
  const BusinessContextSelectionScreen({
    required this.contexts,
    required this.onContextSelected,
    this.title = 'Selecciona tu negocio',
    this.subtitle = 'Elige el negocio y la sucursal con la que vas a trabajar.',
    this.isSubmitting = false,
    this.additionalContent,
    super.key,
  });

  final List<AuthorizedOperationalContext> contexts;
  final ValueChanged<AuthorizedOperationalContext> onContextSelected;
  final String title;
  final String subtitle;
  final bool isSubmitting;
  final Widget? additionalContent;

  @override
  Widget build(BuildContext context) {
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
                        contexts: contexts,
                        isSubmitting: isSubmitting,
                        onSelected: onContextSelected,
                      ),
                      if (additionalContent != null) ...[
                        const SizedBox(height: 24),
                        additionalContent!,
                      ],
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
