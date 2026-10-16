/// "600 m", "1 km", "1.5 km".
String formatMeters(int meters) {
  if (meters < 1000) return '$meters m';
  final km = meters / 1000;
  return '${km == km.roundToDouble() ? km.round() : km.toStringAsFixed(1)} km';
}
