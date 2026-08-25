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

  test('survey responses persist centrally and reject cross-TODA writes', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(adminProvider.notifier);
    const todaSession = AdminSession(
      name: 'Coordinator',
      role: AdminRole.toda,
      toda: 'Brgy. Real',
    );

    controller.recordSurveyResponse(todaSession, 'Brgy. Real');

    expect(container.read(adminProvider).surveyCounts['Brgy. Real'], 9);
    expect(
      () => controller.recordSurveyResponse(todaSession, 'Parian'),
      throwsStateError,
    );
    expect(container.read(adminProvider).surveyCounts['Parian'], 7);
  });
}
