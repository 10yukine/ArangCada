import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../data/providers/repository_providers.dart';
import '../../domain/models/booking.dart';

class SearchingForDriverScreen extends ConsumerStatefulWidget {
  const SearchingForDriverScreen({super.key});

  @override
  ConsumerState<SearchingForDriverScreen> createState() =>
      _SearchingForDriverScreenState();
}

class _SearchingForDriverScreenState
    extends ConsumerState<SearchingForDriverScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scanController;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _scanController.dispose();
    super.dispose();
  }

  Future<void> _cancel(DemoBooking booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel ride request?'),
        content: const Text('ArangCada will stop searching for a demo driver.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep Searching'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    booking.cancelSearching();
    ref.read(demoStateProvider).bookingChanged();
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Finding your driver')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) {
            final booking = state.activeBooking;
            if (booking == null || booking.status != BookingStatus.searching) {
              return const Center(child: Text('No active driver search.'));
            }
            return Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  const Spacer(),
                  AnimatedBuilder(
                    animation: _scanController,
                    builder: (context, child) => Transform.rotate(
                      angle: _scanController.value * 6.283185307,
                      child: child,
                    ),
                    child: Container(
                      width: 154,
                      height: 154,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.primaryContainer,
                          width: 22,
                        ),
                      ),
                      child: const Icon(
                        Icons.radar,
                        size: 74,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  Text(
                    'Searching for a nearby driver',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text(
                    'Checking approved drivers in the Calamba TODA demo jurisdiction.',
                    textAlign: TextAlign.center,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () {
                      booking.matchDriver();
                      state.bookingChanged();
                      context.go('/booking/driver-matched');
                    },
                    icon: const Icon(Icons.person_search),
                    label: const Text('Simulate Driver Match'),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: () => _cancel(booking),
                    child: const Text('Cancel ride request'),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
