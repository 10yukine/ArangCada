String formatCentavos(int centavos) {
  final sign = centavos < 0 ? '-' : '';
  final absolute = centavos.abs();
  final pesos = absolute ~/ 100;
  final remainder = absolute % 100;
  return '$sign₱$pesos.${remainder.toString().padLeft(2, '0')}';
}
