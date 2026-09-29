import 'app_config.dart';

/// MapTiler style URL builder for MapLibre.
///
/// Config only -- no map widget lives here yet. Building the actual commuter
/// map screen is a separate, tests-first spec.
///
/// SECURITY.md: MapTiler receives only the tile/style requests needed to draw
/// the map. This helper does not attach coordinates, ride IDs, or any user
/// data -- callers are responsible for keeping it that way.
class MapStyle {
  const MapStyle._();

  /// MapTiler's "streets" style, the default until a design decision picks
  /// something else. The key is a client-restricted, free-tier credential
  /// per SECURITY.md, not a secret on the level of a service role key.
  static String get streetsStyleUrl =>
      'https://api.maptiler.com/maps/streets-v2/style.json?key=${AppConfig.mapTilerKey}';
}
