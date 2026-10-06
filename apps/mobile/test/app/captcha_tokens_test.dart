import 'package:arangcada/app/captcha_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

/// The in-screen human check hands the app tokens ahead of time. Each works
/// once and for five minutes, so what is handed to Auth has to be the right
/// one, and exactly once.
void main() {
  late int asked;
  late DateTime clock;
  late CaptchaTokens tokens;

  setUp(() {
    asked = 0;
    clock = DateTime(2026, 10, 6, 10);
    tokens = CaptchaTokens(askAgain: () => asked++, now: () => clock);
  });

  tearDown(() => tokens.dispose());

  const brief = Duration(milliseconds: 60);

  test(
    'a ready token is handed out once and a fresh one is asked for',
    () async {
      tokens.onMessage('token:first');

      expect(await tokens.take(patience: brief), 'first');
      expect(asked, 1);
      // The same token is never given twice.
      expect(await tokens.take(patience: brief), isNull);
    },
  );

  test('a token on its way is waited for', () async {
    final taking = tokens.take(patience: const Duration(seconds: 2));
    await Future<void>.delayed(const Duration(milliseconds: 30));
    tokens.onMessage('token:late');

    expect(await taking, 'late');
  });

  test('an old or withdrawn token is not used', () async {
    tokens.onMessage('token:stale');
    clock = clock.add(const Duration(minutes: 5));
    expect(await tokens.take(patience: brief), isNull);

    tokens.onMessage('token:spent-by-cloudflare');
    tokens.onMessage('expired');
    expect(await tokens.take(patience: brief), isNull);

    tokens.onMessage('token:');
    expect(await tokens.take(patience: brief), isNull);
    expect(asked, 0);
  });

  test(
    'the box opens while a tap is wanted, and the wait lasts that long',
    () async {
      var changes = 0;
      tokens.addListener(() => changes++);

      tokens.onMessage('interactive:81');
      expect(tokens.openHeight, 81);

      // Longer than the ordinary patience: the person is still tapping.
      final taking = tokens.take(
        patience: brief,
        limit: const Duration(seconds: 2),
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));
      tokens.onMessage('token:after-tap');
      tokens.onMessage('idle');

      expect(await taking, 'after-tap');
      expect(tokens.openHeight, isNull);
      expect(changes, 2);
    },
  );
}
