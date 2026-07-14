import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final supabaseAuthProvider = Provider<GoTrueClient>((ref) {
  return ref.watch(supabaseClientProvider).auth;
});

final currentSupabaseSessionProvider = Provider<Session?>((ref) {
  return ref.watch(supabaseAuthProvider).currentSession;
});

final currentSupabaseUserProvider = Provider<User?>((ref) {
  return ref.watch(supabaseAuthProvider).currentUser;
});
