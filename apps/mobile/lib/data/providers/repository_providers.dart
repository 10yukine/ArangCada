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

// supabase_flutter persists a session and restores it on the next cold start,
// which is the correct behaviour for a real user -- nobody wants to log into a
// ride-hailing app every time they open it, least of all a driver starting a
// shift outdoors on a low-end handset.
//
// This used to be suppressed wholesale by an AUTO_SIGN_OUT_ON_COLD_START
// constant, because a phone used to exercise one QA identity (the SJVTODA
// driver account, say) silently auto-signed back into that SAME account every
// launch, and switching identities meant remembering to sign out first. That
// was a real problem, but the blanket fix charged its cost to every real user.
//
// The accounts it was written for are already marked, server-side, by
// profiles.is_internal_tester -- so only those sessions are discarded now.
//
// Note the gate is NOT DemoUser.isDemoAccount. The @arangcada.demo accounts
// authenticate through MockAuthRepository and hold no Supabase session at all,
// so gating on them would restore nothing and discard nothing.

final demoStateProvider = Provider<DemoState>((ref) {
  final client = _supabaseClient();
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
    // Checked BEFORE restoreProfile, not after. restoreProfile() calls
    // setCurrentUser() itself, which fires the router's refreshListenable --
    // so deciding afterwards would redirect to the role home, then null the
    // user and redirect back to /login, flashing a screen the tester never
    // asked for on every launch.
    //
    // is_internal_tester is read from profiles under the existing owner-select
    // policy. It is not self-service: the privilege guard stops an ordinary
    // account granting itself the flag, so this cannot be flipped from the
    // client to change which branch runs.
    final flags = await client
        .from('profiles')
        .select('is_internal_tester')
        .eq('id', user.id)
        .maybeSingle();

    if (flags?['is_internal_tester'] == true) {
      await client.auth.signOut();
      state.setCurrentUser(null);
      return;
    }

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
