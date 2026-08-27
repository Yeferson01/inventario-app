import 'package:supabase_flutter/supabase_flutter.dart';

class ProductiveAuthService {
  ProductiveAuthService(GoTrueClient auth) : _auth = auth;

  final GoTrueClient _auth;

  Future<void> signInWithPassword({
    required String email,
    required String password,
  }) async {
    await _auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _auth.signOut();

  Future<void> sendPasswordRecovery({
    required String email,
    required String redirectTo,
  }) async {
    await _auth.resetPasswordForEmail(email, redirectTo: redirectTo);
  }

  Future<void> updatePassword(String password) async {
    await _auth.updateUser(
      UserAttributes(
        password: password,
        data: const {
          'platform_invitation_requires_password_setup': false,
        },
      ),
    );
  }
}
