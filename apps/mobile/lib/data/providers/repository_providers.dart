import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock/demo_state.dart';
import '../mock/mock_auth_repository.dart';
import '../mock/mock_fare_repository.dart';
import '../mock/mock_payment_repository.dart';
import '../mock/mock_safety_repository.dart';
import '../mock/mock_wallet_repository.dart';
import '../repositories/auth_repository.dart';
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
