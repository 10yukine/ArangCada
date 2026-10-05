import 'dart:io';

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
        'Barangay Real': GeoCoordinate(latitude: 14.2300, longitude: 121.1500),
      };
      for (final entry in inside.entries) {
        expect(
          ServiceArea.contains(entry.value),
          isTrue,
          reason: '${entry.key} must be inside the service area',
        );
      }
    });

    test('is the same outline the server holds', () {
      final sql = File(
        '../../supabase/pilot/20260930_bjmp_toda_zone.sql',
      ).readAsStringSync();
      final ring = RegExp(
        r'POLYGON\(\((.*?)\)\)',
        dotAll: true,
      ).firstMatch(sql)!.group(1)!;
      final server = [
        for (final pair in ring.split(',')) pair.trim().split(RegExp(r'\s+')),
      ];
      // The file repeats its first point to close the ring.
      expect(server.length, ServiceArea.boundary.length + 1);
      for (var i = 0; i < ServiceArea.boundary.length; i++) {
        expect(
          [ServiceArea.boundary[i].longitude, ServiceArea.boundary[i].latitude],
          [double.parse(server[i][0]), double.parse(server[i][1])],
          reason: 'point $i',
        );
      }
    });

    test('follows the city limit where the old rough outline did not', () {
      // Upland Canlubang, which the old outline refused.
      expect(
        ServiceArea.contains(
          const GeoCoordinate(latitude: 14.1721, longitude: 121.0416),
        ),
        isTrue,
      );
      // Malitlit in Santa Rosa and Los Banos, which it let through.
      expect(
        ServiceArea.contains(
          const GeoCoordinate(latitude: 14.2465, longitude: 121.1107),
        ),
        isFalse,
      );
      expect(
        ServiceArea.contains(
          const GeoCoordinate(latitude: 14.1820, longitude: 121.2214),
        ),
        isFalse,
      );
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

    test('Cabuyao remains an explicitly enabled developer-only exception', () {
      const cabuyao = GeoCoordinate(latitude: 14.3100, longitude: 121.1250);
      const calamba = GeoCoordinate(latitude: 14.2116, longitude: 121.1652);

      expect(ServiceArea.contains(cabuyao), isFalse);
      expect(
        ServiceArea.contains(cabuyao, allowCabuyaoTestException: true),
        isTrue,
      );
      expect(
        ServiceArea.rejectionReason(
          pickup: cabuyao,
          destination: calamba,
          allowCabuyaoTestException: true,
        ),
        isNull,
      );
    });
  });
}
