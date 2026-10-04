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

  /// Optional. Google Routes API is a paid, opt-in upgrade over
  /// openrouteservice for unnamed/barangay-road accuracy -- see
  /// GoogleRoutesConfig. Absent by default; the app must keep working with
  /// only ORS configured, and ORS remains the automatic fallback even when
  /// this is present. Never required by assertConfigured().
  static const String googleRoutesApiKey = String.fromEnvironment(
    'GOOGLE_ROUTES_API_KEY',
  );

  /// Optional. Switches the map from MapLibre/MapTiler to the Google Maps SDK
  /// (free on Android). Also read by android/app/build.gradle.kts into the
  /// manifest, where the SDK looks for it.
  static const String googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
  );

  /// Optional. Google Places (New) search, with MapTiler as the fallback.
  static const String googlePlacesApiKey = String.fromEnvironment(
    'GOOGLE_PLACES_API_KEY',
  );

  /// Tells Google's web services which Android app is calling, so the
  /// Places/Routes key can be restricted to this app in Google Cloud ("Android
  /// apps": this package and certificate fingerprint). Without these headers
  /// the key could only be left usable from anywhere. Google ignores them
  /// while the key has no app restriction. A build signed with another
  /// certificate (a debug build) passes its own fingerprint as
  /// ANDROID_CERT_SHA1, and that fingerprint has to be on the key too.
  static const String androidCertSha1 = String.fromEnvironment(
    'ANDROID_CERT_SHA1',
    defaultValue: 'D1A9788DBB48F046C50486B30BAD751D208B4AF4',
  );
  static const Map<String, String> googleAppIdentityHeaders = {
    'X-Android-Package': 'ph.calamba.arangcada',
    'X-Android-Cert': androidCertSha1,
  };

  /// Per-service readiness. Each live integration degrades on its own rather
  /// than the whole app refusing to start, so a missing MapTiler key costs the
  /// map but not authentication.
  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get isMapTilerConfigured => mapTilerKey.isNotEmpty;

  static bool get isOrsConfigured => orsApiKey.isNotEmpty;

  static bool get isGoogleMapsConfigured => googleMapsApiKey.isNotEmpty;

  /// Google's terms allow Routes results only on a Google map, so the Routes
  /// key does nothing unless the Google map is on too.
  static bool get isGoogleRoutesConfigured =>
      googleRoutesApiKey.isNotEmpty && isGoogleMapsConfigured;

  /// Same rule as Routes: Places results may only appear with a Google map.
  static bool get isGooglePlacesConfigured =>
      googlePlacesApiKey.isNotEmpty && isGoogleMapsConfigured;

  /// True when every integration has a value. Never logs which one is absent
  /// at runtime beyond its name, and never a value.
  static bool get isFullyConfigured =>
      isSupabaseConfigured && isMapTilerConfigured && isOrsConfigured;

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
