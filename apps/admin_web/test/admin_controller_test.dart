import 'package:arangcada_admin/admin_controller.dart';
import 'package:arangcada_admin/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'dashboard scope stays independent from driver filters and audit leaks',
    () {
      final container = ProviderContainer();
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

  test('local admin mutations stay scoped and auditable', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(adminProvider.notifier);
    const todaSession = AdminSession(
      name: 'Coordinator',
      role: AdminRole.toda,
      toda: 'Brgy. Real',
    );

    expect(
      controller
          .visibleDrivers(todaSession)
          .every((driver) => driver.toda == 'Brgy. Real'),
      isTrue,
    );
    final driver = controller.enrollDriver(
      name: 'Test Driver',
      toda: 'Brgy. Real',
      phone: '09171234567',
      plate: 'TEST-1',
    );
    expect(driver.enrollmentCode, 'AC-2026-0128');

    controller.updateDriver(
      driver.id,
      DriverStatus.approved,
      'Test review complete',
    );
    expect(
      container
          .read(adminProvider)
          .drivers
          .firstWhere((item) => item.id == driver.id)
          .status,
      DriverStatus.approved,
    );

    controller.transitionReport(
      'SR-1042',
      ReportStatus.resolved,
      'Verified in test',
    );
    final report = container
        .read(adminProvider)
        .reports
        .firstWhere((item) => item.id == 'SR-1042');
    expect(report.status, ReportStatus.resolved);
    expect(report.notes.last, 'Verified in test');
    expect(
      container.read(adminProvider).audit.first.title,
      'Safety report updated',
    );
  });

  test(
    'demo feedback participants stay scoped and reject cross-TODA writes',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(adminProvider.notifier);
      const todaSession = AdminSession(
        name: 'Coordinator',
        role: AdminRole.toda,
        toda: 'Brgy. Real',
      );

      controller.recordDemoFeedbackResponse(todaSession, 'Brgy. Real');

      expect(container.read(adminProvider).feedbackCounts['Brgy. Real'], 9);
      expect(
        () => controller.recordDemoFeedbackResponse(todaSession, 'Parian'),
        throwsStateError,
      );
      expect(container.read(adminProvider).feedbackCounts['Parian'], 7);
    },
  );

  test(
    'only LGU administrators can update the global feedback interval',
    () async {
      final container = ProviderContainer();
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

      expect(container.read(adminProvider).feedbackInterval, 1);
      await controller.updateFeedbackSettings(
        session: lguSession,
        feedbackInterval: 3,
      );
      expect(container.read(adminProvider).feedbackInterval, 3);
      await expectLater(
        controller.updateFeedbackSettings(
          session: todaSession,
          feedbackInterval: 1,
        ),
        throwsStateError,
      );
      expect(container.read(adminProvider).feedbackInterval, 3);
    },
  );

  test('complaints and reviews stay scoped to the assigned TODA', () {
    final container = ProviderContainer();
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

    // Both seeded complaints and both seeded ratings are in Brgy. Real, so a
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

  test('transitioning a complaint updates its status and notes locally', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(adminProvider.notifier);
    const lguSession = AdminSession(
      name: 'LGU evaluator',
      role: AdminRole.lgu,
    );
    final before = controller.visibleComplaints(lguSession).firstWhere(
      (complaint) => complaint.id == 'CPL-2091',
    );
    expect(before.status, ReportStatus.newReport);

    controller.transitionComplaint(
      'CPL-2091',
      ReportStatus.acknowledged,
      'Spoke with the driver.',
    );

    final after = container
        .read(adminProvider.notifier)
        .visibleComplaints(lguSession)
        .firstWhere((complaint) => complaint.id == 'CPL-2091');
    expect(after.status, ReportStatus.acknowledged);
    expect(after.notes, contains('Spoke with the driver.'));
  });

  test('demo sessions cannot change an account password', () async {
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
