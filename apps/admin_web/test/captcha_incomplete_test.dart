import 'package:arangcada_admin/captcha.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a configured check cannot continue without a token',
    () async {
      await expectLater(
        captchaToken(),
        throwsA(
          predicate(
            (error) => error is Object && captchaFailureMessage(error) != null,
          ),
        ),
      );
    },
    skip: turnstileSiteKey.isEmpty,
  );
}
