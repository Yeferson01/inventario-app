import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/sync/presentation/productive_error_presentation.dart';

void main() {
  test('UX-01 retryable keeps local data safe and offers retry', () {
    final copy = ProductiveErrorPresentation.forCategory(
      ProductiveErrorCategory.retryable,
    );

    expect(copy.title, 'No se pudo sincronizar ahora');
    expect(copy.message, contains('siguen seguros en este dispositivo'));
    expect(copy.actionLabel, 'Reintentar');
  });

  test('UX-02 offline is not presented as data loss or conflict', () {
    final copy = ProductiveErrorPresentation.forCategory(
      ProductiveErrorCategory.offline,
    );

    expect(copy.title, 'Sin conexión');
    expect(copy.message, contains('permanecen en este dispositivo'));
    expect(copy.message.toLowerCase(), isNot(contains('conflict')));
  });

  test('UX-03 needs attention uses operational review language', () {
    final copy = ProductiveErrorPresentation.forCategory(
      ProductiveErrorCategory.needsAttention,
    );

    expect(copy.message, 'Hay una operación que necesita revisión.');
    expect(copy.actionLabel, 'Revisar operación');
  });

  test('UX-04 stale sale explicitly identifies a pending Sale', () {
    final copy = ProductiveErrorPresentation.forCategory(
      ProductiveErrorCategory.staleSale,
    );

    expect(copy.title, 'Venta pendiente de revisión');
    expect(copy.message, contains('venta pendiente de revisión'));
    expect(copy.actionLabel, 'Revisar venta');
  });

  test('UX-05 context not ready avoids recovery terminology', () {
    final copy = ProductiveErrorPresentation.forCategory(
      ProductiveErrorCategory.contextNotReady,
    );

    expect(copy.message, contains('información necesaria'));
    expect(copy.title.toLowerCase(), isNot(contains('recovery')));
    expect(copy.title.toLowerCase(), isNot(contains('recuperación')));
  });

  test('UX-06 authorization is distinct from an offline failure', () {
    final authorization = ProductiveErrorPresentation.forCategory(
      ProductiveErrorCategory.authorization,
    );
    final offline = ProductiveErrorPresentation.forCategory(
      ProductiveErrorCategory.offline,
    );

    expect(authorization.title, 'Acceso no disponible');
    expect(authorization.message, contains('negocio o sucursal'));
    expect(authorization.actionLabel, 'Volver a iniciar sesión');
    expect(authorization.message, isNot(offline.message));
  });

  test('UX-07 release copy contains no technical diagnostic terms', () {
    const forbidden = [
      'recovery',
      'reconciliation',
      'blocker',
      'batch',
      'mutation',
      'checkpoint',
      'snapshot',
      'rpc',
      'uuid',
      'supabase',
      'sqlite',
      'exception',
      'stack trace',
    ];

    for (final category in ProductiveErrorCategory.values) {
      final copy = ProductiveErrorPresentation.forCategory(category);
      final visible =
          '${copy.title} ${copy.message} ${copy.actionLabel}'.toLowerCase();
      for (final term in forbidden) {
        expect(visible, isNot(contains(term)),
            reason: '$category exposed $term');
      }
    }
  });
}
