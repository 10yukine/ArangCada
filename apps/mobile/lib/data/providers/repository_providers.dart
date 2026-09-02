import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../mock/mock_payment_repository.dart';
import '../mock/mock_safety_repository.dart';
import '../mock/mock_wallet_repository.dart';
import '../repositories/auth_repository.dart';
import '../repositories/hybrid_auth_repository.dart';
import '../remote/supabase_auth_repository.dart';
import '../repositories/chat_repository.dart';
import '../repositories/geocoding_repository.dart';
import '../repositories/location_repository.dart';
import '../repositories/routing_repository.dart';
import '../repositories/fare_repository.dart';
import '../repositories/payment_repository.dart';
import '../repositories/safety_repository.dart';
import '../repositories/wallet_repository.dart';

SupabaseClient? _supabaseClient() {
  if (!AppConfig.isSupabaseConfigured) return null;
  try {
    return Supabase.instance.client;
  } catch (_) {
    return null;
  }
}

// TESTING-PHASE DECISION, deliberately reversible -- see
// docs/TECH_STACK_DECISIONS.md's migration-path entries for the established
// pattern this follows.
//
// supabase_flutter persists a session by default and restores it on the next
// cold start, which is the CORRECT behaviour for a real user -- nobody wants
// to log into a ride-hailing app every time they open it. It became a real
// problem the moment real accounts existed to test with: a physical device
// used to test one role (e.g. the SJVTODA driver account) silently
// auto-signs back into that SAME account on every subsequent launch, so
// switching which test identity a given phone exercises requires knowing to
// explicitly sign out first -- easy to forget mid-QA-session, and it looked
// indistinguishable from a bug ("why does this always log in as the same
// person") rather than the intended default it actually is.
//
// AUTO_SIGN_OUT_ON_COLD_START forces every launch to land on /login during
// this internal-testing phase. Flip it to false (or delete this block
// entirely) once real user-facing session persistence is wanted again --
// nothing else in the app depends on this flag.
const bool _autoSignOutOnColdStart = true;

final demoStateProvider = Provider<DemoState>((ref) {
  final client = _supabaseClient();
  if (_autoSignOutOnColdStart && client != null) {
    // Fire-and-forget: clearing the persisted session is best-effort and
    // must never block app startup on a network round trip.
    unawaited(client.auth.signOut());
    final state = DemoState();
    ref.onDispose(state.dispose);
    return state;
  }
  final remoteUser = client?.auth.currentUser;
  // Never construct a commuter shell from stale JWT metadata while a restored
  // driver session is waiting for its authoritative profiles row.
  final state = DemoState();
  if (client != null && remoteUser != null) {
    unawaited(_restoreTrustedProfile(client, state, remoteUser));
  }
  ref.onDispose(state.dispose);
  return state;
});

Future<void> _restoreTrustedProfile(
  SupabaseClient client,
  DemoState state,
  User user,
) async {
  try {
    await SupabaseAuthRepository(client, state).restoreProfile(user);
  } on Exception {
    state.setCurrentUser(null);
  }
}

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

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  return MockWalletRepository(ref.watch(demoStateProvider));
});

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return MockPaymentRepository(ref.watch(demoStateProvider));
});

final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  return MockSafetyRepository(ref.watch(demoStateProvider));
});

final liveRideRepositoryProvider = Provider<SupabaseRideRepository?>((ref) {
  final client = _supabaseClient();
  final state = ref.watch(demoStateProvider);
  final account = state.currentUser;
  if (client == null ||
      account == null ||
      account.isDemoAccount ||
      client.auth.currentUser?.email?.toLowerCase() !=
          account.email.toLowerCase()) {
    return null;
  }
  final repository = SupabaseRideRepository(
    client,
    state,
    ref.read(locationRepositoryProvider),
    ref.read(fareRepositoryProvider),
  );
  ref.onDispose(repository.dispose);
  return repository;
});

/// Real authenticated accounts share trip-scoped Realtime chat. Hidden local
/// demo accounts keep their existing isolated on-device walkthrough.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final rides = ref.watch(liveRideRepositoryProvider);
  if (rides == null) {
    final repository = LocalChatRepository();
    ref.onDispose(repository.dispose);
    return repository;
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
