import 'package:flutter/material.dart';

import '../../data/models/authorized_operational_context_models.dart';

class AppBusinessContextSelector extends StatefulWidget {
  const AppBusinessContextSelector({
    required this.contexts,
    required this.onSelected,
    this.isSubmitting = false,
    super.key,
  });

  final List<AuthorizedOperationalContext> contexts;
  final ValueChanged<AuthorizedOperationalContext> onSelected;
  final bool isSubmitting;

  @override
  State<AppBusinessContextSelector> createState() =>
      _AppBusinessContextSelectorState();
}

class _AppBusinessContextSelectorState
    extends State<AppBusinessContextSelector> {
  String? _businessId;
  String? _branchId;

  @override
  void initState() {
    super.initState();
    _initializeSelection();
  }

  @override
  void didUpdateWidget(covariant AppBusinessContextSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameScopes(oldWidget.contexts, widget.contexts)) {
      _initializeSelection();
    }
  }

  void _initializeSelection() {
    final businesses = _groupByBusiness(widget.contexts);
    _businessId = businesses.length == 1 ? businesses.keys.single : null;
    _branchId = null;
  }

  @override
  Widget build(BuildContext context) {
    final businesses = _groupByBusiness(widget.contexts);
    final selectedBusinessContexts = _businessId == null
        ? const <AuthorizedOperationalContext>[]
        : businesses[_businessId] ?? const <AuthorizedOperationalContext>[];
    final selectedContext = _selectedContext(selectedBusinessContexts);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (businesses.length > 1) ...[
          DropdownButtonFormField<String>(
            key: const Key('operational-business-selector'),
            initialValue: _businessId,
            decoration: const InputDecoration(
              labelText: 'Negocio',
              border: OutlineInputBorder(),
            ),
            items: businesses.entries
                .map(
                  (entry) => DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text(entry.value.first.businessName),
                  ),
                )
                .toList(growable: false),
            onChanged: widget.isSubmitting
                ? null
                : (businessId) {
                    setState(() {
                      _businessId = businessId;
                      final branches = businessId == null
                          ? const <AuthorizedOperationalContext>[]
                          : businesses[businessId] ??
                              const <AuthorizedOperationalContext>[];
                      _branchId = branches.length == 1
                          ? branches.single.branchId
                          : null;
                    });
                  },
          ),
          const SizedBox(height: 16),
        ] else if (businesses.isNotEmpty) ...[
          Text(
            businesses.values.single.first.businessName,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
        ],
        if (_businessId != null)
          DropdownButtonFormField<String>(
            key: const Key('operational-branch-selector'),
            initialValue: _branchId,
            decoration: const InputDecoration(
              labelText: 'Sucursal',
              border: OutlineInputBorder(),
            ),
            items: selectedBusinessContexts
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item.branchId,
                    child: Text(item.branchName),
                  ),
                )
                .toList(growable: false),
            onChanged: widget.isSubmitting
                ? null
                : (branchId) {
                    setState(() {
                      _branchId = branchId;
                    });
                  },
          ),
        const SizedBox(height: 20),
        FilledButton(
          key: const Key('confirm-operational-context'),
          onPressed: widget.isSubmitting || selectedContext == null
              ? null
              : () => widget.onSelected(selectedContext),
          child: Text(
            widget.isSubmitting ? 'Preparando contexto...' : 'Continuar',
          ),
        ),
      ],
    );
  }

  AuthorizedOperationalContext? _selectedContext(
    List<AuthorizedOperationalContext> contexts,
  ) {
    final branchId = _branchId;
    if (branchId == null) {
      return null;
    }
    for (final context in contexts) {
      if (context.branchId == branchId) {
        return context;
      }
    }
    return null;
  }

  Map<String, List<AuthorizedOperationalContext>> _groupByBusiness(
    List<AuthorizedOperationalContext> contexts,
  ) {
    final grouped = <String, List<AuthorizedOperationalContext>>{};
    for (final context in contexts) {
      grouped.putIfAbsent(context.businessId, () => []).add(context);
    }
    return grouped;
  }

  bool _sameScopes(
    List<AuthorizedOperationalContext> left,
    List<AuthorizedOperationalContext> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index++) {
      if (left[index].scopeKey != right[index].scopeKey) {
        return false;
      }
    }
    return true;
  }
}
