import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventario_frontend/features/auth/application/productive_auth_providers.dart';
import 'package:inventario_frontend/features/auth/application/productive_auth_service.dart';
import 'package:inventario_frontend/features/auth/presentation/screens/productive_login_screen.dart';
import 'package:inventario_frontend/features/auth/presentation/screens/productive_registration_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('RG-02 registration validates email, password and confirmation',
      (tester) async {
    var calls = 0;
    await _pumpRegistration(
      tester,
      signUp: ({required email, required password}) async {
        calls++;
        return const ProductiveSignUpResult.authenticated();
      },
    );

    await tester.tap(find.byKey(const Key('registration-submit')));
    await tester.pump();
    expect(find.text('Ingresa un correo electrónico válido.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('registration-email')),
      'pilot@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('registration-password')),
      '123',
    );
    await tester.tap(find.byKey(const Key('registration-submit')));
    await tester.pump();
    expect(
      find.text('La contraseña debe tener al menos 6 caracteres.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const Key('registration-password')),
      'secure-password',
    );
    await tester.enterText(
      find.byKey(const Key('registration-confirmation')),
      'different-password',
    );
    await tester.tap(find.byKey(const Key('registration-submit')));
    await tester.pump();
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('RG-03 signup with Session continues through normal auth state',
      (tester) async {
    expect(productiveSignUpResultFor(_session).isAuthenticated, isTrue);
    var calls = 0;
    await _pumpRegistration(
      tester,
      signUp: ({required email, required password}) async {
        calls++;
        expect(email, 'pilot@example.com');
        expect(password, 'secure-password');
        return const ProductiveSignUpResult.authenticated();
      },
    );
    await _fillValidRegistration(tester);

    await tester.tap(find.byKey(const Key('registration-submit')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.text('Cuenta creada. Validando acceso...'), findsOneWidget);
    expect(find.text('Revisa tu correo'), findsNothing);
  });

  testWidgets('RG-04 signup without Session shows confirmation pending',
      (tester) async {
    expect(productiveSignUpResultFor(null).requiresEmailConfirmation, isTrue);
    await _pumpRegistration(
      tester,
      signUp: ({required email, required password}) async =>
          const ProductiveSignUpResult.confirmationRequired(),
    );
    await _fillValidRegistration(tester);

    await tester.tap(find.byKey(const Key('registration-submit')));
    await tester.pumpAndSettle();

    expect(find.text('Revisa tu correo'), findsOneWidget);
    expect(
      find.text(
        'Te enviamos un enlace para confirmar tu cuenta. Después vuelve a CronosManagement para iniciar sesión.',
      ),
      findsOneWidget,
    );
    expect(find.text('Volver al inicio de sesión'), findsOneWidget);
  });

  testWidgets('RG-05 duplicate signup submit invokes Auth once',
      (tester) async {
    final pending = Completer<ProductiveSignUpResult>();
    var calls = 0;
    await _pumpRegistration(
      tester,
      signUp: ({required email, required password}) {
        calls++;
        return pending.future;
      },
    );
    await _fillValidRegistration(tester);

    await tester.tap(find.byKey(const Key('registration-submit')));
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('registration-submit')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(calls, 1);
    pending.complete(const ProductiveSignUpResult.authenticated());
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('RG-09 forgot password remains available', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productivePasswordRecoveryProvider.overrideWithValue((email) async {
            calls++;
            expect(email, 'pilot@example.com');
          }),
        ],
        child: const MaterialApp(home: ProductiveLoginScreen()),
      ),
    );

    await tester.tap(find.text('Olvidé mi contraseña'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'pilot@example.com');
    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.textContaining('recibirás instrucciones'), findsOneWidget);
  });
}

Future<void> _pumpRegistration(
  WidgetTester tester, {
  required ProductiveSignUp signUp,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [productiveSignUpProvider.overrideWithValue(signUp)],
      child: const MaterialApp(home: ProductiveRegistrationScreen()),
    ),
  );
}

Future<void> _fillValidRegistration(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('registration-email')),
    'pilot@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('registration-password')),
    'secure-password',
  );
  await tester.enterText(
    find.byKey(const Key('registration-confirmation')),
    'secure-password',
  );
}

final _session = Session(
  accessToken: 'test-token',
  refreshToken: 'test-refresh',
  tokenType: 'bearer',
  user: const User(
    id: 'registered-user',
    appMetadata: {},
    userMetadata: {},
    aud: 'authenticated',
    email: 'pilot@example.com',
    createdAt: '2026-09-17T00:00:00Z',
  ),
);
