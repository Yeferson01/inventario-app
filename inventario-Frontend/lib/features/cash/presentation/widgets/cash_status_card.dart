import 'package:flutter/material.dart';

import '../../../../app/theme/app_theme.dart';
import '../../../../shared/presentation/widgets/app_glass_card.dart';
import '../../../../shared/presentation/widgets/app_status_chip.dart';

class CashStatusCard extends StatelessWidget {
  const CashStatusCard({
    super.key,
    required this.summary,
    required this.readiness,
  });

  final Map<String, dynamic>? summary;
  final Map<String, dynamic>? readiness;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final status = summary?['status']?.toString();
    final isOpen = status == 'open';
    final isClosed = status == 'closed';
    final canUploadPos = readiness?['pos_upload_blocked_reason'] == null;
    final blockedReason = readiness?['pos_upload_blocked_reason']?.toString();

    IconData icon;
    String title;
    String subtitle;
    Gradient gradient;
    AppStatusTone tone;
    String chipLabel;

    if (summary == null) {
      icon = Icons.point_of_sale_outlined;
      title = 'Sin caja local';
      subtitle = 'Abre una caja para empezar a operar.';
      gradient = CronosColors.primaryGradient;
      tone = AppStatusTone.neutral;
      chipLabel = 'Sin sesión';
    } else if (isOpen) {
      icon = Icons.lock_open_outlined;
      title = 'Caja abierta';
      subtitle = canUploadPos
          ? 'POS habilitado. La caja está lista para vender.'
          : 'Caja abierta, pero POS todavía está bloqueado.';
      gradient = CronosColors.successGradient;
      tone = canUploadPos ? AppStatusTone.success : AppStatusTone.warning;
      chipLabel = canUploadPos ? 'Lista para POS' : 'Cash pendiente';
    } else if (isClosed) {
      icon = Icons.lock_outline;
      title = 'Caja cerrada';
      subtitle = 'Abre una nueva caja para registrar ventas.';
      gradient = CronosColors.warningGradient;
      tone = AppStatusTone.warning;
      chipLabel = 'Cerrada';
    } else {
      icon = Icons.info_outline;
      title = 'Estado de caja: ${status ?? 'desconocido'}';
      subtitle = 'Revisa la sesión antes de continuar.';
      gradient = CronosColors.primaryGradient;
      tone = AppStatusTone.info;
      chipLabel = status ?? 'Estado';
    }

    return AppGlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(CronosSpacing.md),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(CronosRadius.lg),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(CronosRadius.md),
                  ),
                  child: Icon(
                    icon,
                    size: 30,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: CronosSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.88),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(CronosSpacing.md),
            child: Row(
              children: [
                AppStatusChip(
                  label: chipLabel,
                  tone: tone,
                  icon:
                      isOpen ? Icons.check_circle_outline : Icons.info_outline,
                ),
                const Spacer(),
                if (blockedReason != null && blockedReason.trim().isNotEmpty)
                  Expanded(
                    child: Text(
                      blockedReason,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
