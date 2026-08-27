import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final supabaseAuthProvider = Provider<GoTrueClient>((ref) {
  return ref.watch(supabaseClientProvider).auth;
});

final supabaseAuthStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseAuthProvider).onAuthStateChange;
});

final currentSupabaseSessionProvider = Provider<Session?>((ref) {
  final auth = ref.watch(supabaseAuthProvider);
  return ref.watch(supabaseAuthStateProvider).value?.session ??
      auth.currentSession;
});

final currentSupabaseUserProvider = Provider<User?>((ref) {
  return ref.watch(currentSupabaseSessionProvider)?.user;
});
