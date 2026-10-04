import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_build.dart';

/// Set when the server says this build is too old to keep using. While set,
/// the only screen is /update-required.
final updateRequired = ValueNotifier<bool>(false);

/// Which services the owner has chosen (get_mobile_settings, 20261002150000).
/// routing: 'google', or 'ors' / 'ors_only' (the same thing now: no Google at
/// all, see [useGoogleStack]). search: 'google' | 'maptiler'.
/// Google bills per request; the other values are how it is switched off.
final serviceChoices = ValueNotifier<({String routing, String search})>((
  routing: 'google',
  search: 'google',
));

/// Whether the Google map, Google Places and Google Routes are in use. They
/// are used together or not at all: Google's terms keep its content off other
/// maps and other map services' content off its map. Any routing choice other
/// than 'google' selects MapLibre, MapTiler search and openrouteservice.
// ponytail: read when a map or request starts; a map already on screen keeps
// its renderer and matching router until a new map is opened. No automatic
// switch when Google's quota
// runs out (the route line is simply absent); add one if the cap is hit.
bool get useGoogleStack => serviceChoices.value.routing == 'google';

/// Asks the server for the oldest build it still accepts and which services
/// to use. Called at start and whenever the app returns to the foreground.
///
/// The APK is installed by hand, so nothing else can retire an old build
/// before a server change that would break it. Fails open: an app that cannot
/// ask keeps working with what it last knew.
Future<void> loadMobileSettings(SupabaseClient client) async {
  try {
    final settings = await client
        .rpc('get_mobile_settings')
        .timeout(const Duration(seconds: 10));
    if (settings is! Map) return;
    final minimum = settings['min_mobile_build'];
    if (minimum is int) updateRequired.value = minimum > appBuild;
    final routing = settings['routing'];
    final search = settings['search'];
    if (routing is String && search is String) {
      serviceChoices.value = (routing: routing, search: search);
    }
  } catch (_) {
    // Offline, or a server that does not have the function yet.
  }
}
