import 'package:arangcada/app/theme/app_colors.dart';
import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/core/widgets/map/live_map_view.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('map diffs catch marker style and interior route changes', () {
    const point = GeoCoordinate(latitude: 14.21, longitude: 121.16);
    const end = GeoCoordinate(latitude: 14.22, longitude: 121.17);

    expect(
      mapMarkersEquivalent(
        const [MapMarker(coordinate: point, color: AppColors.primary)],
        const [MapMarker(coordinate: point, color: AppColors.green)],
      ),
      isFalse,
    );
    expect(
      mapRoutesEquivalent(
        const [point, GeoCoordinate(latitude: 14.215, longitude: 121.165), end],
        const [point, GeoCoordinate(latitude: 14.216, longitude: 121.165), end],
      ),
      isFalse,
    );
    expect(
      mapBoundariesEquivalent(
        const [
          MapBoundary(
            points: [
              point,
              GeoCoordinate(latitude: 14.215, longitude: 121.165),
              end,
            ],
          ),
        ],
        const [
          MapBoundary(
            points: [
              point,
              GeoCoordinate(latitude: 14.216, longitude: 121.165),
              end,
            ],
          ),
        ],
      ),
      isFalse,
    );
  });
}
