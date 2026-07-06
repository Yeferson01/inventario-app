import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

class AppGlassCard extends StatelessWidget {
  const AppGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(CronosSpacing.md),
    this.margin = EdgeInsets.zero,
    this.borderRadius = CronosRadius.lg,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: CronosColors.surface,
        borderRadius: radius,
        border: Border.all(
          color: CronosColors.border,
        ),
        boxShadow: [
          BoxShadow(
            color: CronosColors.primaryDark.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: card,
        ),
      ),
    );
  }
}
