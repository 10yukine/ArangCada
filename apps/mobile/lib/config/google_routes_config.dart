import 'app_config.dart';

/// Google Routes API (v2) configuration.
///
/// This is the CURRENT Google routing product -- `routes.googleapis.com`,
/// not the legacy `maps.googleapis.com/maps/api/directions` endpoint, which
/// Google itself now steers new integrations away from.
///
/// SCOPE: drawing the route only. Nothing from this API reaches the fare
/// calculator -- billing stays Haversine + the Ordinance 743 matrix
/// (`domain/fare/`). This constant file changes NOTHING about that boundary;
/// only `GoogleRoutesRoutingRepository` exists to feed the same
/// display-only `RoutingRepository` contract that ORS already implements.
///
/// COST CONTROL AND TERMS: the field mask below requests only
/// `polyline.encodedPolyline`. Google's terms let the app keep a route's
/// coordinates (the repository reuses them for 30 minutes) and nothing else
/// from it; distance and duration were requested once, never shown, and kept
/// in that cache. Routes API also bills by which response fields you ask
/// for -- this field keeps every call on the cheapest "Routes Essentials"
/// SKU. Do not add fields
/// (e.g. traffic-aware duration, multiple route alternatives) without
/// checking https://developers.google.com/maps/billing-and-pricing/pricing
/// first, since several fields silently upgrade the whole request to a more
/// expensive SKU.
///
/// SECURITY.md: only the two coordinates needed for the current route lookup
/// are ever sent -- never names, ride IDs, or document URLs. The key travels
/// as the `X-Goog-Api-Key` header, never in a query string.
class GoogleRoutesConfig {
  const GoogleRoutesConfig._();

  static const String baseUrl = 'https://routes.googleapis.com';

  /// Restricts the response to the cheapest billable SKU. See the class doc
  /// before changing this.
  static const String fieldMask = 'routes.polyline.encodedPolyline';

  /// DRIVE is used rather than TWO_WHEELER. The Philippines does support
  /// TWO_WHEELER (checked 2026-09-30), but two-wheeled routing is billed as
  /// Compute Routes Enterprise ($15/1000, 1,000 free a month) instead of
  /// Essentials ($5/1000, 10,000 free). Tolled expressways are excluded with
  /// `routeModifiers.avoidTolls` instead, which keeps Essentials pricing.
  /// Otherwise DRIVE follows the same road network a tricycle uses and,
  /// unlike ORS, Google's road graph has far better unnamed-road/alley/
  /// barangay-road coverage in Calamba, which is the whole reason this
  /// integration exists.
  static const String travelMode = 'DRIVE';

  static String get apiKey => AppConfig.googleRoutesApiKey;

  static bool get isConfigured => apiKey.isNotEmpty;
}
