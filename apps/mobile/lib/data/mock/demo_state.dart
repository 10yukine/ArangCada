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

  int walletBalanceCentavos = 35000;
  DemoPlace pickup = DemoData.calambaCrossing;
  DemoPlace? destination;
  int passengerCount = 1;
  UserFareClass userFareClass = UserFareClass.regular;
  DemoBooking? activeBooking;
  bool demoSafetyAlertRecorded = false;
  final DriverTripStateMachine driverTrip = DriverTripStateMachine();
  final List<WalletTransaction> _walletTransactions = [
    WalletTransaction(
      id: 'DEMO-TOPUP-20260812-001',
      title: 'Demo balance top-up',
      amountCentavos: 50000,
      occurredAt: DateTime.utc(2026, 8, 12, 9, 30),
      kind: WalletTransactionKind.topUp,
      status: 'Simulated',
    ),
    WalletTransaction(
      id: 'DEMO-RIDE-20260813-024',
      title: 'Ride to SM City Calamba',
      amountCentavos: -15000,
      occurredAt: DateTime.utc(2026, 8, 13, 17, 10),
      kind: WalletTransactionKind.ridePayment,
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
    notifyListeners();
  }

  void bookingChanged() => notifyListeners();

  void setWalletBalanceForDemo(int amountCentavos) {
    if (amountCentavos < 0) throw ArgumentError.value(amountCentavos);
    walletBalanceCentavos = amountCentavos;
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
      status: 'Simulated',
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
    driverTrip.reset();
    notifyListeners();
  }
}
