import '../../core/geo/haversine.dart';

/// Client-side check for "is this inside the area ArangCada serves?".
///
/// This is a **guard rail, not the authority.** Real TODA jurisdiction is a
/// PostGIS polygon evaluated server-side (`supabase/migrations/*geofence_rpc*`),
/// because a client can be modified and a boundary decision affects who is
/// allowed to earn a fare. This exists so a commuter is told immediately
/// instead of being allowed to build a booking that the server will refuse.
///
/// The outline below is the one the server holds for Calamba, so both give
/// the same answer. It is not an official survey; see [boundary].
abstract final class ServiceArea {
  const ServiceArea._();

  static const String name = 'Calamba City';

  /// Calamba's outline from OpenStreetMap relation 1578579 ((c) OpenStreetMap
  /// contributors, ODbL), simplified to about 50 m. Point for point the ring
  /// in `supabase/pilot/20260930_bjmp_toda_zone.sql`, which is what the server
  /// was loaded from; a test compares the two. Change both together.
  static const List<GeoCoordinate> boundary = [
    GeoCoordinate(latitude: 14.16743, longitude: 121.01982),
    GeoCoordinate(latitude: 14.16233, longitude: 121.02366),
    GeoCoordinate(latitude: 14.15581, longitude: 121.02378),
    GeoCoordinate(latitude: 14.15192, longitude: 121.02720),
    GeoCoordinate(latitude: 14.15220, longitude: 121.02800),
    GeoCoordinate(latitude: 14.15396, longitude: 121.02838),
    GeoCoordinate(latitude: 14.15471, longitude: 121.03021),
    GeoCoordinate(latitude: 14.15374, longitude: 121.03130),
    GeoCoordinate(latitude: 14.15331, longitude: 121.03418),
    GeoCoordinate(latitude: 14.15383, longitude: 121.03733),
    GeoCoordinate(latitude: 14.15229, longitude: 121.03749),
    GeoCoordinate(latitude: 14.15216, longitude: 121.03933),
    GeoCoordinate(latitude: 14.15122, longitude: 121.03905),
    GeoCoordinate(latitude: 14.15210, longitude: 121.04072),
    GeoCoordinate(latitude: 14.15548, longitude: 121.04328),
    GeoCoordinate(latitude: 14.15695, longitude: 121.04596),
    GeoCoordinate(latitude: 14.15311, longitude: 121.04780),
    GeoCoordinate(latitude: 14.15414, longitude: 121.04906),
    GeoCoordinate(latitude: 14.15123, longitude: 121.04984),
    GeoCoordinate(latitude: 14.15323, longitude: 121.05770),
    GeoCoordinate(latitude: 14.15448, longitude: 121.06976),
    GeoCoordinate(latitude: 14.15610, longitude: 121.09834),
    GeoCoordinate(latitude: 14.15484, longitude: 121.10342),
    GeoCoordinate(latitude: 14.15413, longitude: 121.10304),
    GeoCoordinate(latitude: 14.15203, longitude: 121.10863),
    GeoCoordinate(latitude: 14.15268, longitude: 121.11026),
    GeoCoordinate(latitude: 14.15180, longitude: 121.11033),
    GeoCoordinate(latitude: 14.15044, longitude: 121.11476),
    GeoCoordinate(latitude: 14.14804, longitude: 121.11632),
    GeoCoordinate(latitude: 14.14677, longitude: 121.11536),
    GeoCoordinate(latitude: 14.14477, longitude: 121.11651),
    GeoCoordinate(latitude: 14.14530, longitude: 121.11890),
    GeoCoordinate(latitude: 14.14390, longitude: 121.12467),
    GeoCoordinate(latitude: 14.14540, longitude: 121.12737),
    GeoCoordinate(latitude: 14.14734, longitude: 121.12844),
    GeoCoordinate(latitude: 14.14483, longitude: 121.13035),
    GeoCoordinate(latitude: 14.14290, longitude: 121.13062),
    GeoCoordinate(latitude: 14.14174, longitude: 121.13342),
    GeoCoordinate(latitude: 14.14214, longitude: 121.13537),
    GeoCoordinate(latitude: 14.14436, longitude: 121.13666),
    GeoCoordinate(latitude: 14.14437, longitude: 121.13989),
    GeoCoordinate(latitude: 14.14352, longitude: 121.14033),
    GeoCoordinate(latitude: 14.14434, longitude: 121.14059),
    GeoCoordinate(latitude: 14.14368, longitude: 121.14108),
    GeoCoordinate(latitude: 14.14413, longitude: 121.14186),
    GeoCoordinate(latitude: 14.14209, longitude: 121.15210),
    GeoCoordinate(latitude: 14.14269, longitude: 121.15453),
    GeoCoordinate(latitude: 14.14090, longitude: 121.15677),
    GeoCoordinate(latitude: 14.14126, longitude: 121.15872),
    GeoCoordinate(latitude: 14.14057, longitude: 121.16034),
    GeoCoordinate(latitude: 14.14129, longitude: 121.16180),
    GeoCoordinate(latitude: 14.13770, longitude: 121.17134),
    GeoCoordinate(latitude: 14.15180, longitude: 121.18302),
    GeoCoordinate(latitude: 14.16644, longitude: 121.19992),
    GeoCoordinate(latitude: 14.17947, longitude: 121.20356),
    GeoCoordinate(latitude: 14.17941, longitude: 121.20257),
    GeoCoordinate(latitude: 14.18462, longitude: 121.20465),
    GeoCoordinate(latitude: 14.18577, longitude: 121.20371),
    GeoCoordinate(latitude: 14.25690, longitude: 121.22143),
    GeoCoordinate(latitude: 14.26139, longitude: 121.21267),
    GeoCoordinate(latitude: 14.26621, longitude: 121.20752),
    GeoCoordinate(latitude: 14.23526, longitude: 121.16803),
    GeoCoordinate(latitude: 14.23427, longitude: 121.16138),
    GeoCoordinate(latitude: 14.23513, longitude: 121.16016),
    GeoCoordinate(latitude: 14.23316, longitude: 121.15654),
    GeoCoordinate(latitude: 14.23373, longitude: 121.15512),
    GeoCoordinate(latitude: 14.23219, longitude: 121.15365),
    GeoCoordinate(latitude: 14.23269, longitude: 121.15198),
    GeoCoordinate(latitude: 14.23219, longitude: 121.14986),
    GeoCoordinate(latitude: 14.22487, longitude: 121.13490),
    GeoCoordinate(latitude: 14.22574, longitude: 121.13375),
    GeoCoordinate(latitude: 14.22981, longitude: 121.13499),
    GeoCoordinate(latitude: 14.23244, longitude: 121.13043),
    GeoCoordinate(latitude: 14.23444, longitude: 121.12993),
    GeoCoordinate(latitude: 14.23422, longitude: 121.12104),
    GeoCoordinate(latitude: 14.23485, longitude: 121.11880),
    GeoCoordinate(latitude: 14.23712, longitude: 121.11823),
    GeoCoordinate(latitude: 14.23757, longitude: 121.11519),
    GeoCoordinate(latitude: 14.23683, longitude: 121.11344),
    GeoCoordinate(latitude: 14.23439, longitude: 121.11263),
    GeoCoordinate(latitude: 14.23139, longitude: 121.10649),
    GeoCoordinate(latitude: 14.22996, longitude: 121.10543),
    GeoCoordinate(latitude: 14.22983, longitude: 121.10340),
    GeoCoordinate(latitude: 14.22821, longitude: 121.10041),
    GeoCoordinate(latitude: 14.22835, longitude: 121.09551),
    GeoCoordinate(latitude: 14.22670, longitude: 121.09352),
    GeoCoordinate(latitude: 14.22705, longitude: 121.08988),
    GeoCoordinate(latitude: 14.22430, longitude: 121.08876),
    GeoCoordinate(latitude: 14.22326, longitude: 121.08362),
    GeoCoordinate(latitude: 14.22188, longitude: 121.08282),
    GeoCoordinate(latitude: 14.21836, longitude: 121.07675),
    GeoCoordinate(latitude: 14.21838, longitude: 121.07259),
    GeoCoordinate(latitude: 14.21751, longitude: 121.07162),
    GeoCoordinate(latitude: 14.21777, longitude: 121.06791),
    GeoCoordinate(latitude: 14.21582, longitude: 121.06620),
    GeoCoordinate(latitude: 14.21438, longitude: 121.06217),
    GeoCoordinate(latitude: 14.21349, longitude: 121.06221),
    GeoCoordinate(latitude: 14.21105, longitude: 121.06009),
    GeoCoordinate(latitude: 14.20885, longitude: 121.05580),
    GeoCoordinate(latitude: 14.20420, longitude: 121.05412),
    GeoCoordinate(latitude: 14.20307, longitude: 121.05138),
    GeoCoordinate(latitude: 14.20263, longitude: 121.05217),
    GeoCoordinate(latitude: 14.20170, longitude: 121.05157),
    GeoCoordinate(latitude: 14.20095, longitude: 121.05305),
    GeoCoordinate(latitude: 14.20011, longitude: 121.05204),
    GeoCoordinate(latitude: 14.19969, longitude: 121.05296),
    GeoCoordinate(latitude: 14.19714, longitude: 121.05022),
    GeoCoordinate(latitude: 14.19564, longitude: 121.05014),
    GeoCoordinate(latitude: 14.19543, longitude: 121.04912),
    GeoCoordinate(latitude: 14.19391, longitude: 121.04922),
    GeoCoordinate(latitude: 14.19235, longitude: 121.04050),
    GeoCoordinate(latitude: 14.18875, longitude: 121.03878),
    GeoCoordinate(latitude: 14.18779, longitude: 121.03609),
    GeoCoordinate(latitude: 14.18519, longitude: 121.03566),
    GeoCoordinate(latitude: 14.18046, longitude: 121.03132),
    GeoCoordinate(latitude: 14.17190, longitude: 121.03221),
    GeoCoordinate(latitude: 14.17231, longitude: 121.02595),
    GeoCoordinate(latitude: 14.17122, longitude: 121.02203),
  ];

  /// Ray-casting point-in-polygon. Mirrors what `ST_Covers` decides on the
  /// server, minus the exact boundary semantics -- which is why the server
  /// remains authoritative.
  static bool contains(
    GeoCoordinate point, {
    bool allowCabuyaoTestException = false,
  }) {
    if (allowCabuyaoTestException &&
        point.latitude >= 14.2350 &&
        point.latitude <= 14.3300 &&
        point.longitude >= 121.0550 &&
        point.longitude <= 121.1750) {
      return true;
    }
    var inside = false;
    for (var i = 0, j = boundary.length - 1; i < boundary.length; j = i++) {
      final a = boundary[i];
      final b = boundary[j];
      final intersects =
          (a.latitude > point.latitude) != (b.latitude > point.latitude) &&
          point.longitude <
              (b.longitude - a.longitude) *
                      (point.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude;
      if (intersects) inside = !inside;
    }
    return inside;
  }

  /// Null when the trip is serviceable, otherwise the reason to show.
  static String? rejectionReason({
    required GeoCoordinate pickup,
    required GeoCoordinate destination,
    bool allowCabuyaoTestException = false,
  }) {
    final pickupOk = contains(
      pickup,
      allowCabuyaoTestException: allowCabuyaoTestException,
    );
    final destinationOk = contains(
      destination,
      allowCabuyaoTestException: allowCabuyaoTestException,
    );
    if (pickupOk && destinationOk) return null;
    if (!pickupOk && !destinationOk) {
      return 'Both your pickup and destination are outside the $name service '
          'area. ArangCada tricycles operate within Calamba only.';
    }
    if (!destinationOk) {
      return 'This destination is outside the $name service area. Booking is '
          'not allowed.';
    }
    return 'Your pickup point is outside the $name service area. Booking is '
        'not allowed.';
  }
}
