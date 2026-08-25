import 'app_config.dart';

/// openrouteservice (HeiGIT) endpoint configuration.
///
/// HOST: `api.openrouteservice.org` is the current, correct API host, and was
/// verified rather than assumed. A migration to a `*.heigit.org` API host was
/// investigated on 15 Aug 2026 and does not exist:
///
///   api.openrouteservice.heigit.org   DNS does not resolve
///   ors.heigit.org / api.ors.heigit.org   DNS does not resolve
///   openrouteservice.heigit.org       301 -> heigit.org/smart-mobility/
///                                     (an information page, not an API)
///   api.openrouteservice.org          200/401 as expected, TLS verifies
///
/// Do not "migrate" this constant to a heigit.org hostname without re-checking
/// DNS first; doing so silently disables routing and leaves every road route
/// unavailable.
///
/// PLAN: the project's key belongs to HeiGIT's Collaborative plan, granted for
/// NON-COMMERCIAL academic use. Request discipline is a condition of that
/// grant, not an optimisation -- see [OpenRouteServiceRoutingRepository].
///
/// SECURITY.md: openrouteservice receives only the coordinates needed for the
/// current route lookup -- never names, phone numbers, ride IDs, or document
/// URLs. The key is sent as an Authorization header, never in a query string.
class OrsConfig {
  const OrsConfig._();

  static const String baseUrl = 'https://api.openrouteservice.org';

  /// Tricycles are not a distinct ORS profile. `driving-car` follows the same
  /// road network and one-way rules, which is the closest available match for
  /// a Calamba tricycle route. Revisit if ORS adds a suitable profile.
  static const String profile = 'driving-car';

  static String get apiKey => AppConfig.orsApiKey;

  static bool get isConfigured => apiKey.isNotEmpty;
}
