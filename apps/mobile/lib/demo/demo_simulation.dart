import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/mock/demo_state.dart';
import '../domain/models/booking.dart';
import '../domain/state/driver_trip_state_machine.dart';

class DemoSimulationDurations {
  const DemoSimulationDurations({
    this.driverMatchMin = const Duration(seconds: 2),
    this.driverMatchMax = const Duration(seconds: 4),
    this.matchedDisplay = const Duration(milliseconds: 600),
    this.driverApproachMin = const Duration(seconds: 6),
    this.driverApproachMax = const Duration(seconds: 9),
    this.arrivedDisplay = const Duration(milliseconds: 800),
    this.tripMin = const Duration(seconds: 10),
    this.tripMax = const Duration(seconds: 14),
    this.driverRequestMin = const Duration(seconds: 2),
    this.driverRequestMax = const Duration(seconds: 4),
    this.countdownTick = const Duration(seconds: 1),
  });

  final Duration driverMatchMin;
  final Duration driverMatchMax;
  final Duration matchedDisplay;
  final Duration driverApproachMin;
  final Duration driverApproachMax;
  final Duration arrivedDisplay;
  final Duration tripMin;
  final Duration tripMax;
  final Duration driverRequestMin;
  final Duration driverRequestMax;
  final Duration countdownTick;
}

enum DemoSimulationStage {
  driverMatch,
  matchedDisplay,
  driverApproach,
  activeTrip,
  driverRequest,
}

class DemoSimulationRun {
  DemoSimulationRun._(this.stage, this.duration);

  final DemoSimulationStage stage;
  final Duration duration;
  final List<Timer> _timers = [];
  bool _cancelled = false;

  int get totalSeconds => (duration.inMilliseconds + 999) ~/ 1000;
  bool get isCancelled => _cancelled;

  void _track(Timer timer) {
    if (_cancelled) {
      timer.cancel();
    } else {
      _timers.add(timer);
    }
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }
}

/// Schedules logical events for the offline demo.
///
/// Smooth marker motion remains widget-owned. Every returned run must be
/// cancelled by the screen that started it; [dispose] is the final safeguard.
class DemoSimulationService {
  DemoSimulationService({
    this.durations = const DemoSimulationDurations(),
    Random? random,
  }) : _random = random ?? Random(20260815);

  final DemoSimulationDurations durations;
  final Random _random;
  final Set<DemoSimulationRun> _runs = {};

  Duration _between(Duration minimum, Duration maximum) {
    final minMs = minimum.inMilliseconds;
    final maxMs = maximum.inMilliseconds;
    if (maxMs < minMs) {
      throw ArgumentError('Maximum simulation duration must not be shorter.');
    }
    if (maxMs == minMs) return minimum;
    return Duration(milliseconds: minMs + _random.nextInt(maxMs - minMs + 1));
  }

  DemoSimulationRun _run(DemoSimulationStage stage, Duration duration) {
    final run = DemoSimulationRun._(stage, duration);
    _runs.add(run);
    return run;
  }

  void _cancelStage(DemoSimulationStage stage) {
    for (final run in _runs.where((run) => run.stage == stage)) {
      run.cancel();
    }
  }

  DemoSimulationRun scheduleDriverMatch({
    required DemoState state,
    required void Function() onMatched,
  }) {
    _cancelStage(DemoSimulationStage.driverMatch);
    final delay = _between(durations.driverMatchMin, durations.driverMatchMax);
    final run = _run(DemoSimulationStage.driverMatch, delay);
    run._track(
      Timer(delay, () {
        if (run.isCancelled || state.forceNoDriversAvailable) return;
        final booking = state.activeBooking;
        if (booking?.status != BookingStatus.searching) return;
        booking!.matchDriver();
        state.bookingChanged();
        onMatched();
      }),
    );
    return run;
  }

  DemoSimulationRun scheduleDriverApproachStart({
    required DemoState state,
    required void Function() onApproachStarted,
  }) {
    _cancelStage(DemoSimulationStage.matchedDisplay);
    final run = _run(
      DemoSimulationStage.matchedDisplay,
      durations.matchedDisplay,
    );
    run._track(
      Timer(durations.matchedDisplay, () {
        if (run.isCancelled) return;
        final booking = state.activeBooking;
        if (booking?.status != BookingStatus.matched) return;
        booking!.beginDriverApproach();
        state.bookingChanged();
        onApproachStarted();
      }),
    );
    return run;
  }

  DemoSimulationRun scheduleDriverArrival({
    required DemoState state,
    required void Function(int secondsRemaining) onEtaChanged,
    required void Function() onArrived,
    required void Function() onTripStarted,
  }) {
    _cancelStage(DemoSimulationStage.driverApproach);
    final delay = _between(
      durations.driverApproachMin,
      durations.driverApproachMax,
    );
    final run = _run(DemoSimulationStage.driverApproach, delay);
    var remainingMs = delay.inMilliseconds;
    late final Timer countdown;
    countdown = Timer.periodic(durations.countdownTick, (timer) {
      if (run.isCancelled) return;
      remainingMs -= durations.countdownTick.inMilliseconds;
      onEtaChanged(
        ((remainingMs.clamp(0, delay.inMilliseconds)) + 999) ~/ 1000,
      );
    });
    run._track(countdown);
    run._track(
      Timer(delay, () {
        countdown.cancel();
        if (run.isCancelled ||
            state.activeBooking?.status != BookingStatus.approaching) {
          return;
        }
        onEtaChanged(0);
        onArrived();
        run._track(
          Timer(durations.arrivedDisplay, () {
            if (run.isCancelled ||
                state.activeBooking?.status != BookingStatus.approaching) {
              return;
            }
            state.activeBooking!.startTrip();
            state.bookingChanged();
            onTripStarted();
          }),
        );
      }),
    );
    return run;
  }

  DemoSimulationRun scheduleTripCompletion({
    required DemoState state,
    required void Function() onCompletionDue,
  }) {
    _cancelStage(DemoSimulationStage.activeTrip);
    final delay = _between(durations.tripMin, durations.tripMax);
    final run = _run(DemoSimulationStage.activeTrip, delay);
    run._track(
      Timer(delay, () {
        if (run.isCancelled ||
            state.activeBooking?.status != BookingStatus.inProgress) {
          return;
        }
        onCompletionDue();
      }),
    );
    return run;
  }

  DemoSimulationRun scheduleDriverRequest({
    required DemoState state,
    required void Function() onRequestReceived,
  }) {
    _cancelStage(DemoSimulationStage.driverRequest);
    final delay = _between(
      durations.driverRequestMin,
      durations.driverRequestMax,
    );
    final run = _run(DemoSimulationStage.driverRequest, delay);
    run._track(
      Timer(delay, () {
        if (run.isCancelled ||
            state.driverTrip.status != DriverTripStatus.available) {
          return;
        }
        state.driverTrip.receiveRequest();
        state.driverChanged();
        onRequestReceived();
      }),
    );
    return run;
  }

  bool forceDriverMatch(DemoState state) {
    _cancelStage(DemoSimulationStage.driverMatch);
    final booking = state.activeBooking;
    if (booking?.status != BookingStatus.searching) return false;
    booking!.matchDriver();
    state.bookingChanged();
    return true;
  }

  bool forceDriverArrival(DemoState state) {
    _cancelStage(DemoSimulationStage.matchedDisplay);
    _cancelStage(DemoSimulationStage.driverApproach);
    final booking = state.activeBooking;
    if (booking?.status == BookingStatus.matched) {
      booking!.beginDriverApproach();
    }
    if (booking?.status != BookingStatus.approaching) return false;
    booking!.startTrip();
    state.bookingChanged();
    return true;
  }

  bool forceTripCompletion(DemoState state) {
    _cancelStage(DemoSimulationStage.activeTrip);
    final booking = state.activeBooking;
    if (booking?.status != BookingStatus.inProgress) return false;
    booking!
      ..completeTrip()
      ..receiptReference = 'DEMO-DEV-COMPLETE-001';
    state.bookingChanged();
    return true;
  }

  void dispose() {
    for (final run in _runs) {
      run.cancel();
    }
    _runs.clear();
  }
}

final demoSimulationServiceProvider = Provider<DemoSimulationService>((ref) {
  final service = DemoSimulationService();
  ref.onDispose(service.dispose);
  return service;
});
