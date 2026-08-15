import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../app/theme/app_typography.dart';
import '../../core/widgets/arang_ui.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/app_row_icon.dart';
import '../../core/widgets/painted_calamba_map.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../demo/demo_simulation.dart';
import '../../domain/state/driver_trip_state_machine.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  Timer? _countdownTimer;
  DemoSimulationRun? _requestRun;
  int _secondsRemaining = 20;

  @override
  void initState() {
    super.initState();
    if (ref.read(demoStateProvider).driverTrip.status ==
        DriverTripStatus.incoming) {
      _startCountdown();
    } else if (ref.read(demoStateProvider).driverTrip.status ==
        DriverTripStatus.available) {
      _scheduleRequest();
    }
  }

  void _scheduleRequest() {
    _requestRun?.cancel();
    final state = ref.read(demoStateProvider);
    if (state.driverTrip.status != DriverTripStatus.available) return;
    _requestRun = ref
        .read(demoSimulationServiceProvider)
        .scheduleDriverRequest(
          state: state,
          onRequestReceived: () {
            if (!mounted) return;
            _startCountdown();
            setState(() {});
          },
        );
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _secondsRemaining = 20;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsRemaining <= 1) {
        timer.cancel();
        final state = ref.read(demoStateProvider);
        if (state.driverTrip.status == DriverTripStatus.incoming) {
          state.driverTrip.declineRequest();
          state.driverChanged();
        }
        setState(() => _secondsRemaining = 0);
      } else {
        setState(() => _secondsRemaining--);
      }
    });
  }

  void _acceptRequest() {
    _requestRun?.cancel();
    _countdownTimer?.cancel();
    final state = ref.read(demoStateProvider);
    state.driverTrip.acceptRequest();
    state.driverChanged();
    setState(() {});
  }

  void _declineRequest() {
    _requestRun?.cancel();
    _countdownTimer?.cancel();
    final state = ref.read(demoStateProvider);
    state.driverTrip.declineRequest();
    state.driverChanged();
    setState(() {});
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _requestRun?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            children: [
              // Prototype driver header: who you are, which body number and
              // TODA you drive under, and notices from the TODA desk.
              Row(
                children: [
                  ArangAvatar(
                    name: state.currentUser?.displayName ?? 'Driver',
                    background: AppColors.primary,
                    foreground: Colors.white,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hello, ${(state.currentUser?.displayName ?? 'Driver').split(' ').first}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink,
                          ),
                        ),
                        const Text(
                          'Body no. 024 - Calamba TODA',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ArangIconButton(
                    icon: Icons.notifications_outlined,
                    tooltip: 'TODA notices',
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No new notices from the TODA desk.'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _AvailabilityCard(
                online: state.driverTrip.isOnline,
                canToggle:
                    state.driverTrip.status == DriverTripStatus.available ||
                    state.driverTrip.status == DriverTripStatus.offline ||
                    state.driverTrip.status == DriverTripStatus.declined,
                onToggle: () {
                  if (state.driverTrip.isOnline) {
                    _requestRun?.cancel();
                    state.driverTrip.goOffline();
                  } else {
                    if (state.driverTrip.status == DriverTripStatus.declined) {
                      state.driverTrip.goOffline();
                    }
                    state.driverTrip.goOnline();
                    _scheduleRequest();
                  }
                  state.driverChanged();
                },
              ),
              const SizedBox(height: 14),
              _EarningsCard(onView: () => context.push('/driver/earnings')),
              const SizedBox(height: AppSpacing.md),
              if (state.driverTrip.status == DriverTripStatus.available)
                const SectionCard(
                  child: Column(
                    children: [
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                      SizedBox(height: AppSpacing.sm),
                      Text(
                        'You are online',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: AppSpacing.xs),
                      Text(
                        'Waiting for ride requests in the Calamba TODA area.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              if (state.driverTrip.status == DriverTripStatus.incoming)
                _IncomingRequestCard(
                  secondsRemaining: _secondsRemaining,
                  onAccept: _acceptRequest,
                  onDecline: _declineRequest,
                ),
              if (state.driverTrip.status == DriverTripStatus.accepted ||
                  state.driverTrip.status == DriverTripStatus.arrivedAtPickup)
                _PickupModeCard(
                  arrived:
                      state.driverTrip.status ==
                      DriverTripStatus.arrivedAtPickup,
                  onAction: () {
                    if (state.driverTrip.status == DriverTripStatus.accepted) {
                      state.driverTrip.markArrivedAtPickup();
                    } else {
                      state.driverTrip.startTrip();
                    }
                    state.driverChanged();
                  },
                ),
              if (state.driverTrip.status == DriverTripStatus.inProgress)
                _DriverTripModeCard(
                  onComplete: () {
                    state.driverTrip.completeTrip();
                    state.driverChanged();
                    context.go('/driver/earnings');
                  },
                ),
              if (state.driverTrip.status == DriverTripStatus.completed)
                SectionCard(
                  child: Column(
                    children: [
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.green,
                        size: 42,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Demo trip completed',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton(
                        onPressed: () => context.go('/driver/earnings'),
                        child: const Text('View Earnings'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncomingRequestCard extends StatelessWidget {
  const _IncomingRequestCard({
    required this.secondsRemaining,
    required this.onAccept,
    required this.onDecline,
  });

  final int secondsRemaining;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Incoming ride request',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              CircleAvatar(
                backgroundColor: AppColors.coral,
                child: Text('$secondsRemaining'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text('Joshua Adia · 1 passenger · Special'),
          const Text('Calamba Crossing Terminal → Calamba City Hall'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${formatCentavos(9200)} cash fare',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.dangerDark,
                    side: const BorderSide(color: AppColors.dangerBorder),
                  ),
                  onPressed: onDecline,
                  child: const Text('Decline'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  child: const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickupModeCard extends StatelessWidget {
  const _PickupModeCard({required this.arrived, required this.onAction});

  final bool arrived;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PaintedCalambaMap(height: 230),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                arrived ? 'Waiting at pickup' : 'Navigate to pickup',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text('Joshua Adia · Calamba Crossing Terminal'),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: onAction,
                child: Text(arrived ? 'Start Trip' : 'Arrived at Pickup'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverTripModeCard extends StatelessWidget {
  const _DriverTripModeCard({required this.onComplete});

  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const PaintedCalambaMap(height: 230),
        const SizedBox(height: AppSpacing.md),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trip in progress',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text('Destination: Calamba City Hall · ETA 12–16 min'),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: onComplete,
                child: const Text('Complete Trip'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class DriverProfileScreen extends ConsumerWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Driver profile')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              SectionCard(
                child: ListTile(
                  leading: const AppRowIcon(Icons.badge_outlined),
                  title: Text(state.currentUser?.displayName ?? 'Demo driver'),
                  subtitle: Text(state.currentUser?.email ?? ''),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.dangerDark,
                  side: const BorderSide(color: AppColors.dangerBorder),
                ),
                onPressed: () async {
                  await ref.read(authRepositoryProvider).signOut();
                  if (context.mounted) context.go('/login');
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Online/offline state, following the prototype: a status dot, a plain
/// sentence about what that means, and a chip to flip it.
class _AvailabilityCard extends StatelessWidget {
  const _AvailabilityCard({
    required this.online,
    required this.canToggle,
    required this.onToggle,
  });

  final bool online;
  final bool canToggle;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ArangCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              // Status is never colour alone -- the sentence beside it says
              // the same thing in words.
              color: online ? AppColors.green : AppColors.textMuted,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  online ? "You're online" : "You're offline",
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  online
                      ? 'Receiving requests from the Calamba Crossing terminal queue.'
                      : 'Go online to join the terminal queue.',
                  style: AppTypography.caption.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          ArangChip(
            label: online ? 'Go offline' : 'Go online',
            selected: false,
            onTap: canToggle ? onToggle : null,
          ),
        ],
      ),
    );
  }
}

/// Today's earnings, in the prototype's clay panel.
class _EarningsCard extends StatelessWidget {
  const _EarningsCard({required this.onView});

  final VoidCallback onView;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: const BoxDecoration(
        color: AppColors.clayFill,
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Today's earnings",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.clayText,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Cash collected plus digital awaiting settlement.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppColors.clayText,
                  ),
                ),
                const SizedBox(height: 10),
                ArangButton(
                  label: 'View earnings',
                  expand: false,
                  onPressed: onView,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          const Icon(
            Icons.payments_outlined,
            size: 32,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}
