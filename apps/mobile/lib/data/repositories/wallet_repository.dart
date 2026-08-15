import '../../domain/models/wallet_transaction.dart';

abstract interface class WalletRepository {
  int get balanceCentavos;
  List<WalletTransaction> get transactions;

  Future<WalletTransaction> topUp(int amountCentavos);
}
