import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/admin_fixture.dart';

void main() {
  test('the console ships no sample records before sign-in', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final state = container.read(adminProvider);

    expect(state.connected, isFalse);
    expect(state.drivers, isEmpty);
    expect(state.reports, isEmpty);
    expect(state.rides, isEmpty);
    expect(state.audit, isEmpty);
    expect(state.feedbackCounts, isEmpty);
  });

  test(
    'dashboard scope stays independent from driver filters and audit leaks',
    () {
      final container = ProviderContainer(overrides: fixtureOverrides);
      addTearDown(container.dispose);
      final controller = container.read(adminProvider.notifier);
      const lguSession = AdminSession(
        name: 'LGU evaluator',
        role: AdminRole.lgu,
      );
      const todaSession = AdminSession(
        name: 'Coordinator',
        role: AdminRole.toda,
        toda: 'Brgy. Real',
      );

      controller.setDriverQuery('Joel');
      expect(controller.visibleDrivers(lguSession), hasLength(1));
      expect(controller.scopedDrivers(lguSession), hasLength(5));
      expect(controller.scopedDrivers(todaSession), hasLength(3));

      controller.setDriverQuery('');
      controller.setDriverStatus('Needs review');
      expect(
        controller.visibleDrivers(lguSession).map((driver) => driver.name),
        unorderedEquals(['Joel Mendoza', 'Mario Santos']),
      );

      expect(
        controller.visibleAudit(todaSession).map((event) => event.detail),
        everyElement(contains('Brgy. Real')),
      );
      expect(
        controller
            .visibleAudit(todaSession)
            .any((event) => event.detail.contains('Benjie Reyes')),
        isFalse,
      );
    },
  );

  test(
    'writes without a live session fail instead of changing local records',
    () async {
      final container = ProviderContainer(overrides: fixtureOverrides);
      addTearDown(container.dispose);
      final controller = container.read(adminProvider.notifier);
      final before = container.read(adminProvider);

      await expectLater(
        controller.updateDriver('124', DriverStatus.approved, 'Checked'),
        throwsStateError,
      );
      await expectLater(
        controller.transitionReport(
          'SR-1042',
          ReportStatus.resolved,
          'Checked',
        ),
        throwsStateError,
      );
      await expectLater(
        controller.transitionComplaint(
          'CPL-2091',
          ReportStatus.acknowledged,
          'Checked',
        ),
        throwsStateError,
      );

      final after = container.read(adminProvider);
      expect(after.drivers, same(before.drivers));
      expect(after.reports, same(before.reports));
      expect(after.complaints, same(before.complaints));
      expect(after.audit, same(before.audit));
    },
  );

  test(
    'only LGU administrators can update the global feedback interval',
    () async {
      final container = ProviderContainer(overrides: fixtureOverrides);
      addTearDown(container.dispose);
      final controller = container.read(adminProvider.notifier);
      const todaSession = AdminSession(
        name: 'Coordinator',
        role: AdminRole.toda,
        toda: 'Brgy. Real',
      );

      expect(container.read(adminProvider).feedbackInterval, 1);
      await expectLater(
        controller.updateFeedbackSettings(
          session: todaSession,
          feedbackInterval: 3,
        ),
        throwsStateError,
      );
      expect(container.read(adminProvider).feedbackInterval, 1);
    },
  );

  test('complaints and reviews stay scoped to the assigned TODA', () {
    final container = ProviderContainer(overrides: fixtureOverrides);
    addTearDown(container.dispose);
    final controller = container.read(adminProvider.notifier);
    const lguSession = AdminSession(
      name: 'LGU evaluator',
      role: AdminRole.lgu,
    );
    const todaSession = AdminSession(
      name: 'Coordinator',
      role: AdminRole.toda,
      toda: 'Brgy. Real',
    );

    // Both fixture complaints and both fixture ratings are in Brgy. Real, so a
    // scoped TODA administrator sees exactly the same count an unscoped LGU
    // administrator does here -- the real proof is that a DIFFERENT TODA
    // sees none, covered next.
    expect(controller.visibleComplaints(lguSession), hasLength(2));
    expect(controller.visibleComplaints(todaSession), hasLength(2));
    expect(controller.visibleRatings(lguSession), hasLength(2));
    expect(controller.visibleRatings(todaSession), hasLength(2));

    const otherTodaSession = AdminSession(
      name: 'Other Coordinator',
      role: AdminRole.toda,
      toda: 'Canlubang',
    );
    expect(controller.visibleComplaints(otherTodaSession), isEmpty);
    expect(controller.visibleRatings(otherTodaSession), isEmpty);
  });

  test('sessions without a connected account cannot change a password', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await expectLater(
      container
          .read(adminProvider.notifier)
          .updateOwnPassword(
            session: const AdminSession(
              name: 'LGU evaluator',
              email: 'evaluator@calambacity.gov.ph',
              role: AdminRole.lgu,
            ),
            currentPassword: 'current-password',
            newPassword: 'new-password',
          ),
      throwsStateError,
    );
  });
}
