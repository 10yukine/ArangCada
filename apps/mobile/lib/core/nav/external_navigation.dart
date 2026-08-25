import 'package:url_launcher/url_launcher.dart';

import '../geo/haversine.dart';

/// Hands off turn-by-turn navigation to whatever maps app is already
/// installed on the device (Google Maps, Waze, etc.) instead of building
/// in-app turn-by-turn navigation.
///
/// This is deliberately the same trade-off a competitor ride-hailing app
/// makes: routing/ETA preview stays on ORS inside ArangCada, but the actual
/// drive is handed to a dedicated navigation app the driver already trusts.
/// No API key, no new account, and no recurring cost -- `geo:` is a
/// standard Android intent scheme resolved by the OS, not a Google service.
///
/// Returns `true` if an external app accepted the intent.
Future<bool> openExternalNavigation(
  GeoCoordinate destination, {
  String? label,
}) {
  final query = Uri.encodeComponent(
    label == null || label.isEmpty
        ? '${destination.latitude},${destination.longitude}'
        : '${destination.latitude},${destination.longitude}($label)',
  );
  final uri = Uri.parse(
    'geo:${destination.latitude},${destination.longitude}?q=$query',
  );
  return launchUrl(uri, mode: LaunchMode.externalApplication);
}
