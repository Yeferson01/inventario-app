import 'package:supabase_flutter/supabase_flutter.dart';

const platformInvitationPasswordSetupMetadataKey =
    'platform_invitation_requires_password_setup';

bool invitationPasswordSetupRequired(Map<String, dynamic>? metadata) {
  return metadata?[platformInvitationPasswordSetupMetadataKey] == true;
}

enum ProductiveSignUpOutcome {
  authenticated,
  confirmationRequired,
}

class ProductiveSignUpResult {
  const ProductiveSignUpResult._(this.outcome);

  const ProductiveSignUpResult.authenticated()
      : this._(ProductiveSignUpOutcome.authenticated);

  const ProductiveSignUpResult.confirmationRequired()
      : this._(ProductiveSignUpOutcome.confirmationRequired);

  final ProductiveSignUpOutcome outcome;

  bool get isAuthenticated => outcome == ProductiveSignUpOutcome.authenticated;
  bool get requiresEmailConfirmation =>
      outcome == ProductiveSignUpOutcome.confirmationRequired;
}

ProductiveSignUpResult productiveSignUpResultFor(Session? session) {
  return session == null
      ? const ProductiveSignUpResult.confirmationRequired()
      : const ProductiveSignUpResult.authenticated();
}

typedef AuthUserUpdater = Future<void> Function(UserAttributes attributes);

Future<void> completeInvitationPasswordSetup({
  required String password,
  required AuthUserUpdater updateUser,
}) {
  return updateUser(
    UserAttributes(
      password: password,
      data: const {
        platformInvitationPasswordSetupMetadataKey: false,
      },
    ),
  );
}

class ProductiveAuthService {
  ProductiveAuthService(
    GoTrueClient auth, {
    required String emailRedirectTo,
  })  : _auth = auth,
        _emailRedirectTo = emailRedirectTo;

  final GoTrueClient _auth;
  final String _emailRedirectTo;

  Future<ProductiveSignUpResult> signUp({
    required String email,
    required String password,
  }) async {
    final response = await _auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: _emailRedirectTo,
    );
    return productiveSignUpResultFor(response.session);
  }

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
    await completeInvitationPasswordSetup(
      password: password,
      updateUser: (attributes) async {
        await _auth.updateUser(attributes);
      },
    );
  }
}
