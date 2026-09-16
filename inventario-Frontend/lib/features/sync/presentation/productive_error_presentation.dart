enum ProductiveErrorCategory {
  retryable,
  offline,
  needsAttention,
  staleSale,
  contextNotReady,
  authorization,
}

class ProductiveErrorPresentation {
  const ProductiveErrorPresentation({
    required this.title,
    required this.message,
    required this.actionLabel,
  });

  final String title;
  final String message;
  final String actionLabel;

  static ProductiveErrorPresentation forCategory(
    ProductiveErrorCategory category,
  ) {
    return switch (category) {
      ProductiveErrorCategory.retryable => const ProductiveErrorPresentation(
          title: 'No se pudo sincronizar ahora',
          message: 'Tus datos guardados siguen seguros en este dispositivo.',
          actionLabel: 'Reintentar',
        ),
      ProductiveErrorCategory.offline => const ProductiveErrorPresentation(
          title: 'Sin conexión',
          message: 'Tus operaciones guardadas permanecen en este dispositivo.',
          actionLabel: 'Reintentar',
        ),
      ProductiveErrorCategory.needsAttention =>
        const ProductiveErrorPresentation(
          title: 'Operación pendiente de revisión',
          message: 'Hay una operación que necesita revisión.',
          actionLabel: 'Revisar operación',
        ),
      ProductiveErrorCategory.staleSale => const ProductiveErrorPresentation(
          title: 'Venta pendiente de revisión',
          message: 'Hay una venta pendiente de revisión antes de continuar.',
          actionLabel: 'Revisar venta',
        ),
      ProductiveErrorCategory.contextNotReady =>
        const ProductiveErrorPresentation(
          title: 'Información pendiente',
          message:
              'No pudimos preparar toda la información necesaria para continuar.',
          actionLabel: 'Reintentar',
        ),
      ProductiveErrorCategory.authorization =>
        const ProductiveErrorPresentation(
          title: 'Acceso no disponible',
          message: 'Tu acceso a este negocio o sucursal ya no está disponible.',
          actionLabel: 'Volver a iniciar sesión',
        ),
    };
  }
}
