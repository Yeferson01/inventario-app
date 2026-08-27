import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/app/router/app_router.dart';
import 'package:inventario_frontend/features/auth/application/productive_auth_providers.dart';

void main() {
  testWidgets('unauthenticated productive route resolves to Login',
      (tester) async {
    final router = AppRouter.create(
      phase: ProductiveAuthPhase.unauthenticated,
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.textContaining('Regístrate'), findsNothing);
  });
}
