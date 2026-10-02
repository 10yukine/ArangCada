import 'dart:math' as math;

import 'haversine.dart';

/// Where [position] is along [line]: how far off it, and the part still ahead.
///
/// Worked out on the device so a moving vehicle can follow a route it already
/// has instead of asking the routing service again. Flat-earth maths, which is
/// exact enough over a city.
({double offRouteMeters, List<GeoCoordinate> remaining}) routeProgress(
  List<GeoCoordinate> line,
  GeoCoordinate position,
) {
  if (line.isEmpty) return (offRouteMeters: double.infinity, remaining: line);
  if (line.length == 1) {
    return (
      offRouteMeters: haversineDistanceMeters(line.first, position),
      remaining: line,
    );
  }

  const metersPerDegree = 111320.0;
  final scale = math.cos(position.latitude * math.pi / 180);
  // Metres east and north of [position].
  (double, double) local(GeoCoordinate c) => (
    (c.longitude - position.longitude) * metersPerDegree * scale,
    (c.latitude - position.latitude) * metersPerDegree,
  );

  var best = double.infinity;
  var bestSegment = 0;
  var bestT = 0.0;
  for (var i = 0; i < line.length - 1; i++) {
    final (ax, ay) = local(line[i]);
    final (bx, by) = local(line[i + 1]);
    final dx = bx - ax;
    final dy = by - ay;
    final lengthSquared = dx * dx + dy * dy;
    final t = lengthSquared == 0
        ? 0.0
        : ((-ax * dx - ay * dy) / lengthSquared).clamp(0.0, 1.0);
    final distance = math.sqrt(
      math.pow(ax + t * dx, 2) + math.pow(ay + t * dy, 2),
    );
    if (distance < best) {
      best = distance;
      bestSegment = i;
      bestT = t;
    }
  }

  final a = line[bestSegment];
  final b = line[bestSegment + 1];
  final nearest = GeoCoordinate(
    latitude: a.latitude + (b.latitude - a.latitude) * bestT,
    longitude: a.longitude + (b.longitude - a.longitude) * bestT,
  );
  return (
    offRouteMeters: best,
    remaining: [nearest, ...line.sublist(bestSegment + 1)],
  );
}
