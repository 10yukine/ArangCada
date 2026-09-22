import 'dart:async';
import 'dart:convert';
import 'package:arangcada/config/app_config.dart';
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
}
