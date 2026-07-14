import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/app_glass_card.dart';

class CashMetricTile extends StatelessWidget {
  const CashMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.helper,
    this.icon,
  });

  final String label;
  final String value;
  final String? helper;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppGlassCard(
      margin: const EdgeInsets.only(bottom: CronosSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: CronosColors.primarySoft,
                borderRadius: BorderRadius.circular(CronosRadius.md),
              ),
              child: Icon(
                icon,
                color: CronosColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: CronosSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (helper != null && helper!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    helper!,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
