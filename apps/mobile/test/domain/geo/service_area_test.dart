import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/domain/geo/service_area.dart';
import 'package:flutter_test/flutter_test.dart';

/// A wrong boundary silently refuses legitimate rides, which is worse than a
/// slightly generous one. These pin the landmarks the app actually ships.
void main() {
  group('ServiceArea', () {
    test('accepts Calamba landmarks', () {
      const inside = <String, GeoCoordinate>{
        'Calamba Crossing Terminal': GeoCoordinate(
          latitude: 14.2116,
          longitude: 121.1652,
        ),
        'Calamba City Hall': GeoCoordinate(
          latitude: 14.2117,
          longitude: 121.1653,
        ),
        'Rizal Shrine': GeoCoordinate(latitude: 14.2109, longitude: 121.1631),
        'Calamba Poblacion': GeoCoordinate(
          latitude: 14.2000,
          longitude: 121.1600,
        ),
        'Barangay Real': GeoCoordinate(
          latitude: 14.2300,
          longitude: 121.1500,
        ),
      };
      for (final entry in inside.entries) {
        expect(
          ServiceArea.contains(entry.value),
          isTrue,
          reason: '${entry.key} must be inside the service area',
        );
      }
    });

    test('rejects places well outside Calamba', () {
      const outside = <String, GeoCoordinate>{
        'Manila': GeoCoordinate(latitude: 14.5995, longitude: 120.9842),
        'Dasmarinas, Cavite': GeoCoordinate(
          latitude: 14.3294,
          longitude: 120.9367,
        ),
        'Lucena': GeoCoordinate(latitude: 13.9314, longitude: 121.6170),
      };
      for (final entry in outside.entries) {
        expect(
          ServiceArea.contains(entry.value),
          isFalse,
          reason: '${entry.key} must be outside the service area',
        );
      }
    });

    test('reports which endpoint is out of area', () {
      const calamba = GeoCoordinate(latitude: 14.2116, longitude: 121.1652);
      const manila = GeoCoordinate(latitude: 14.5995, longitude: 120.9842);

      expect(
        ServiceArea.rejectionReason(pickup: calamba, destination: calamba),
        isNull,
      );
      expect(
        ServiceArea.rejectionReason(pickup: calamba, destination: manila),
        contains('destination'),
      );
      expect(
        ServiceArea.rejectionReason(pickup: manila, destination: calamba),
        contains('pickup'),
      );
    });
  });
}
