enum WalletTransactionKind { topUp, ridePayment, refund }

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.title,
    required this.amountCentavos,
    required this.occurredAt,
    required this.kind,
    required this.status,
  });

  final String id;
  final String title;
  final int amountCentavos;
  final DateTime occurredAt;
  final WalletTransactionKind kind;
  final String status;
}
