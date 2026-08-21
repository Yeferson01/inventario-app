import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../sync/application/app_router_sync_bootstrap_provider.dart';
import '../../../sync/application/operational_bootstrap_entry_providers.dart';

class DebugSupabaseLoginScreen extends ConsumerStatefulWidget {
  const DebugSupabaseLoginScreen({super.key});

  @override
  ConsumerState<DebugSupabaseLoginScreen> createState() =>
      _DebugSupabaseLoginScreenState();
}

class _DebugSupabaseLoginScreenState
    extends ConsumerState<DebugSupabaseLoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  String? _message;

  SupabaseClient get _client => Supabase.instance.client;

  User? get _currentUser => _client.auth.currentUser;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      if (email.isEmpty || password.isEmpty) {
        throw StateError('Ingresa email y contraseña.');
      }

      final response = await _client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      ref.invalidate(appRouterSyncBootstrapProvider);
      ref.invalidate(productiveOperationalEntryProvider);

      setState(() {
        _message = 'Login OK. User ID: ${response.user?.id ?? 'sin user'}';
      });
    } catch (error) {
      setState(() {
        _message = 'Error login: $error';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await _client.auth.signOut();

      ref.invalidate(appRouterSyncBootstrapProvider);
      ref.invalidate(productiveOperationalEntryProvider);

      setState(() {
        _message = 'Sesión cerrada.';
      });
    } catch (error) {
      setState(() {
        _message = 'Error cerrando sesión: $error';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _refresh() {
    setState(() {
      _message = 'Estado actualizado.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = _currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Debug Supabase Login'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Login real de Supabase',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              user == null
                  ? 'Estado: no autenticado'
                  : 'Estado: autenticado\nUser ID: ${user.id}\nEmail: ${user.email ?? 'sin email'}',
              style: TextStyle(
                color: user == null ? Colors.red : Colors.green,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _isLoading ? null : _signIn,
              child: const Text('Iniciar sesión'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isLoading ? null : _signOut,
              child: const Text('Cerrar sesión'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _isLoading ? null : _refresh,
              child: const Text('Refrescar estado'),
            ),
            const SizedBox(height: 24),
            FilledButton.tonal(
              onPressed: user == null
                  ? null
                  : () => context.go('/debug/e2e-real-sync'),
              child: const Text('Ir a prueba E2E real'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => context.go('/debug/ping'),
              child: const Text('Ir a Debug Ping'),
            ),
            if (_isLoading) ...[
              const SizedBox(height: 24),
              const LinearProgressIndicator(),
            ],
            if (_message != null) ...[
              const SizedBox(height: 24),
              SelectableText(
                _message!,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
