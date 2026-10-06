import 'dart:async';

import 'package:arangcada/app/auth_captcha.dart';
import 'package:arangcada/app/captcha_tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

/// The in-screen human check hands the app tokens ahead of time. Each works
/// once and for five minutes, so what is handed to Auth has to be the right
/// one, and exactly once.
void main() {
  late int startedOver;
  late DateTime clock;
  late CaptchaTokens tokens;

  CaptchaTokens holder() =>
      CaptchaTokens(startOver: () => startedOver++, now: () => clock);

  setUp(() {
    startedOver = 0;
    clock = DateTime(2026, 10, 6, 10);
    tokens = holder();
  });

  tearDown(() => tokens.dispose());

  const brief = Duration(milliseconds: 60);

  test(
    'a ready token is handed out once and the page starts over for the next',
    () async {
      tokens.onMessage('token:first');

      expect(await tokens.take(patience: brief), 'first');
      expect(startedOver, 1);
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

  test('a token that has grown old is replaced, not waited out', () async {
    tokens.onMessage('token:stale');
    // Too old to send, yet not old enough for the page to replace it.
    clock = clock.add(const Duration(minutes: 4, seconds: 40));

    final taking = tokens.take(patience: const Duration(seconds: 2));
    expect(startedOver, 1);
    tokens.onMessage('token:fresh');

    expect(await taking, 'fresh');
  });

  test('a withdrawn or empty token is not used', () async {
    tokens.onMessage('token:spent-by-cloudflare');
    tokens.onMessage('expired');
    expect(await tokens.take(patience: brief), isNull);

    tokens.onMessage('token:');
    expect(await tokens.take(patience: brief), isNull);
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

  test(
    'a check that is getting nowhere has its page started afresh, once',
    () async {
      final taking = tokens.take(patience: const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(startedOver, 1);
      tokens.onMessage('token:from-the-new-page');

      expect(await taking, 'from-the-new-page');
      // Once while waiting, once more for the token after this one.
      expect(startedOver, 2);
    },
  );

  test('a page that did not load is started afresh without waiting', () async {
    tokens.pageFailed();

    final taking = tokens.take(patience: const Duration(seconds: 2));
    expect(startedOver, 1);
    tokens.onMessage('token:loaded-this-time');

    expect(await taking, 'loaded-this-time');
  });

  test('a wait ends when its screen goes', () async {
    final gone = holder();
    final taking = gone.take(patience: const Duration(seconds: 30));
    gone.dispose();

    expect(await taking, isNull);
    expect(startedOver, 0);
  });

  // The owner's report, 6 Oct 2026: a second sign-in attempt on the Login
  // screen found the in-screen check still working, and after eight seconds
  // the old "Security check" dialog opened on top of it.
  group('which check answers', () {
    final refused = isA<AuthException>().having(
      (error) => error.code,
      'code',
      'captcha_failed',
    );

    testWidgets(
      'a screen that carries the check never opens the dialog as well',
      (tester) async {
        var dialogs = 0;
        Object? outcome;
        unawaited(
          captchaFrom(tokens, () async {
            dialogs++;
            return 'from-the-dialog';
          }).then<void>(
            (token) => outcome = token,
            onError: (Object error) => outcome = error,
          ),
        );

        // Slower than the old eight seconds, and after one fresh start.
        await tester.pump(const Duration(seconds: 14));
        expect(outcome, isNull);
        expect(startedOver, 1);
        tokens.onMessage('token:slow-but-in-the-screen');
        await tester.pump();

        expect(outcome, 'slow-but-in-the-screen');
        expect(dialogs, 0);
      },
    );

    testWidgets('a check that never finishes is refused here, not sent', (
      tester,
    ) async {
      var dialogs = 0;
      Object? outcome;
      unawaited(
        captchaFrom(tokens, () async {
          dialogs++;
          return 'from-the-dialog';
        }).then<void>(
          (token) => outcome = token,
          onError: (Object error) => outcome = error,
        ),
      );

      await tester.pump(const Duration(seconds: 19));
      expect(outcome, isNull);
      await tester.pump(const Duration(seconds: 2));

      // What Auth itself answers without a token, so the screen says the
      // same thing it would have said.
      expect(outcome, refused);
      expect(dialogs, 0);
    });

    testWidgets('a wait whose screen has gone opens nothing either', (
      tester,
    ) async {
      final gone = holder();
      var dialogs = 0;
      Object? outcome;
      unawaited(
        captchaFrom(gone, () async {
          dialogs++;
          return 'from-the-dialog';
        }).then<void>(
          (token) => outcome = token,
          onError: (Object error) => outcome = error,
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      gone.dispose();
      await tester.pump();

      expect(outcome, refused);
      expect(dialogs, 0);
    });

    test('a screen without one uses the dialog', () async {
      expect(
        await captchaFrom(null, () async => 'from-the-dialog'),
        'from-the-dialog',
      );
      // Closed or failed: refused, not sent without a token.
      await expectLater(captchaFrom(null, () async => null), throwsA(refused));
    });
  });
}
