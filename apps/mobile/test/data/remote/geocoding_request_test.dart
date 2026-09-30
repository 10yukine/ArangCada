import 'dart:async';
import 'dart:convert';
import 'package:arangcada/config/app_config.dart';
import 'package:arangcada/core/geo/haversine.dart';
import 'package:arangcada/data/remote/maptiler_geocoding_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'clearing search discards a pending response',
    () async {
      final pending = Completer<http.Response>();
      final repository = MapTilerGeocodingRepository(
        client: MockClient((_) => pending.future),
      );
      addTearDown(repository.dispose);
      final oldSearch = repository.search('Calamba');
      expect(await repository.search(''), isEmpty);
      pending.complete(
        http.Response(
          jsonEncode({
            'features': [
              {
                'id': 'test',
                'text': 'Old result',
                'center': [121.1, 14.2],
              },
            ],
          }),
          200,
        ),
      );
      expect(await oldSearch, isEmpty);
    },
    skip: !AppConfig.isMapTilerConfigured,
  );

  test(
    'a pin on a named place is labelled with it, and Route 1 is renamed',
    () async {
      http.Response feature(String text, List<double> center) => http.Response(
        jsonEncode({
          'features': [
            {
              'id': text,
              'text': text,
              'place_name': '$text, 4027 Calamba, Philippines',
              'center': center,
            },
          ],
        }),
        200,
      );
      var poiCenter = [121.1363, 14.1778];
      final repository = MapTilerGeocodingRepository(
        client: MockClient(
          (request) async => request.url.queryParameters['types'] == 'poi'
              ? feature('National University Laguna', poiCenter)
              : feature('Route 1', [121.1365, 14.1779]),
        ),
      );
      addTearDown(repository.dispose);
      const pin = GeoCoordinate(latitude: 14.1779, longitude: 121.1364);

      final onCampus = await repository.reverse(pin);
      expect(onCampus!.name, 'National University Laguna');
      expect(onCampus.context, 'Maharlika Highway');
      expect(onCampus.coordinate, pin);

      // A named place a few hundred meters away is not what the pin means.
      poiCenter = [121.1400, 14.1800];
      final onRoad = await repository.reverse(pin);
      expect(onRoad!.name, 'Maharlika Highway');
      expect(onRoad.context, '4027 Calamba, Philippines');
    },
    skip: !AppConfig.isMapTilerConfigured,
  );
}
