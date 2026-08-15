import '../../domain/models/wallet_transaction.dart';
import '../repositories/wallet_repository.dart';
import 'demo_state.dart';

class MockWalletRepository implements WalletRepository {
  MockWalletRepository(this._state);

  final DemoState _state;

  @override
  int get balanceCentavos => _state.walletBalanceCentavos;

  @override
  List<WalletTransaction> get transactions => _state.walletTransactions;

  @override
  Future<WalletTransaction> topUp(int amountCentavos) async {
    if (amountCentavos <= 0) {
      throw ArgumentError.value(amountCentavos, 'amountCentavos');
    }
    return _state.addWalletTopUp(amountCentavos);
  }
}
