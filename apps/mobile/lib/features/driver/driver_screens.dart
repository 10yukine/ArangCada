import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/format/money_format.dart';
import '../../core/widgets/painted_calamba_map.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/state/driver_trip_state_machine.dart';

class DriverHomeScreen extends ConsumerStatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  ConsumerState<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends ConsumerState<DriverHomeScreen> {
  Timer? _countdownTimer;
  int _secondsRemaining = 20;

  @override
  void initState() {
    super.initState();
    if (ref.read(demoStateProvider).driverTrip.status ==
        DriverTripStatus.incoming) {
      _startCountdown();
    }
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

  void _showRequest() {
    final state = ref.read(demoStateProvider);
    state.driverTrip.receiveRequest();
    state.driverChanged();
    _startCountdown();
    setState(() {});
  }

  void _acceptRequest() {
    _countdownTimer?.cancel();
    final state = ref.read(demoStateProvider);
    state.driverTrip.acceptRequest();
    state.driverChanged();
    setState(() {});
  }

  void _declineRequest() {
    _countdownTimer?.cancel();
    final state = ref.read(demoStateProvider);
    state.driverTrip.declineRequest();
    state.driverChanged();
    setState(() {});
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Driver dashboard')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text(
                'Magandang araw, ${state.currentUser?.displayName ?? 'Driver'}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              SectionCard(
                child: Column(
                  children: [
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primaryContainer,
                        child: Icon(
                          Icons.electric_rickshaw,
                          color: AppColors.primary,
                        ),
                      ),
                      title: Text('Tricycle 024'),
                      subtitle: Text('Calamba TODA · 4.9 rating'),
                    ),
                    const Divider(height: 1),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.verified_user_outlined,
                        color: AppColors.success,
                      ),
                      title: Text('Verification status'),
                      trailing: Chip(label: Text('Approved')),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        state.driverTrip.isOnline ? 'Online' : 'Offline',
                      ),
                      subtitle: Text(
                        state.driverTrip.isOnline
                            ? 'Ready for Calamba TODA demo requests'
                            : 'Go online to receive a request',
                      ),
                      value: state.driverTrip.isOnline,
                      onChanged:
                          state.driverTrip.status ==
                                  DriverTripStatus.available ||
                              state.driverTrip.status ==
                                  DriverTripStatus.offline ||
                              state.driverTrip.status ==
                                  DriverTripStatus.declined
                          ? (online) {
                              if (online) {
                                if (state.driverTrip.status ==
                                    DriverTripStatus.declined) {
                                  state.driverTrip.goOffline();
                                }
                                state.driverTrip.goOnline();
                              } else {
                                state.driverTrip.goOffline();
                              }
                              state.driverChanged();
                            }
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (state.driverTrip.status == DriverTripStatus.available)
                FilledButton.icon(
                  onPressed: _showRequest,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('Show Demo Incoming Request'),
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
                        color: AppColors.success,
                        size: 42,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      const Text('Demo trip completed'),
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
                backgroundColor: AppColors.secondary,
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
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge_outlined),
                  title: Text(state.currentUser?.displayName ?? 'Demo driver'),
                  subtitle: Text(state.currentUser?.email ?? ''),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
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
