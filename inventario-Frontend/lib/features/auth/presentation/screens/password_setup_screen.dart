import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/productive_auth_providers.dart';

class PasswordSetupScreen extends ConsumerStatefulWidget {
  const PasswordSetupScreen({super.key});

  @override
  ConsumerState<PasswordSetupScreen> createState() =>
      _PasswordSetupScreenState();
}

class _PasswordSetupScreenState extends ConsumerState<PasswordSetupScreen> {
  final _passwordController = TextEditingController();
  final _confirmationController = TextEditingController();
  bool _isSubmitting = false;
  bool _obscure = true;
  String? _message;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmationController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final password = _passwordController.text;
    if (password.length < 6) {
      setState(
          () => _message = 'La contraseña debe tener al menos 6 caracteres.');
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
      await ref.read(productivePasswordUpdateProvider)(password);
    } catch (_) {
      if (mounted) {
        setState(() {
          _message =
              'No fue posible actualizar la contraseña. Intenta nuevamente.';
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
                        'Define tu contraseña',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tu sesión ya fue validada por Supabase. La invitación del negocio se comprobará después en el servidor.',
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _passwordController,
                        enabled: !_isSubmitting,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          labelText: 'Nueva contraseña',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _confirmationController,
                        enabled: !_isSubmitting,
                        obscureText: _obscure,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(
                          labelText: 'Confirmar contraseña',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 16),
                        Text(_message!),
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
                            : const Text('Guardar contraseña'),
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
