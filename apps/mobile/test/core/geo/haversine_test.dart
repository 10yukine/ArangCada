import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/demo/demo_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same coordinate has zero distance', () {
    expect(
      haversineDistanceMeters(
        DemoData.calambaCrossing.coordinate,
        DemoData.calambaCrossing.coordinate,
      ),
      closeTo(0, 0.000001),
    );
  });

  test('seeded NU Laguna route demonstrates a 3-6 km fare band', () {
    final nuLaguna = DemoData.places.firstWhere(
      (place) => place.id == 'nu-laguna',
    );
    final distance = haversineDistanceMeters(
      DemoData.calambaCrossing.coordinate,
      nuLaguna.coordinate,
    );
    expect(distance, inInclusiveRange(3000, 6000));
  });
}
