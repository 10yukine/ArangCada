import '../../domain/models/booking.dart';
import '../repositories/payment_repository.dart';
import 'demo_state.dart';

class MockPaymentRepository implements PaymentRepository {
  MockPaymentRepository(this._state);

  final DemoState _state;

  @override
  void ensureCanConfirm(DemoBooking booking) {
    if (booking.paymentMethod == PaymentMethod.digital &&
        _state.walletBalanceCentavos < booking.fareQuote.partyTotalCentavos) {
      throw InsufficientBalanceException(
        availableCentavos: _state.walletBalanceCentavos,
        requiredCentavos: booking.fareQuote.partyTotalCentavos,
      );
    }
  }

  @override
  Future<void> completeRidePayment(DemoBooking booking) async {
    if (booking.paymentMethod == PaymentMethod.cash) return;
    ensureCanConfirm(booking);
    _state.debitRidePayment(
      booking.fareQuote.partyTotalCentavos,
      booking.destinationName,
    );
  }
}
