import 'package:flutter/material.dart';

import '../../data/models/authorized_operational_context_models.dart';

class OperationalBranchSwitcher extends StatelessWidget {
  const OperationalBranchSwitcher({
    required this.currentContext,
    required this.contexts,
    required this.onSelected,
    this.isSwitching = false,
    this.foregroundColor,
    super.key,
  });

  final AuthorizedOperationalContext currentContext;
  final List<AuthorizedOperationalContext> contexts;
  final ValueChanged<AuthorizedOperationalContext> onSelected;
  final bool isSwitching;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final scopedContexts = contexts
        .where(
          (item) =>
              item.profileId == currentContext.profileId &&
              item.businessId == currentContext.businessId,
        )
        .toList(growable: false);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(
          'Sucursal actual: ${currentContext.branchName}',
          key: const Key('current-operational-branch-name'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: foregroundColor,
                fontWeight: FontWeight.w700,
              ),
        ),
        if (scopedContexts.length > 1)
          TextButton.icon(
            key: const Key('change-operational-branch'),
            onPressed: isSwitching
                ? null
                : () => _showBranchOptions(context, scopedContexts),
            style: TextButton.styleFrom(foregroundColor: foregroundColor),
            icon: isSwitching
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.swap_horiz_outlined),
            label: const Text('Cambiar sucursal'),
          ),
      ],
    );
  }

  Future<void> _showBranchOptions(
    BuildContext context,
    List<AuthorizedOperationalContext> scopedContexts,
  ) async {
    final selected = await showModalBottomSheet<AuthorizedOperationalContext>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
              child: Text(
                'Cambiar sucursal',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
            ),
            for (final item in scopedContexts)
              ListTile(
                key: ValueKey('operational-branch-${item.branchId}'),
                leading: Icon(
                  item.branchId == currentContext.branchId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                ),
                title: Text(item.branchName),
                subtitle: item.branchId == currentContext.branchId
                    ? const Text('Sucursal actual')
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(item),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (selected != null && selected.branchId != currentContext.branchId) {
      onSelected(selected);
    }
  }
}
