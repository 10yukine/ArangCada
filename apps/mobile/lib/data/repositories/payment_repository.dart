import '../../domain/models/booking.dart';

class InsufficientBalanceException implements Exception {
  const InsufficientBalanceException({
    required this.availableCentavos,
    required this.requiredCentavos,
  });

  final int availableCentavos;
  final int requiredCentavos;
  int get shortfallCentavos => requiredCentavos - availableCentavos;
}

abstract interface class PaymentRepository {
  void ensureCanConfirm(DemoBooking booking);

  Future<void> completeRidePayment(DemoBooking booking);
}
