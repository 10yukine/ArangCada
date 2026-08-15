import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/section_card.dart';
import '../../data/providers/repository_providers.dart';

class CommuterHomeScreen extends ConsumerWidget {
  const CommuterHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(demoStateProvider);
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text('Hi, ${state.currentUser?.displayName ?? 'Commuter'}'),
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: const BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppRadii.lg),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.cloud_off_outlined, color: AppColors.primary),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Offline demo · local places and deterministic fares',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Where are you going?',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.radio_button_checked,
                          color: AppColors.primary,
                        ),
                        title: Text(state.pickup.name),
                        subtitle: const Text('Pickup'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.location_on_outlined,
                          color: AppColors.secondary,
                        ),
                        title: Text(
                          state.destination?.name ?? 'Choose destination',
                        ),
                        subtitle: const Text('Destination'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push('/home/search'),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      FilledButton.icon(
                        onPressed: state.destination == null
                            ? () => context.push('/home/search')
                            : () => context.push('/home/ride-options'),
                        icon: Icon(
                          state.destination == null
                              ? Icons.search
                              : Icons.directions_car_outlined,
                        ),
                        label: Text(
                          state.destination == null
                              ? 'Find a destination'
                              : 'Compare ride options',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
