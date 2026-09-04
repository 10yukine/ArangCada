import 'package:arangcada/core/format/ph_mobile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizePhMobile accepts the ways Filipinos actually type a number', () {
    // Every one of these is the same number. A driver at a TODA terminal will
    // type whichever form they know; all of them must reach the same SIM.
    const sameNumber = <String>[
      '09171234567',
      '0917 123 4567',
      '0917-123-4567',
      '+639171234567',
      '+63 917 123 4567',
      '639171234567',
      '9171234567',
      '(0917) 123-4567',
      '  09171234567  ',
    ];

    for (final input in sameNumber) {
      test('"$input" normalises to +639171234567', () {
        final result = normalizePhMobile(input);
        expect(result.isValid, isTrue, reason: result.error);
        expect(result.e164, '+639171234567');
      });
    }
  });

  group('rejects what cannot receive an OTP', () {
    const rejected = <String, String>{
      '': 'empty',
      '   ': 'whitespace only',
      'abcdefghijk': 'letters',
      '0917123456': 'one digit short',
      '091712345678': 'one digit long',
      '0281234567': 'Metro Manila landline, not a mobile',
      '028123456': 'landline, wrong length',
      '+14155552671': 'US number',
      '123': 'far too short',
    };

    rejected.forEach((input, why) {
      test('rejects "$input" ($why)', () {
        final result = normalizePhMobile(input);
        expect(result.isValid, isFalse);
        expect(result.error, isNotNull);
        expect(result.error, isNotEmpty);
      });
    });

    test('rejects null', () {
      expect(normalizePhMobile(null).isValid, isFalse);
    });
  });

  group('presentation', () {
    test('reads a number back the way a Filipino user expects', () {
      expect(normalizePhMobile('+639171234567').display, '0917 123 4567');
    });

    test('masks the middle for the verify screen', () {
      // Enough to recognise your own number, not enough to read over a
      // shoulder.
      expect(normalizePhMobile('09171234567').masked, '+63 917 *** 4567');
    });
  });

  test('an invalid number carries an error a user can act on', () {
    // The message must say what to do, not just that something is wrong.
    final result = normalizePhMobile('0917123456');
    expect(result.error, contains('0917'));
  });
}
