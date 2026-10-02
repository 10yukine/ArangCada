import '../core/geo/haversine.dart';

class DemoPlace {
  const DemoPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.coordinate,
    this.googleRetrievedAt,
  });

  final String id;
  final String name;
  final String address;
  final GeoCoordinate coordinate;
  final DateTime? googleRetrievedAt;

  bool googleCoordinateIsFresh(DateTime now) =>
      !id.startsWith('google:') ||
      (googleRetrievedAt != null &&
          !now.isBefore(googleRetrievedAt!) &&
          now.difference(googleRetrievedAt!) < const Duration(hours: 1));
}

abstract final class DemoData {
  /// Mirrors the placeholder CAL-POB-01 seed geometry. It is intentionally
  /// rectangular and must never be presented as official LGU data.
  static const calambaPoblacionPrototypeBoundary = <GeoCoordinate>[
    GeoCoordinate(latitude: 14.200, longitude: 121.150),
    GeoCoordinate(latitude: 14.200, longitude: 121.180),
    GeoCoordinate(latitude: 14.230, longitude: 121.180),
    GeoCoordinate(latitude: 14.230, longitude: 121.150),
    GeoCoordinate(latitude: 14.200, longitude: 121.150),
  ];

  static const calambaCrossing = DemoPlace(
    id: 'calamba-crossing',
    name: 'Calamba Crossing Terminal',
    address: 'Crossing, Real, Calamba City',
    coordinate: GeoCoordinate(latitude: 14.2116, longitude: 121.1652),
  );

  /// Synthetic driver origin used for device QA while development happens
  /// outside Calamba. It never replaces a commuter's real GPS fix.
  static const mockDriverLocation = DemoPlace(
    id: 'starbucks-olivarez-mock-driver',
    name: 'Starbucks Olivarez Plaza',
    address: 'Maharlika Highway, Barangay Milagrosa, Calamba, Laguna',
    coordinate: GeoCoordinate(latitude: 14.1792854, longitude: 121.1365276),
  );

  static const places = <DemoPlace>[
    calambaCrossing,
    DemoPlace(
      id: 'calamba-city-hall',
      name: 'Calamba City Hall',
      address: 'Chipeco Avenue Extension, Barangay Real, Calamba City',
      coordinate: GeoCoordinate(latitude: 14.1941, longitude: 121.1597),
    ),
    DemoPlace(
      id: 'rizal-shrine',
      name: 'Rizal Shrine Calamba',
      address: 'J. P. Rizal Street, Barangay 5, Calamba City',
      coordinate: GeoCoordinate(latitude: 14.2142, longitude: 121.1670),
    ),
    DemoPlace(
      id: 'sm-city-calamba',
      name: 'SM City Calamba',
      address: 'National Highway, Barangay Real, Calamba City',
      coordinate: GeoCoordinate(latitude: 14.2031, longitude: 121.1550),
    ),
    // MapTiler's search does not index this one; the local list covers it.
    DemoPlace(
      id: 'nu-laguna',
      name: 'National University Laguna',
      address: 'NU-L · KM 53 Maharlika Highway, Milagrosa, Calamba City',
      coordinate: GeoCoordinate(latitude: 14.1778, longitude: 121.1363),
    ),
    DemoPlace(
      id: 'canlubang-plaza',
      name: 'Canlubang Plaza',
      address: 'Canlubang, Calamba City',
      coordinate: GeoCoordinate(latitude: 14.1970, longitude: 121.0920),
    ),
  ];
}
