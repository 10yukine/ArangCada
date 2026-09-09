import 'package:arangcada_admin/main.dart';
import 'package:arangcada_admin/models.dart';
import 'package:arangcada_admin/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    auth.value = null;
  });

  Future<void> openSettings(WidgetTester tester, AdminSession session) async {
    await tester.binding.setSurfaceSize(const Size(1001, 941));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    auth.value = session;
    await tester.pumpWidget(const ProviderScope(child: AdminApp()));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a connected session with no photo yet offers to change it',
    (tester) async {
      await openSettings(
        tester,
        const AdminSession(
          name: 'Maria Robles',
          email: 'm.robles@calamba.gov.ph',
          role: AdminRole.lgu,
          userId: 'admin-1',
          connected: true,
        ),
      );

      // Initials still render (no photo on file yet).
      expect(find.text('MR'), findsWidgets);
      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('Change profile photo')),
        findsOneWidget,
      );
      semantics.dispose();
    },
  );

  testWidgets(
    'the edit badge renders fully inside its own tappable area, not '
    'poking outside it',
    (tester) async {
      // Regression test for a real bug: the badge used to sit at a
      // negative Positioned offset (right: -2, bottom: -2) so it could
      // visually poke past the avatar's edge -- painted there via
      // Clip.none, but *outside* the GestureDetector's own hit-test
      // bounds (a Positioned child painting outside a Stack's bounds does
      // not extend what that Stack -- or its ancestor GestureDetector --
      // will hit-test). It was visible and looked tappable but a real
      // click on it silently did nothing. A presence-only check
      // (find.bySemanticsLabel, the test above) cannot catch this class
      // of bug; this asserts the actual geometry instead -- everything
      // that paints must stay within the one Rect that is tappable.
      await openSettings(
        tester,
        const AdminSession(
          name: 'Maria Robles',
          email: 'm.robles@calamba.gov.ph',
          role: AdminRole.lgu,
          userId: 'admin-1',
          connected: true,
        ),
      );

      final hitTestArea = tester.getRect(
        find.byKey(const ValueKey('avatarHitTestBox')),
      );
      final badge = tester.getRect(find.byIcon(Icons.edit));

      expect(hitTestArea.contains(badge.topLeft), isTrue);
      expect(hitTestArea.contains(badge.bottomRight), isTrue);
    },
  );

  testWidgets(
    'a real tap on the edit badge does not throw',
    (tester) async {
      // The geometry test above proves nothing paints outside the
      // tappable area; this exercises a real tester.tap() (hit-tests for
      // real, the same way a mouse click does) at the badge's own
      // rendered position. Deliberately weaker than the check this
      // replaced: _changePhoto() used to show a SnackBar synchronously,
      // before ever awaiting image_picker, specifically so this test
      // could prove tap delivery independent of image_picker itself --
      // but that same SnackBar turned out to be a real live bug (it
      // silently consumed the browser's one-shot "user activation" for
      // the click, so image_picker's file dialog never opened -- see the
      // header comment on _changePhoto). Nothing may run ahead of
      // pickImage() in real code, which also means nothing here can
      // observe tap delivery without also reintroducing that bug. Left
      // as a smoke test -- a genuinely broken hit-test region (the class
      // of bug the geometry test above targets) would still throw or
      // warn here; the actual browser-activation timing this bug turned
      // out to hinge on is not something `flutter test`'s Dart-VM
      // environment can exercise at all, same limitation this repo has
      // hit before for other browser-specific interactions.
      await openSettings(
        tester,
        const AdminSession(
          name: 'Maria Robles',
          email: 'm.robles@calamba.gov.ph',
          role: AdminRole.lgu,
          userId: 'admin-1',
          connected: true,
        ),
      );

      await tester.tap(find.byIcon(Icons.edit), warnIfMissed: true);
      await tester.pump();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'both avatars (Settings panel and nav rail) pick up a new photo '
    'without navigating away first',
    (tester) async {
      // Regression test for a real bug, confirmed live 9 Sep 2026: a
      // real photo upload succeeded end to end (verified directly
      // against the hosted project -- the Storage object and
      // profiles.avatar_path both existed with the correct value), but
      // the console kept showing initials, not the new photo. Root
      // cause: _changePhoto() updates auth.value in place, on the *same*
      // route -- unlike every other write to auth.value in this app
      // (sign-in, session restore), which always immediately navigates
      // to a different route and so always gets a fresh build for free.
      // _AccountProfilePanel and _RailAccountFooter each captured
      // `session` once from their parent and never asked auth.value
      // again. This simulates exactly that in-place update -- no
      // navigation -- and checks that a screen already on Settings still
      // picks up the change.
      const before = AdminSession(
        name: 'Maria Robles',
        email: 'm.robles@calamba.gov.ph',
        role: AdminRole.lgu,
        userId: 'admin-1',
        connected: true,
      );
      await openSettings(tester, before);

      expect(find.text('MR'), findsWidgets);

      auth.value = const AdminSession(
        name: 'Maria Robles',
        email: 'm.robles@calamba.gov.ph',
        role: AdminRole.lgu,
        userId: 'admin-1',
        connected: true,
        avatarUrl: 'https://example.test/signed/photo.jpg',
      );
      await tester.pump();

      // Initials were the CircleAvatar's only child when there was no
      // photo; with avatarUrl set, that child becomes null everywhere,
      // in both the Settings panel and the rail footer -- checking the
      // widgets' own properties rather than rendering the image itself,
      // which would attempt a real network fetch in this environment.
      final avatars = tester.widgetList<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatars, isNotEmpty);
      expect(avatars.every((avatar) => avatar.backgroundImage != null), isTrue);
      expect(find.text('MR'), findsNothing);
    },
  );

  testWidgets(
    'a disconnected local-demo session cannot change its photo',
    (tester) async {
      await openSettings(
        tester,
        const AdminSession(name: 'LGU Evaluator', role: AdminRole.lgu),
      );

      final semantics = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('Change profile photo')),
        findsNothing,
      );
      semantics.dispose();
    },
  );
}
