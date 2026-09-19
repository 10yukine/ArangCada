import 'package:arangcada/core/widgets/trip_call_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'dialer accepts only registered PH mobile numbers, never USSD or URL input',
    () {
      expect(tripPhoneUri('+639171234567')?.scheme, 'tel');
      expect(tripPhoneUri('+639171234567')?.path, '+639171234567');
      for (final value in [
        null,
        '',
        '*123#',
        'tel:+639171234567',
        '+639171234567;123',
        '+12025550123',
      ]) {
        expect(tripPhoneUri(value), isNull);
      }
    },
  );
}
