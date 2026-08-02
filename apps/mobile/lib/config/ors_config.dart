import 'app_config.dart';

/// openrouteservice (HeiGIT) endpoint configuration.
///
/// Constants only -- no HTTP client, no route-lookup logic. A real
/// route-preview call belongs to its own tests-first spec, since it feeds
/// distance data that is fare-adjacent (CLAUDE.md rule 7: final fare stays
/// trusted server-side; a client-side route preview must not become a second
/// source of truth for billed distance).
///
/// SECURITY.md: openrouteservice receives only the coordinates needed for the
/// current route lookup -- never names, phone numbers, ride IDs, or document
/// URLs. Enforce that in whatever client is built against these constants.
class OrsConfig {
  const OrsConfig._();

  static const String baseUrl = 'https://api.openrouteservice.org';

  static String get apiKey => AppConfig.orsApiKey;
}
