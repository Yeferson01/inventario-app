import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import 'app_glass_card.dart';
import 'app_status_chip.dart';

class AppModuleCard extends StatelessWidget {
  const AppModuleCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    this.statusLabel,
    this.statusTone = AppStatusTone.neutral,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Gradient gradient;
  final String? statusLabel;
  final AppStatusTone statusTone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppGlassCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(CronosRadius.md),
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const Spacer(),
              if (statusLabel != null)
                AppStatusChip(
                  label: statusLabel!,
                  tone: statusTone,
                ),
            ],
          ),
          const SizedBox(height: CronosSpacing.md),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: CronosSpacing.xs),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
