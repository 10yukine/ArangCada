import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_config.dart';
import '../mock/demo_state.dart';
import '../remote/geolocator_location_repository.dart';
import '../remote/maptiler_geocoding_repository.dart';
import '../remote/openrouteservice_routing_repository.dart';
import '../remote/google_routes_routing_repository.dart';
import '../remote/fallback_routing_repository.dart';
import '../remote/supabase_chat_repository.dart';
import '../remote/supabase_ride_repository.dart';
import '../mock/local_chat_repository.dart';
import '../mock/mock_fare_repository.dart';
import '../mock/mock_safety_repository.dart';
import '../remote/hive_notifications_repository.dart';
import '../repositories/auth_repository.dart';
import '../repositories/hybrid_auth_repository.dart';
import '../remote/supabase_auth_repository.dart';
import '../repositories/chat_repository.dart';
import '../repositories/geocoding_repository.dart';
import '../repositories/location_repository.dart';
import '../repositories/notifications_repository.dart';
import '../repositories/routing_repository.dart';
import '../repositories/fare_repository.dart';
import '../repositories/safety_repository.dart';
import '../repositories/saved_places_repository.dart';
import '../repositories/driver_documents_repository.dart';
import '../remote/supabase_driver_documents_repository.dart';

final driverDocumentsRepositoryProvider =
    Provider.autoDispose<DriverDocumentsRepository?>((ref) {
      final user = ref.watch(demoStateProvider).currentUser;
      final client = _supabaseClient();
      if (user == null || user.isDemoAccount || client == null) return null;
      final transport = http.Client();
      ref.onDispose(transport.close);
      return SupabaseDriverDocumentsRepository(client, transport);
    });

final savedPlacesRepositoryProvider =
    Provider.autoDispose<SavedPlacesRepository>((ref) {
      final user = ref.watch(demoStateProvider).currentUser;
      final accountId = user == null
          ? null
          : user.isDemoAccount
          ? 'demo:${user.email}'
          : _supabaseClient()?.auth.currentUser?.id;
      return SavedPlacesRepository(
        Hive.isBoxOpen('arangcada_demo')
            ? Hive.box<String>('arangcada_demo')
            : null,
        accountId,
      );
    });

SupabaseClient? _supabaseClient() {
  if (!AppConfig.isSupabaseConfigured) return null;
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

final demoStateProvider = Provider<DemoState>((ref) {
  // Never construct a commuter shell from stale JWT metadata while a restored
  // driver session is waiting for its authoritative profiles row.
  final state = DemoState();
  ref.onDispose(state.dispose);
  return state;
});

/// Routing waits for the authoritative profile before choosing a role's shell.
/// A network failure stays recoverable on the splash; it is not a sign-out.
final sessionRestorationProvider = FutureProvider<void>((ref) async {
  final state = ref.read(demoStateProvider);
  final client = _supabaseClient();
  final user = client?.auth.currentUser;
  if (client == null || user == null || state.currentUser != null) return;
  await SupabaseAuthRepository(client, state).restoreProfile(user);
}, retry: (_, _) => null);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final state = ref.watch(demoStateProvider);
  final client = _supabaseClient();
  return HybridAuthRepository(
    state: state,
    live: client == null ? null : SupabaseAuthRepository(client, state),
  );
});

final fareRepositoryProvider = Provider<FareRepository>((ref) {
  return const MockFareRepository();
});

final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  return MockSafetyRepository(ref.watch(demoStateProvider));
});

/// Real for every account, demo or not -- unlike ride/chat/safety, a
/// notification history has no per-account server state to fake; it is
/// just whatever this device has actually received, which is equally real
/// (or equally empty) either way.
final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return const HiveNotificationsRepository();
});

final liveRideRepositoryProvider = Provider<SupabaseRideRepository?>((ref) {
  final client = _supabaseClient();
  final account = ref.watch(demoStateProvider.select((s) => s.currentUser));
  if (client == null ||
      account == null ||
      account.isDemoAccount ||
      client.auth.currentUser?.email?.toLowerCase() !=
          account.email.toLowerCase()) {
    return null;
  }
  final repository = SupabaseRideRepository(
    client,
    ref.read(demoStateProvider),
    ref.read(locationRepositoryProvider),
    ref.read(fareRepositoryProvider),
    geocoding: ref.read(geocodingRepositoryProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

final localChatRepositoryProvider = Provider<LocalChatRepository>((ref) {
  final sampleEnabled = ref.watch(
    demoStateProvider.select((s) => s.sampleContentEnabled),
  );
  final repository = LocalChatRepository(sampleContent: sampleEnabled);
  ref.onDispose(repository.dispose);
  return repository;
});

/// Real authenticated accounts share trip-scoped Realtime chat. Hidden local
/// demo accounts keep their existing isolated on-device walkthrough.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final rides = ref.watch(liveRideRepositoryProvider);
  if (rides == null) {
    return ref.watch(localChatRepositoryProvider);
  }
  final repository = SupabaseChatRepository(_supabaseClient()!, rides);
  ref.onDispose(repository.dispose);
  return repository;
});

/// Unread badge source for the Chat tab.
final chatUnreadCountProvider = Provider<int>((ref) {
  final repository = ref.watch(chatRepositoryProvider);
  return repository.totalUnread;
});

// ---------------------------------------------------------------------------
// Live integrations.
//
// These provider-neutral map/location services work for both connected and
// explicit local-demo accounts.
// ---------------------------------------------------------------------------

/// Road geometry for display only. Its distance and duration must never reach
/// the fare calculator -- billing uses Haversine (see `domain/fare/`).
///
/// Google Routes is preferred when configured (better unnamed/barangay-road
/// coverage than ORS in Calamba), with openrouteservice as the automatic
/// fallback -- never the other way around, and never both queried for a
/// route the primary already answered. With no Google key configured, this
/// is exactly the previous ORS-only behavior.
final routingRepositoryProvider = Provider<RoutingRepository>((ref) {
  final ors = OpenRouteServiceRoutingRepository();
  ref.onDispose(ors.dispose);
  if (!AppConfig.isGoogleRoutesConfigured) return ors;

  final google = GoogleRoutesRoutingRepository();
  ref.onDispose(google.dispose);
  return FallbackRoutingRepository(primary: google, secondary: ors);
});

/// MapTiler forward/reverse geocoding for destination search and pin-on-map.
final geocodingRepositoryProvider = Provider<GeocodingRepository>((ref) {
  final repository = MapTilerGeocodingRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

/// Device GPS. While-in-use only.
final locationRepositoryProvider = Provider<LocationRepository>((ref) {
  return const GeolocatorLocationRepository();
});
