/// Compile-time configuration for the standalone admin console.
///
/// Build with `--dart-define-from-file=env.json`. The ignored JSON file never
/// becomes a bundled asset, and only the public/publishable Supabase key may
/// be supplied to this browser application.
abstract final class AdminAppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
