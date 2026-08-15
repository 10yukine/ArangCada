/// Compile-time app configuration.
///
/// Values are supplied via `--dart-define-from-file=env.json` (see
/// `env.json.example` for the required keys), NOT loaded from a bundled
/// asset. `String.fromEnvironment` reads these at compile time, so the raw
/// JSON file itself never ships inside the app package.
///
/// SECURITY.md limits Flutter to the Supabase URL and anon key only. The
/// Supabase *service role* key must never have a variable reserved for it
/// here, must never be read by this app, and belongs only in Supabase's own
/// secrets store or a server-only environment (Edge Functions, seed scripts).
///
/// Nothing in this file may log, print, or otherwise surface a value. The
/// only safe things to do with a config value are: pass it straight to the
/// SDK/client that needs it, or check whether it is empty.
class AppConfig {
  const AppConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );
  static const String mapTilerKey = String.fromEnvironment('MAPTILER_KEY');
  static const String orsApiKey = String.fromEnvironment('ORS_API_KEY');

  /// Whether every production integration value is available.
  ///
  /// The offline demo deliberately does not require these values. A later
  /// production entrypoint can continue to call [assertConfigured].
  static bool get isFullyConfigured =>
      supabaseUrl.isNotEmpty &&
      supabaseAnonKey.isNotEmpty &&
      mapTilerKey.isNotEmpty &&
      orsApiKey.isNotEmpty;

  /// Throws with a message naming the missing variable -- never its value --
  /// if any required config is absent. Call once at startup, before any
  /// screen or client that depends on these values.
  static void assertConfigured() {
    final missing = <String>[
      if (supabaseUrl.isEmpty) 'SUPABASE_URL',
      if (supabaseAnonKey.isEmpty) 'SUPABASE_ANON_KEY',
      if (mapTilerKey.isEmpty) 'MAPTILER_KEY',
      if (orsApiKey.isEmpty) 'ORS_API_KEY',
    ];
    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required config: ${missing.join(', ')}. '
        'Run with --dart-define-from-file=env.json '
        '(copy env.json.example and fill in real values; '
        'env.json is gitignored and must never be committed).',
      );
    }
  }
}
