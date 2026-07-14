import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';

enum AppStatusTone {
  success,
  warning,
  danger,
  info,
  neutral,
}

class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  final String label;
  final AppStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = _colorsForTone(tone);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: CronosSpacing.sm,
        vertical: CronosSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(CronosRadius.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: colors.foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: colors.foreground,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  _StatusColors _colorsForTone(AppStatusTone tone) {
    return switch (tone) {
      AppStatusTone.success => const _StatusColors(
          background: CronosColors.successSoft,
          foreground: CronosColors.success,
          border: Color(0xFFBBF7D0),
        ),
      AppStatusTone.warning => const _StatusColors(
          background: CronosColors.warningSoft,
          foreground: CronosColors.warning,
          border: Color(0xFFFDE68A),
        ),
      AppStatusTone.danger => const _StatusColors(
          background: CronosColors.dangerSoft,
          foreground: CronosColors.danger,
          border: Color(0xFFFECACA),
        ),
      AppStatusTone.info => const _StatusColors(
          background: CronosColors.infoSoft,
          foreground: CronosColors.info,
          border: Color(0xFFA5F3FC),
        ),
      AppStatusTone.neutral => const _StatusColors(
          background: CronosColors.surfaceMuted,
          foreground: CronosColors.textSecondary,
          border: CronosColors.border,
        ),
    };
  }
}

class _StatusColors {
  const _StatusColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}
