import '../core/geo/haversine.dart';

class DemoPlace {
  const DemoPlace({
    required this.id,
    required this.name,
    required this.address,
    required this.coordinate,
  });

  final String id;
  final String name;
  final String address;
  final GeoCoordinate coordinate;
}

abstract final class DemoData {
  static const calambaCrossing = DemoPlace(
    id: 'calamba-crossing',
    name: 'Calamba Crossing Terminal',
    address: 'Crossing, Real, Calamba City',
    coordinate: GeoCoordinate(latitude: 14.2116, longitude: 121.1652),
  );

  static const places = <DemoPlace>[
    calambaCrossing,
    DemoPlace(
      id: 'calamba-city-hall',
      name: 'Calamba City Hall',
      address: 'Chipeco Avenue, Barangay Real, Calamba City',
      coordinate: GeoCoordinate(latitude: 14.1875, longitude: 121.1250),
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
      coordinate: GeoCoordinate(latitude: 14.2074, longitude: 121.1556),
    ),
    DemoPlace(
      id: 'uplb-gate',
      name: 'UPLB Main Gate',
      address: 'Lopez Avenue, Los Baños',
      coordinate: GeoCoordinate(latitude: 14.1660, longitude: 121.2421),
    ),
    DemoPlace(
      id: 'canlubang-plaza',
      name: 'Canlubang Plaza',
      address: 'Canlubang, Calamba City',
      coordinate: GeoCoordinate(latitude: 14.1970, longitude: 121.0920),
    ),
  ];
}
