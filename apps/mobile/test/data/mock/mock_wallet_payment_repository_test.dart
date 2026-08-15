import 'package:arangcada/data/mock/demo_state.dart';
import 'package:arangcada/data/mock/mock_payment_repository.dart';
import 'package:arangcada/data/mock/mock_wallet_repository.dart';
import 'package:arangcada/data/repositories/payment_repository.dart';
import 'package:arangcada/domain/fare/fare_calculator.dart';
import 'package:arangcada/domain/fare/fare_matrix.dart';
import 'package:arangcada/domain/models/booking.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DemoBooking digitalBooking(int fareCentavos) => DemoBooking.draft(
    pickupName: 'Pickup',
    destinationName: 'Destination',
    rideType: RideType.special,
    passengerCount: 1,
    userFareClass: UserFareClass.regular,
    paymentMethod: PaymentMethod.digital,
    fareQuote: FareQuote(
      unitFareCentavos: fareCentavos,
      partyTotalCentavos: fareCentavos,
      farePerPassengerCentavos: null,
      baseFareCentavos: fareCentavos,
      additionalDistanceCentavos: 0,
      distanceMeters: 1000,
      chargeableKm: 2,
      rideType: RideType.special,
      passengerCount: 1,
      discountClass: DiscountClass.full,
      fareMatrixVersion: 'test',
      createdAt: DateTime.utc(2026, 8, 15),
    ),
  );

  test('wallet top-up increases balance', () async {
    final state = DemoState();
    final wallet = MockWalletRepository(state);

    await wallet.topUp(10000);

    expect(wallet.balanceCentavos, 45000);
  });

  test('digital ride payment decreases balance at completion', () async {
    final state = DemoState();
    final payment = MockPaymentRepository(state);

    await payment.completeRidePayment(digitalBooking(6000));

    expect(state.walletBalanceCentavos, 29000);
  });

  test('insufficient balance blocks charge and leaves balance untouched', () {
    final state = DemoState()..setWalletBalanceForDemo(5000);
    final payment = MockPaymentRepository(state);

    expect(
      () => payment.completeRidePayment(digitalBooking(6000)),
      throwsA(isA<InsufficientBalanceException>()),
    );
    expect(state.walletBalanceCentavos, 5000);
  });

  test('booking state survives the top-up detour intact', () async {
    final state = DemoState()..setWalletBalanceForDemo(5000);
    final booking = digitalBooking(6000);
    state.setActiveBooking(booking);

    await MockWalletRepository(state).topUp(10000);

    expect(state.activeBooking, same(booking));
    expect(state.activeBooking?.destinationName, 'Destination');
    expect(state.activeBooking?.fareQuote.partyTotalCentavos, 6000);
    expect(state.walletBalanceCentavos, 15000);
  });
}
