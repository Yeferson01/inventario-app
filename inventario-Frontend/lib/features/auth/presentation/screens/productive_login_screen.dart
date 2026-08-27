import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/productive_auth_providers.dart';

class ProductiveLoginScreen extends ConsumerStatefulWidget {
  const ProductiveLoginScreen({super.key});

  @override
  ConsumerState<ProductiveLoginScreen> createState() =>
      _ProductiveLoginScreenState();
}

class _ProductiveLoginScreenState extends ConsumerState<ProductiveLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  bool _isRecoveryMode = false;
  bool _obscurePassword = true;
  String? _message;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || !_looksLikeEmail(email)) {
      setState(() => _message = 'Ingresa un correo electrónico válido.');
      return;
    }
    if (!_isRecoveryMode && password.isEmpty) {
      setState(() => _message = 'Ingresa tu contraseña.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _message = null;
    });
    try {
      if (_isRecoveryMode) {
        await ref.read(productivePasswordRecoveryProvider)(email);
        if (mounted) {
          setState(() {
            _message =
                'Si la cuenta está habilitada, recibirás instrucciones para restablecer tu contraseña.';
          });
        }
      } else {
        await ref.read(productiveSignInProvider)(
          email: email,
          password: password,
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _message = _isRecoveryMode
              ? 'No fue posible enviar la recuperación. Intenta nuevamente.'
              : 'No fue posible iniciar sesión. Verifica tus credenciales e intenta nuevamente.';
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _isRecoveryMode
                            ? 'Recuperar contraseña'
                            : 'Iniciar sesión',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isRecoveryMode
                            ? 'Te enviaremos un enlace seguro a la app.'
                            : 'Acceso privado a CronosManagement.',
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _emailController,
                        enabled: !_isSubmitting,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (!_isRecoveryMode) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _passwordController,
                          enabled: !_isSubmitting,
                          obscureText: _obscurePassword,
                          autofillHints: const [AutofillHints.password],
                          onSubmitted: (_) => _submit(),
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              onPressed: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                              icon: Icon(
                                _obscurePassword
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        Semantics(
                          liveRegion: true,
                          child: Text(_message!),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _isSubmitting ? null : _submit,
                        child: _isSubmitting
                            ? const SizedBox.square(
                                dimension: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                _isRecoveryMode ? 'Enviar enlace' : 'Ingresar',
                              ),
                      ),
                      TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => setState(() {
                                  _isRecoveryMode = !_isRecoveryMode;
                                  _message = null;
                                }),
                        child: Text(
                          _isRecoveryMode
                              ? 'Volver al inicio de sesión'
                              : 'Olvidé mi contraseña',
                        ),
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

bool _looksLikeEmail(String value) {
  final at = value.indexOf('@');
  return at > 0 && value.indexOf('.', at) > at + 1;
}
