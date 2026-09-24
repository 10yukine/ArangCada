import 'package:flutter/foundation.dart';

import '../../demo/demo_data.dart';
import '../../core/geo/haversine.dart';
import '../../domain/fare/fare_matrix.dart';
import '../../domain/models/booking.dart';
import '../../domain/models/demo_user.dart';
import '../../domain/models/wallet_transaction.dart';
import '../../domain/state/driver_trip_state_machine.dart';

/// The single mutable state holder shared by every demo repository.
///
/// Separate repository interfaces remain replaceable, while their mock
/// implementations cannot drift into contradictory sessions or balances.
class DemoState extends ChangeNotifier {
  DemoState({DemoUser? initialUser}) : _currentUser = initialUser;

  DemoUser? get currentUser => _currentUser;

  DemoUser? _currentUser;

  int walletBalanceCentavos = 0;
  DemoPlace pickup = DemoData.calambaCrossing;
  bool hasPickup = false;
  DemoPlace? destination;
  int passengerCount = 1;

  /// Which ride the commuter has selected on the ride-options sheet.
  RideType selectedRideType = RideType.special;
  UserFareClass userFareClass = UserFareClass.regular;
  DemoBooking? activeBooking;
  bool demoSafetyAlertRecorded = false;
  bool forceNoDriversAvailable = false;
  bool forcePaymentFailure = false;
  bool forceEtaFallback = false;
  bool paymentFallbackToCash = false;
  int? tripRating;
  String? tripRatingComment;
  int? driverTripRating;
  String? driverTripRatingComment;
  String? liveTripId;
  String? liveDriverName;
  String? liveCommuterName;
  String? liveTodaName;
  // The OTHER party's photo, from the caller's own point of view -- a
  // commuter reads their driver's, a driver reads their rider's. Populated
  // asynchronously via trip_counterpart_avatar_path() once the trip is
  // matched (see SupabaseRideRepository._applyTrip); null both before that
  // resolves and whenever there is honestly nothing to show (no photo
  // uploaded, or the trip has ended -- see that RPC's own scoping).
  String? liveCounterpartAvatarUrl;
  GeoCoordinate? liveDriverLocation;
  DateTime? completionAvailableAt;
  bool driverFeedbackPending = false;
  String? pendingFeedbackTripId;
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
    if (_currentUser?.email != user?.email) {
      pickup = DemoData.calambaCrossing;
      hasPickup = false;
    }
    _currentUser = user;
    // driverFeedbackPending is per-account server state (set only by
    // SupabaseRideRepository.refreshFeedbackState()). Leaving a stale true
    // from a previous account's session was a real bug: switching to any
    // other driver -- including a local sandbox account, which has no live
    // repository to ever clear it -- force-redirected into the mandatory,
    // unpoppable feedback screen with a Submit button that could only
    // silently no-op, permanently stranding that account. The live
    // repository re-populates this immediately after sign-in if it is
    // genuinely still pending for the new account.
    driverFeedbackPending = false;
    pendingFeedbackTripId = null;
    notifyListeners();
  }

  /// Sets the booking origin. The fare engine reads [pickup], so a screen
  /// that merely *labels* a GPS fix without calling this would price the ride
  /// from a different point than the one shown to the commuter.
  void setPickup(DemoPlace place) {
    pickup = place;
    hasPickup = true;
    notifyListeners();
  }

  void setDestination(DemoPlace place) {
    destination = place;
    notifyListeners();
  }

  void setSelectedRideType(RideType value) {
    if (selectedRideType == value) return;
    selectedRideType = value;
    // Special seats at most 3, so a party of 4 cannot carry over silently.
    if (value == RideType.special && passengerCount > 3) passengerCount = 3;
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

  /// Mirrors [submitTripRating] for the driver rating the passenger. A
  /// separate field because the driver side has no [DemoBooking] -- it runs
  /// entirely on [DriverTripStateMachine].
  void submitDriverTripRating(int stars, String? comment) {
    if (driverTrip.status != DriverTripStatus.completed) {
      throw StateError('A completed trip is required before rating.');
    }
    if (driverTripRating != null) {
      throw StateError('This demo trip has already been rated.');
    }
    if (stars < 1 || stars > 5) throw ArgumentError.value(stars);
    driverTripRating = stars;
    final trimmed = comment?.trim();
    driverTripRatingComment = trimmed == null || trimmed.isEmpty
        ? null
        : trimmed;
    notifyListeners();
  }

  /// Clears a mandatory-feedback gate that has no live repository to answer
  /// it (a local sandbox/demo session). See setCurrentUser() for how this
  /// flag is meant to be scoped per-account, and driver_app_feedback_screen
  /// for the stuck-screen case this exists to escape.
  void clearDriverFeedbackPending() {
    driverFeedbackPending = false;
    pendingFeedbackTripId = null;
    notifyListeners();
  }

  /// Rating is over; the driver returns to available and this trip's rating
  /// state clears so the next trip starts fresh.
  void finishDriverTrip() {
    driverTrip.finishTrip();
    driverTripRating = null;
    driverTripRatingComment = null;
    liveTripId = null;
    liveDriverName = null;
    liveCommuterName = null;
    liveTodaName = null;
    liveCounterpartAvatarUrl = null;
    liveDriverLocation = null;
    completionAvailableAt = null;
    driverFeedbackPending = false;
    pendingFeedbackTripId = null;
    notifyListeners();
  }

  WalletTransaction addWalletTopUp(int amountCentavos) {
    walletBalanceCentavos += amountCentavos;
    final transaction = WalletTransaction(
      id: 'SBX-TOPUP-20260815-${(_walletTransactions.length + 1).toString().padLeft(3, '0')}',
      title: 'Balance top-up',
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
      throw StateError('Insufficient sandbox balance.');
    }
    walletBalanceCentavos -= amountCentavos;
    _walletTransactions.insert(
      0,
      WalletTransaction(
        id: 'SBX-RIDE-20260815-${(_walletTransactions.length + 1).toString().padLeft(3, '0')}',
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
    walletBalanceCentavos = 0;
    pickup = DemoData.calambaCrossing;
    hasPickup = false;
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
    driverTripRating = null;
    driverTripRatingComment = null;
    liveTripId = null;
    liveDriverName = null;
    liveCommuterName = null;
    liveTodaName = null;
    liveCounterpartAvatarUrl = null;
    liveDriverLocation = null;
    completionAvailableAt = null;
    driverFeedbackPending = false;
    pendingFeedbackTripId = null;
    sampleContentEnabled = false;
    _walletTransactions.clear();
    driverTrip.reset();
    notifyListeners();
  }
}
