import 'package:flutter/material.dart';

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

    if (summary == null) {
      icon = Icons.point_of_sale_outlined;
      title = 'Sin caja local';
      subtitle = 'No hay sesiones de caja locales para esta sucursal.';
    } else if (isOpen) {
      icon = Icons.lock_open_outlined;
      title = 'Caja abierta';
      subtitle = canUploadPos
          ? 'POS habilitado. La caja está lista para vender.'
          : 'Caja abierta, pero POS todavía está bloqueado.';
    } else if (isClosed) {
      icon = Icons.lock_outline;
      title = 'Caja cerrada';
      subtitle = 'Abre una nueva caja para registrar ventas.';
    } else {
      icon = Icons.info_outline;
      title = 'Estado de caja: ${status ?? 'desconocido'}';
      subtitle = 'Revisa la sesión antes de continuar.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle),
                  if (blockedReason != null &&
                      blockedReason.trim().isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      blockedReason,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
