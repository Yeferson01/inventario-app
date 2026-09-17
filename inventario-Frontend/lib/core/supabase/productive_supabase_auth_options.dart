import 'package:supabase_flutter/supabase_flutter.dart';

/// Productive Auth callbacks are owned by supabase_flutter/app_links.
const productiveSupabaseAuthOptions = FlutterAuthClientOptions(
  authFlowType: AuthFlowType.pkce,
  detectSessionInUri: true,
);
