import 'package:flutter/foundation.dart';

import '../../demo/demo_data.dart';
import '../../domain/models/booking.dart';
import '../../domain/models/demo_user.dart';
import '../../domain/models/wallet_transaction.dart';
import '../../domain/state/driver_trip_state_machine.dart';

/// The single mutable state holder shared by every demo repository.
///
/// Separate repository interfaces remain replaceable, while their mock
/// implementations cannot drift into contradictory sessions or balances.
class DemoState extends ChangeNotifier {
  DemoUser? get currentUser => _currentUser;

  DemoUser? _currentUser;

  int walletBalanceCentavos = 0;
  DemoPlace pickup = DemoData.calambaCrossing;
  DemoPlace? destination;
  int passengerCount = 1;
  UserFareClass userFareClass = UserFareClass.regular;
  DemoBooking? activeBooking;
  bool demoSafetyAlertRecorded = false;
  bool forceNoDriversAvailable = false;
  bool forcePaymentFailure = false;
  bool forceEtaFallback = false;
  bool paymentFallbackToCash = false;
  int? tripRating;
  String? tripRatingComment;
  final DriverTripStateMachine driverTrip = DriverTripStateMachine();
  /// Sample content is OFF by default. Pre-populated chats and a pre-filled
  /// ledger read as things that actually happened, which is misleading on a
  /// first run. Demo Tools turns them on for a walkthrough.
  bool sampleContentEnabled = false;

  final List<WalletTransaction> _walletTransactions = [];

  static List<WalletTransaction> _seedTransactions() => [
    WalletTransaction(
      id: 'DEMO-TOPUP-20260815-001',
      title: 'Top Up',
      amountCentavos: 50000,
      occurredAt: DateTime.utc(2026, 8, 15, 9, 30),
      kind: WalletTransactionKind.topUp,
      status: 'Completed',
    ),
    WalletTransaction(
      id: 'DEMO-RIDE-20260815-024',
      title: 'Ride Payment',
      amountCentavos: -7600,
      occurredAt: DateTime.utc(2026, 8, 15, 8, 10),
      kind: WalletTransactionKind.ridePayment,
      status: 'Completed',
    ),
    WalletTransaction(
      id: 'DEMO-REFUND-20260815-001',
      title: 'Refund',
      amountCentavos: 1200,
      occurredAt: DateTime.utc(2026, 8, 14, 16, 45),
      kind: WalletTransactionKind.refund,
      status: 'Completed',
    ),
  ];

  List<WalletTransaction> get walletTransactions =>
      List.unmodifiable(_walletTransactions);

  void setCurrentUser(DemoUser? user) {
    if (identical(_currentUser, user)) return;
    _currentUser = user;
    notifyListeners();
  }

  /// Sets the booking origin. The fare engine reads [pickup], so a screen
  /// that merely *labels* a GPS fix without calling this would price the ride
  /// from a different point than the one shown to the commuter.
  void setPickup(DemoPlace place) {
    pickup = place;
    notifyListeners();
  }

  void setDestination(DemoPlace place) {
    destination = place;
    notifyListeners();
  }

  void setPassengerCount(int value) {
    if (passengerCount == value) return;
    passengerCount = value;
    notifyListeners();
  }

  void setUserFareClass(UserFareClass value) {
    if (userFareClass == value) return;
    userFareClass = value;
    notifyListeners();
  }

  void setActiveBooking(DemoBooking booking) {
    activeBooking = booking;
    tripRating = null;
    tripRatingComment = null;
    paymentFallbackToCash = false;
    notifyListeners();
  }

  void bookingChanged() => notifyListeners();

  /// Loads or clears the sample ledger. Balance follows suit so a cleared
  /// wallet does not show money with no transactions explaining it.
  void setSampleContent(bool enabled) {
    if (sampleContentEnabled == enabled) return;
    sampleContentEnabled = enabled;
    _walletTransactions.clear();
    if (enabled) {
      _walletTransactions.addAll(_seedTransactions());
      walletBalanceCentavos = 35000;
    } else {
      walletBalanceCentavos = 0;
    }
    notifyListeners();
  }

  void setWalletBalanceForDemo(int amountCentavos) {
    if (amountCentavos < 0) throw ArgumentError.value(amountCentavos);
    walletBalanceCentavos = amountCentavos;
    notifyListeners();
  }

  void setForceNoDriversAvailable(bool value) {
    forceNoDriversAvailable = value;
    notifyListeners();
  }

  void setForcePaymentFailure(bool value) {
    forcePaymentFailure = value;
    notifyListeners();
  }

  void setForceEtaFallback(bool value) {
    forceEtaFallback = value;
    notifyListeners();
  }

  void setPaymentFallbackToCash(bool value) {
    paymentFallbackToCash = value;
    notifyListeners();
  }

  void submitTripRating(int stars, String? comment) {
    if (activeBooking?.status != BookingStatus.completed) {
      throw StateError('A completed trip is required before rating.');
    }
    if (tripRating != null) {
      throw StateError('This demo trip has already been rated.');
    }
    if (stars < 1 || stars > 5) throw ArgumentError.value(stars);
    tripRating = stars;
    final trimmed = comment?.trim();
    tripRatingComment = trimmed == null || trimmed.isEmpty ? null : trimmed;
    notifyListeners();
  }

  WalletTransaction addWalletTopUp(int amountCentavos) {
    walletBalanceCentavos += amountCentavos;
    final transaction = WalletTransaction(
      id: 'DEMO-TOPUP-20260815-${(_walletTransactions.length + 1).toString().padLeft(3, '0')}',
      title: 'Demo balance top-up',
      amountCentavos: amountCentavos,
      occurredAt: DateTime.now().toUtc(),
      kind: WalletTransactionKind.topUp,
      status: 'Completed',
    );
    _walletTransactions.insert(0, transaction);
    notifyListeners();
    return transaction;
  }

  void debitRidePayment(int amountCentavos, String destinationName) {
    if (amountCentavos > walletBalanceCentavos) {
      throw StateError('Insufficient demo balance.');
    }
    walletBalanceCentavos -= amountCentavos;
    _walletTransactions.insert(
      0,
      WalletTransaction(
        id: 'DEMO-RIDE-20260815-${(_walletTransactions.length + 1).toString().padLeft(3, '0')}',
        title: 'Ride to $destinationName',
        amountCentavos: -amountCentavos,
        occurredAt: DateTime.now().toUtc(),
        kind: WalletTransactionKind.ridePayment,
        status: 'Completed',
      ),
    );
    notifyListeners();
  }

  void recordSafetyAlert() {
    demoSafetyAlertRecorded = true;
    notifyListeners();
  }

  void driverChanged() => notifyListeners();

  void reset() {
    _currentUser = null;
    walletBalanceCentavos = 35000;
    pickup = DemoData.calambaCrossing;
    destination = null;
    passengerCount = 1;
    userFareClass = UserFareClass.regular;
    activeBooking = null;
    demoSafetyAlertRecorded = false;
    forceNoDriversAvailable = false;
    forcePaymentFailure = false;
    forceEtaFallback = false;
    paymentFallbackToCash = false;
    tripRating = null;
    tripRatingComment = null;
    _walletTransactions
      ..clear()
      ..addAll(_seedTransactions());
    driverTrip.reset();
    notifyListeners();
  }
}
