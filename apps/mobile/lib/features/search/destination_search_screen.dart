import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimensions.dart';
import '../../core/widgets/app_row_icon.dart';
import '../../data/providers/repository_providers.dart';
import '../../demo/demo_data.dart';

class DestinationSearchScreen extends ConsumerStatefulWidget {
  const DestinationSearchScreen({super.key});

  @override
  ConsumerState<DestinationSearchScreen> createState() =>
      _DestinationSearchScreenState();
}

class _DestinationSearchScreenState
    extends ConsumerState<DestinationSearchScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(demoStateProvider);
    final normalizedQuery = _query.trim().toLowerCase();
    final matches = DemoData.places
        .where((place) {
          if (place.id == state.pickup.id) return false;
          if (normalizedQuery.isEmpty) return true;
          return place.name.toLowerCase().contains(normalizedQuery) ||
              place.address.toLowerCase().contains(normalizedQuery);
        })
        .toList(growable: false);

    return Scaffold(
      appBar: AppBar(title: const Text('Choose destination')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.sm,
              ),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  hintText: 'Search Calamba demo places',
                  prefixIcon: Icon(Icons.search, size: 18),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  const Icon(
                    Icons.my_location,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Pickup: ${state.pickup.name}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Divider(height: 1),
            Expanded(
              child: matches.isEmpty
                  ? Center(
                      child: Text(
                        'No demo place matches “$_query”.',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      itemCount: matches.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1, indent: 72),
                      itemBuilder: (context, index) {
                        final place = matches[index];
                        return ListTile(
                          minTileHeight: 64,
                          leading: const AppRowIcon(Icons.place_outlined),
                          title: Text(place.name),
                          subtitle: Text(
                            place.address,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onTap: () {
                            state.setDestination(place);
                            context.pushReplacement('/home/ride-options');
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
