import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock/demo_state.dart';
import '../remote/geolocator_location_repository.dart';
import '../remote/maptiler_geocoding_repository.dart';
import '../remote/openrouteservice_routing_repository.dart';
import '../mock/local_chat_repository.dart';
import '../mock/mock_auth_repository.dart';
import '../mock/mock_fare_repository.dart';
import '../mock/mock_payment_repository.dart';
import '../mock/mock_safety_repository.dart';
import '../mock/mock_wallet_repository.dart';
import '../repositories/auth_repository.dart';
import '../repositories/chat_repository.dart';
import '../repositories/geocoding_repository.dart';
import '../repositories/location_repository.dart';
import '../repositories/routing_repository.dart';
import '../repositories/fare_repository.dart';
import '../repositories/payment_repository.dart';
import '../repositories/safety_repository.dart';
import '../repositories/wallet_repository.dart';

final demoStateProvider = Provider<DemoState>((ref) {
  final state = DemoState();
  ref.onDispose(state.dispose);
  return state;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return MockAuthRepository(ref.watch(demoStateProvider));
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

/// Chat transport. Local-only today; a Supabase Realtime implementation
/// replaces this binding without touching any screen.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final repository = LocalChatRepository();
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
// These talk to real services. Everything above this line is simulated on the
// device. Keeping the split visible here is the point: it is the honest answer
// to "what actually works?" without having to read every screen.
// ---------------------------------------------------------------------------

/// Road geometry for display only. Its distance and duration must never reach
/// the fare calculator -- billing uses Haversine (see `domain/fare/`).
final routingRepositoryProvider = Provider<RoutingRepository>((ref) {
  final repository = OpenRouteServiceRoutingRepository();
  ref.onDispose(repository.dispose);
  return repository;
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
