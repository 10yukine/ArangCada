import 'package:arangcada_admin/map_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dashboard dispatch map accepts pointer pan and zoom', () {
    expect(dashboardMapGesturesEnabled, isTrue);
  });
}
