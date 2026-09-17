import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/routes_constants.dart';
import '../../application/productive_auth_providers.dart';

class ProductiveRegistrationScreen extends ConsumerStatefulWidget {
  const ProductiveRegistrationScreen({super.key});

  @override
  ConsumerState<ProductiveRegistrationScreen> createState() =>
      _ProductiveRegistrationScreenState();
}

class _ProductiveRegistrationScreenState
    extends ConsumerState<ProductiveRegistrationScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isSubmitting = false;
  bool _obscurePassword = true;
  bool _confirmationPending = false;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (!_looksLikeEmail(email)) {
      setState(() => _message = 'Ingresa un correo electrónico válido.');
      return;
    }
    if (password.length < 6) {
      setState(
        () => _message = 'La contraseña debe tener al menos 6 caracteres.',
      );
      return;
    }
    if (password != _confirmationController.text) {
      setState(() => _message = 'Las contraseñas no coinciden.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _message = null;
    });
    try {
      final result = await ref.read(productiveSignUpProvider)(
        email: email,
        password: password,
      );
      if (!mounted) return;
      if (result.requiresEmailConfirmation) {
        setState(() => _confirmationPending = true);
      } else {
        setState(() => _message = 'Cuenta creada. Validando acceso...');
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'No fue posible crear la cuenta. Verifica los datos e intenta nuevamente.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _confirmationPending
                      ? _EmailConfirmationPending(
                          onReturnToLogin: () =>
                              context.go(AppRoutes.loginPath),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Crear cuenta',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Crea tu acceso a CronosManagement. Los negocios y permisos se asignan después.',
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              key: const Key('registration-email'),
                              controller: _emailController,
                              enabled: !_isSubmitting,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Correo electrónico',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              key: const Key('registration-password'),
                              controller: _passwordController,
                              enabled: !_isSubmitting,
                              obscureText: _obscurePassword,
                              autofillHints: const [AutofillHints.newPassword],
                              decoration: InputDecoration(
                                labelText: 'Contraseña',
                                border: const OutlineInputBorder(),
                                suffixIcon: IconButton(
                                  onPressed: _isSubmitting
                                      ? null
                                      : () => setState(
                                            () => _obscurePassword =
                                                !_obscurePassword,
                                          ),
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              key: const Key('registration-confirmation'),
                              controller: _confirmationController,
                              enabled: !_isSubmitting,
                              obscureText: _obscurePassword,
                              autofillHints: const [AutofillHints.newPassword],
                              onSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: 'Confirmar contraseña',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            if (_message != null) ...[
                              const SizedBox(height: 16),
                              Semantics(
                                liveRegion: true,
                                child: Text(_message!),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton(
                              key: const Key('registration-submit'),
                              onPressed: _isSubmitting ? null : _submit,
                              child: _isSubmitting
                                  ? const SizedBox.square(
                                      dimension: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Crear cuenta'),
                            ),
                            TextButton(
                              key: const Key('registration-login'),
                              onPressed: _isSubmitting
                                  ? null
                                  : () => context.go(AppRoutes.loginPath),
                              child: const Text('Ya tengo una cuenta'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmailConfirmationPending extends StatelessWidget {
  const _EmailConfirmationPending({required this.onReturnToLogin});

  final VoidCallback onReturnToLogin;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Revisa tu correo',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        const Text(
          'Te enviamos un enlace para confirmar tu cuenta. Después vuelve a CronosManagement para iniciar sesión.',
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: onReturnToLogin,
          child: const Text('Volver al inicio de sesión'),
        ),
      ],
    );
  }
}

bool _looksLikeEmail(String value) {
  final at = value.indexOf('@');
  return at > 0 && value.indexOf('.', at) > at + 1;
}
